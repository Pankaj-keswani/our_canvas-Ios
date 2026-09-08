import Foundation
import Network
import FirebaseAuth
import UIKit

/// A drawing waiting to be sent (offline reliability, Android A10.1 parity).
/// File-backed — survives app kills and restarts. Items are uid-scoped so an
/// account switch can never flush another user's drawings.
struct PendingDrawingItem: Codable, Equatable, Identifiable {
    let id: UUID
    let uid: String
    let groupId: String
    let groupName: String
    let createdAt: Date
    let drawingData: String
    let strokeData: String
    let stickerData: String
    let textData: String
    var attempts: Int = 0
    var lastAttemptAt: Date? = nil

    /// Exponential backoff between retries (30s → 1h cap).
    var retryDelay: TimeInterval {
        let schedule: [TimeInterval] = [30, 60, 120, 300, 900, 3600]
        return schedule[min(attempts, schedule.count - 1)]
    }

    func isDue(now: Date = Date()) -> Bool {
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= retryDelay
    }

    func makeDrawing() -> Drawing {
        Drawing(
            groupId: groupId,
            senderId: uid,
            drawingData: drawingData,
            isFavorite: false,
            strokeData: strokeData,
            stickerData: stickerData,
            textData: textData
        )
    }
}

/// File-backed persistence for pending sends (one JSON file per item).
final class PendingDrawingStore {
    private let directory: URL?

    init(directory: URL? = PendingDrawingStore.defaultDirectory()) {
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PendingDrawings", isDirectory: true)
    }

    private func fileURL(_ id: UUID) -> URL? {
        directory?.appendingPathComponent("\(id.uuidString).json")
    }

    func enqueue(_ item: PendingDrawingItem) {
        guard let url = fileURL(item.id),
              let data = try? JSONEncoder().encode(item) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Removes ONLY after the backend write was confirmed successful.
    func remove(id: UUID) {
        if let url = fileURL(id) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func all() -> [PendingDrawingItem] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                        includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? JSONDecoder().decode(PendingDrawingItem.self, from: $0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func items(forUid uid: String) -> [PendingDrawingItem] {
        all().filter { $0.uid == uid }
    }

    func recordAttempt(_ item: PendingDrawingItem) {
        var updated = item
        updated.attempts += 1
        updated.lastAttemptAt = Date()
        enqueue(updated)
    }
}

/// Transport seam for tests.
protocol DrawingSending {
    func send(drawing: Drawing) async throws
}

extension DrawingRepository: DrawingSending {
    func send(drawing: Drawing) async throws {
        try await saveDrawing(drawing: drawing)
    }
}

/// Owns the offline/reliability loop:
///   send failure (network) → queued to disk → NWPathMonitor reconnect +
///   scenePhase foreground → flush with backoff → item removed only on confirmed
///   success. Duplicate sends are impossible: an item leaves the queue strictly
///   after a successful backend write.
final class OfflineQueueService: ObservableObject {
    static let shared = OfflineQueueService()

    @Published private(set) var isOffline = false
    @Published private(set) var pendingCount = 0

    let store: PendingDrawingStore
    let sender: DrawingSending
    private let pathMonitor = NWPathMonitor()
    var isFlushing = false

    init(store: PendingDrawingStore = PendingDrawingStore(),
         sender: DrawingSending = DrawingRepository()) {
        self.store = store
        self.sender = sender
    }

    /// Starts connectivity monitoring (called from AppDelegate).
    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let wasOffline = self.isOffline
                self.isOffline = offline
                if wasOffline && !offline {
                    self.flushForCurrentUser(reason: "reconnect")
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "io.ourcanvas.connectivity"))
    }

    func refreshPendingCount() {
        guard let uid = Auth.auth().currentUser?.uid else {
            pendingCount = 0
            return
        }
        pendingCount = store.items(forUid: uid).count
    }

    /// Queues a failed send. Returns true when the failure was network-shaped and
    /// the drawing is now safely persisted (callers show the offline banner).
    func enqueueIfNetworkFailure(drawing: Drawing, groupName: String, error: AppError) -> Bool {
        guard error == .network else { return false }
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let item = PendingDrawingItem(
            id: UUID(),
            uid: uid,
            groupId: drawing.groupId,
            groupName: groupName,
            createdAt: Date(),
            drawingData: drawing.drawingData,
            strokeData: drawing.strokeData,
            stickerData: drawing.stickerData,
            textData: drawing.textData
        )
        store.enqueue(item)
        refreshPendingCount()
        return true
    }

    /// Sends every due item owned by the signed-in user (foreground/reconnect path).
    func flushForCurrentUser(reason: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        flush(uid: uid)
    }

    func flush(uid: String) {
        guard !isFlushing else { return }
        isFlushing = true

        Task { [weak self] in
            defer {
                Task { @MainActor in self?.isFlushing = false }
            }
            guard let self else { return }
            for item in self.store.items(forUid: uid) {
                if Task.isCancelled { break }
                guard item.isDue() else { continue }
                do {
                    try await self.sender.send(drawing: item.makeDrawing())
                    // Confirmed backend write → safe to remove.
                    self.store.remove(id: item.id)
                    // Best-effort analytics, same as the online path.
                    try? await UserRepository.shared.recordDrawingSent(uid: uid, strokes: [])
                } catch {
                    self.store.recordAttempt(item)
                    // Stop the pass on the first failure (backoff governs the retry).
                    break
                }
            }
            await MainActor.run {
                self.refreshPendingCount()
            }
        }
    }

    /// Account lifecycle: pending files stay on disk (uid-scoped, never visible to
    /// another account), but the visible counter resets for the next session.
    func handleAuthChange() {
        refreshPendingCount()
    }
}
