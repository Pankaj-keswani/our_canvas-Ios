import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import UIKit

/// Drives a live Co-Draw session: presence heartbeat, transactional join/leave,
/// streamed local strokes, and progressive remote-stroke rendering through the SAME
/// Phase 1 renderer (no second canvas system).
@MainActor
final class CoDrawViewModel: ObservableObject {

    // MARK: Published state

    @Published private(set) var session: CoDrawSession?
    @Published private(set) var isJoining = false
    @Published private(set) var isActive = false
    @Published private(set) var remoteInkImage: UIImage?
    @Published var errorText: String?

    var participantCount: Int {
        guard let session else { return 0 }
        return CoDrawLifecycle.activeParticipantIds(in: session.participants, now: Date()).count
    }

    var participantNames: [String] {
        guard let session else { return [] }
        let activeIds = CoDrawLifecycle.activeParticipantIds(in: session.participants, now: Date())
        return activeIds.compactMap { session.participants[$0]?.displayName }
    }

    // MARK: Dependencies + internals

    let group: Group
    private let repository: CoDrawRepository
    private var sessionListener: ListenerRegistration?
    private var strokeListener: ListenerRegistration?
    private var heartbeatTimer: Timer?

    private var engine: DrawingEngine?
    private var remoteAccumulators: [String: RemoteStrokeAccumulator] = [:]
    private var processedOpsEventIds = Set<String>()
    private var remoteInk: InkCanvas?
    private var currentLocalStrokeId: String?
    private var localSequence = 0

    var currentUID: String? { Auth.auth().currentUser?.uid }
    var currentUserName: String {
        UserRepository.shared.currentUserProfile?.displayName
            ?? Auth.auth().currentUser?.displayName
            ?? "Someone"
    }

    init(group: Group, repository: CoDrawRepository = CoDrawRepository()) {
        self.group = group
        self.repository = repository
    }

    deinit {
        sessionListener?.remove()
        strokeListener?.remove()
        heartbeatTimer?.invalidate()
    }

    /// Wire the composer's engine: local strokes stream out, remote events render in.
    func connect(engine: DrawingEngine) {
        self.engine = engine
        self.remoteInk = InkCanvas(pixelSize: 720, canvasSize: engine.canvasSize)
        engine.onStrokeProgress = { [weak self] stroke, finished in
            Task { @MainActor in
                self?.handleLocalStrokeProgress(stroke, finished: finished)
            }
        }
    }

    // MARK: - Join / leave

    func join() {
        guard let uid = currentUID else { return }
        isJoining = true
        Task {
            do {
                _ = try await repository.joinSession(groupId: group.groupId,
                                                     userId: uid,
                                                     displayName: currentUserName)
                await MainActor.run {
                    isJoining = false
                    isActive = true
                    startListening()
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                    errorText = AppError.from(error).message
                }
            }
        }
    }

    func leave() {
        guard let uid = currentUID else { return }
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        Task {
            try? await repository.leaveSession(groupId: group.groupId, userId: uid)
        }
        isActive = false
        session = nil
        remoteAccumulators.removeAll()
        processedOpsEventIds.removeAll()
        remoteInkImage = nil
        engine?.onStrokeProgress = nil
    }

    // MARK: - Listeners + heartbeat

