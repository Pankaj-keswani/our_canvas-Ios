import Foundation
import CoreGraphics

/// `co_draw_sessions/{groupId}` model — field names match the Android schema (A5.2).
struct CoDrawSession: Equatable, Identifiable {
    enum Status: String {
        case active = "ACTIVE"
        case ended = "ENDED"

        static func from(_ raw: String?) -> Status? {
            guard let raw else { return nil } // missing status field → broken session
            return Status(rawValue: raw)
        }
    }

    struct Participant: Equatable {
        var displayName: String = "Someone"
        var joinedAt: Date? = nil
        var isActive: Bool = false
        var lastSeenAt: Date? = nil

        static func from(data: [String: Any]) -> Participant {
            var participant = Participant()
            participant.displayName = FieldCast.string(data["displayName"]) ?? "Someone"
            participant.joinedAt = TimestampCast.date(data["joinedAt"])
            participant.isActive = FieldCast.bool(data["isActive"]) ?? false
            participant.lastSeenAt = TimestampCast.date(data["lastSeenAt"])
            return participant
        }

        func fields() -> [String: Any] {
            [
                "displayName": displayName,
                "joinedAt": joinedAt.map { Timestamp(date: $0) } ?? FieldValue.serverTimestamp(),
                "isActive": true,
                "lastSeenAt": FieldValue.serverTimestamp(),
            ]
        }
    }

    let id: String // == groupId
    let groupId: String
    let status: Status?
    let participants: [String: Participant]
    let activeParticipantCount: Int
    let createdBy: String
    let createdAt: Date?
    let lastActivityAt: Date?

    /// Freshly computed count (stale participants excluded) — the stored
    /// activeParticipantCount may lag heartbeats.
    var liveActiveCount: Int {
        CoDrawLifecycle.activeParticipantIds(in: participants, now: Date()).count
    }

    var isJoinable: Bool {
        status == .active && liveActiveCount > 0
    }

    static func from(documentID: String, data: [String: Any]) -> CoDrawSession {
        var participants: [String: Participant] = [:]
        if let rawParticipants = data["participants"] as? [String: [String: Any]] {
            for (uid, raw) in rawParticipants {
                participants[uid] = Participant.from(data: raw)
            }
        }
        return CoDrawSession(
            id: documentID,
            groupId: FieldCast.string(data["groupId"]) ?? documentID,
            status: Status.from(FieldCast.string(data["status"])),
            participants: participants,
            activeParticipantCount: FieldCast.int(data["activeParticipantCount"]) ?? 0,
            createdBy: FieldCast.string(data["createdBy"]) ?? "",
            createdAt: TimestampCast.date(data["createdAt"]),
            lastActivityAt: TimestampCast.date(data["lastActivityAt"])
        )
    }
}

/// `live_strokes/{strokeId}` document — either a streamed stroke (point batches,
/// monotonic sequence per stroke) or a synchronized operation broadcast.
struct CoDrawLiveStroke: Equatable, Identifiable {
    enum Kind: String {
        case stroke
        case undo = "DELETE_STROKE"
        case clear = "CLEAR"
    }

    let id: String
    let userId: String
    let kind: Kind
    let points: [CGPoint]
    let sequence: Int
    let isComplete: Bool
    let canvasW: CGFloat
    let canvasH: CGFloat
    let color: Int
    let width: CGFloat
    let brush: BrushType

    var canvasSize: CGSize { CGSize(width: canvasW, height: canvasH) }

    static func from(documentID: String, data: [String: Any]) -> CoDrawLiveStroke {
        let op = FieldCast.string(data["op"]) ?? Kind.stroke.rawValue
        let kind = Kind(rawValue: op) ?? .stroke
        var points: [CGPoint] = []
        if let batches = data["points"] as? [[Any]] {
            for batch in batches where batch.count >= 2 {
                let x = FieldCast.double(batch[0]) ?? 0
                let y = FieldCast.double(batch[1]) ?? 0
                points.append(CGPoint(x: x, y: y))
            }
        }
        return CoDrawLiveStroke(
            id: documentID,
            userId: FieldCast.string(data["userId"]) ?? "",
            kind: kind,
            points: points,
            sequence: FieldCast.int(data["seq"]) ?? 0,
            isComplete: FieldCast.bool(data["isComplete"]) ?? false,
            canvasW: CGFloat(FieldCast.double(data["canvasW"]) ?? 1080),
            canvasH: CGFloat(FieldCast.double(data["canvasH"]) ?? 1080),
            color: FieldCast.int(data["c"]) ?? 0xFF000000,
            width: CGFloat(FieldCast.double(data["w"]) ?? 12),
            brush: BrushType.from(androidID: FieldCast.int(data["b"]) ?? 0)
        )
    }