    func startListening() {
        guard sessionListener == nil else { return }

        sessionListener = repository.listenToSession(groupId: group.groupId) { [weak self] session in
            DispatchQueue.main.async {
                self?.session = session
                if let session, session.isJoinable {
                    self?.isActive = true
                } else if self?.isActive == true, session?.status == .ended {
                    self?.isActive = false
                }
            }
        }

        strokeListener = repository.listenToLiveStrokes(groupId: group.groupId) { [weak self] events in
            DispatchQueue.main.async {
                self?.applyRemoteEvents(events)
            }
        }

        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: CoDrawLifecycle.heartbeatInterval,
                          repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let uid = self.currentUID, self.isActive else { return }
                try? await self.repository.sendHeartbeat(groupId: self.group.groupId, userId: uid)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    // MARK: - Local stroke streaming

    private func handleLocalStrokeProgress(_ stroke: Stroke, finished: Bool) {
        guard isActive, let uid = currentUID else { return }
        if currentLocalStrokeId == nil {
            currentLocalStrokeId = UUID().uuidString
            localSequence = 0
        }
        guard let strokeId = currentLocalStrokeId else { return }
        localSequence += 1
        let sequence = localSequence
        let strokeIdCopy = strokeId
        let canvasSize = engine?.canvasSize ?? CGSize(width: 1080, height: 1080)

        Task {
            try? await repository.sendStrokePoints(
                groupId: group.groupId,
                strokeId: strokeIdCopy,
                userId: uid,
                points: stroke.points,
                sequence: sequence,
                canvasSize: canvasSize,
                color: stroke.color,
                width: stroke.width,
                brush: stroke.brush,
                isComplete: finished
            )
            if finished {
                currentLocalStrokeId = nil
            }
        }
    }

    /// Composer hook: local undo broadcasts so other participants' canvases match.
    func localUndo() {
        guard isActive, let uid = currentUID else {
            engine?.undo()
            return
        }
        engine?.undo()
        Task {
            try? await repository.broadcastUndo(groupId: group.groupId, userId: uid)
        }
    }

    func localClear() {
        guard isActive, let uid = currentUID else {
            engine?.clearAll()
            return
        }
        engine?.clearAll()
        remoteAccumulators.removeAll()
        Task {
            try? await repository.broadcastClear(groupId: group.groupId, userId: uid)
        }
    }

    // MARK: - Remote events

    private func applyRemoteEvents(_ events: [CoDrawLiveStroke]) {
        guard let engine else { return }
        let localCanvas = engine.canvasSize
        let myUid = currentUID ?? ""

        for event in events {
            // Own events already rendered locally.
            if event.userId == myUid { continue }

            switch event.kind {
            case .stroke:
                if remoteAccumulators[event.id] == nil {
                    remoteAccumulators[event.id] = RemoteStrokeAccumulator(
                        userId: event.userId,
                        color: event.color,
                        width: event.width,
                        brush: event.brush
                    )
                }
                remoteAccumulators[event.id]?.append(points: event.points,
                                                      sequence: event.sequence,
                                                      sourceCanvas: event.canvasSize,
                                                      localCanvasSize: localCanvas)
                if event.isComplete {
                    markRemoteStrokeComplete(event.id)
                }
            case .undo:
                guard !processedOpsEventIds.contains(event.id) else { continue }
                processedOpsEventIds.insert(event.id)
                engine.removeLastStroke(ownerId: event.userId)
                if let newestKey = newestAccumulatorKey(for: event.userId) {
                    remoteAccumulators.removeValue(forKey: newestKey)
                    completedRemoteStrokeIds.remove(newestKey)
                    committedRemoteStrokeIds.remove(newestKey)
                }
            case .clear:
                guard !processedOpsEventIds.contains(event.id) else { continue }
                processedOpsEventIds.insert(event.id)
                engine.applyRemoteClear()
                remoteAccumulators.removeAll()
                completedRemoteStrokeIds.removeAll()
                committedRemoteStrokeIds.removeAll()
            }
        }

        rebuildRemoteInk()
    }

    private func newestAccumulatorKey(for userId: String) -> String? {
        remoteAccumulators
            .filter { $0.value.stroke.ownerId == userId }
            .max { $0.value.lastSequence < $1.value.lastSequence }?
            .key
    }

    /// Completed remote strokes are committed into the engine exactly once; strokes
    /// still in flight render progressively through the shared renderer into a
    /// preview ink bitmap layered over the canvas.
    private func rebuildRemoteInk() {
        guard let engine else { return }

        for strokeId in completedRemoteStrokeIds where !committedRemoteStrokeIds.contains(strokeId) {
            guard let accumulator = remoteAccumulators[strokeId] else {
                committedRemoteStrokeIds.insert(strokeId)
                continue
            }
            engine.appendRemoteStroke(accumulator.stroke)
            committedRemoteStrokeIds.insert(strokeId)
            remoteAccumulators.removeValue(forKey: strokeId)
        }

        if let remoteInk {
            remoteInk.reset(with: remoteAccumulators.values.map { $0.stroke })
            remoteInkImage = remoteInk.image
        }
    }

    private var completedRemoteStrokeIds: Set<String> = []
    private var committedRemoteStrokeIds: Set<String> = []

    private func markRemoteStrokeComplete(_ strokeId: String) {
        completedRemoteStrokeIds.insert(strokeId)
    }
}