    func fields() -> [String: Any] {
        var fields: [String: Any] = [
            "userId": userId,
            "op": kind.rawValue,
            "seq": sequence,
            "isComplete": isComplete,
            "canvasW": Double(canvasW),
            "canvasH": Double(canvasH),
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if kind == .stroke {
            fields["points"] = points.map { [Double($0.x), Double($0.y)] as [Any] }
            fields["c"] = color
            fields["w"] = Double(width)
            fields["b"] = brush.androidID
        }
        return fields
    }
}

/// Session lifecycle rules (pure, tested) — Android parity:
/// heartbeat every 45s, staleness window 5 minutes, self-healing restart when the
/// session is ENDED / has zero active participants / has a missing status field.
enum CoDrawLifecycle {
    static let heartbeatInterval: TimeInterval = 45
    static let staleThreshold: TimeInterval = 5 * 60

    /// A participant counts as active when flagged active AND seen within the window.
    static func isActive(_ participant: CoDrawSession.Participant, now: Date) -> Bool {
        guard participant.isActive else { return false }
        guard let lastSeen = participant.lastSeenAt else { return false }
        return now.timeIntervalSince(lastSeen) < staleThreshold
    }

    static func activeParticipantIds(in participants: [String: CoDrawSession.Participant],
                                      now: Date) -> [String] {
        participants.filter { isActive($0.value, now: now) }.map { $0.key }.sorted()
    }

    /// Broken sessions self-heal by creating a fresh one on join.
    static func requiresNewSession(_ session: CoDrawSession?, now: Date = Date()) -> Bool {
        guard let session else { return true }
        if session.status == nil { return true }              // missing status field
        if session.status == .ended { return true }           // ENDED
        if activeParticipantIds(in: session.participants, now: now).isEmpty { return true } // zero present
        return false
    }

    /// Remote-canvas scaling: map a point from the sender's canvas space into ours.
    static func scalePoint(_ point: CGPoint,
                           from source: CGSize,
                           to target: CGSize) -> CGPoint {
        guard source.width > 0, source.height > 0 else { return point }
        let sx = target.width / source.width
        let sy = target.height / source.height
        // Uniform scale keeps relative positions/aspect across devices.
        let s = min(sx, sy)
        let offsetX = (target.width - source.width * s) / 2
        let offsetY = (target.height - source.height * s) / 2
        return CGPoint(x: point.x * s + offsetX, y: point.y * s + offsetY)
    }

    /// Monotonic per-stroke sequence validation: batches must arrive in order.
    static func isOrdered(sequences: [Int]) -> Bool {
        zip(sequences, sequences.dropFirst()).allSatisfy { $0.0 < $0.1 }
    }
}

/// Accumulates remote point batches into progressively-renderable strokes.
struct RemoteStrokeAccumulator: Equatable {
    private(set) var stroke: Stroke
    private(set) var lastSequence = 0

    init(userId: String, color: Int, width: CGFloat, brush: BrushType, canvasSize: CGSize) {
        var initial = Stroke()
        initial.color = color
        initial.width = width
        initial.brush = brush
        initial.ownerId = userId
        self.stroke = initial
        self.canvasSize = canvasSize
    }

    fileprivate var canvasSize: CGSize

    /// Appends a batch (ignores out-of-order/duplicate sequences) after scaling the
    /// sender's canvas space into `localCanvasSize`.
    mutating func append(points: [CGPoint], sequence: Int, sourceCanvas: CGSize, localCanvasSize: CGSize) {
        guard sequence > lastSequence else { return }
        lastSequence = sequence
        for point in points {
            stroke.points.append(CoDrawLifecycle.scalePoint(point, from: sourceCanvas, to: localCanvasSize))
        }
    }
}
