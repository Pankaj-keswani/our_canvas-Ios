import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Repository for `co_draw_sessions/{groupId}` (+ `live_strokes` / `strokes`
/// subcollections). Joins/leaves run inside Firestore transactions so simultaneous
/// joiners can never create duplicate or conflicting sessions.
final class CoDrawRepository {

    private let db = Firestore.firestore()

    private func sessionRef(_ groupId: String) -> DocumentReference {
        db.collection("co_draw_sessions").document(groupId)
    }

    // MARK: - Join / leave (transactional)

    /// Joins the live session for the group, creating a fresh one when the current
    /// session is ENDED / empty / missing its status field (Android self-heal rules).
    @discardableResult
    func joinSession(groupId: String,
                     userId: String,
                     displayName: String,
                     now: Date = Date()) async throws -> Bool {
        let ref = sessionRef(groupId)
        let createdNewResult: Any? = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return false
            }

            var requiresNew = true
            let data = snapshot.data() ?? [:]
            if snapshot.exists {
                let session = CoDrawSession.from(documentID: snapshot.documentID, data: data)
                requiresNew = CoDrawLifecycle.requiresNewSession(session, now: now)
            }

            let participantFields: [String: Any] = [
                "displayName": displayName,
                "joinedAt": FieldValue.serverTimestamp(),
                "isActive": true,
                "lastSeenAt": FieldValue.serverTimestamp(),
            ]

            if requiresNew {
                let fields: [String: Any] = [
                    "groupId": groupId,
                    "status": CoDrawSession.Status.active.rawValue,
                    "participants": [userId: participantFields],
                    "activeParticipantCount": 1,
                    "createdBy": userId,
                    "createdAt": FieldValue.serverTimestamp(),
                    "lastActivityAt": FieldValue.serverTimestamp(),
                ]
                transaction.setData(fields, forDocument: ref)
                return true
            } else {
                // Recompute presence including the joiner (stale participants excluded).
                var session = CoDrawSession.from(documentID: snapshot.documentID, data: data)
                var participants = session.participants
                participants[userId] = CoDrawSession.Participant(displayName: displayName,
                                                                 joinedAt: nil,
                                                                 isActive: true,
                                                                 lastSeenAt: now)
                session = CoDrawSession(id: session.id, groupId: session.groupId, status: session.status,
                                        participants: participants,
                                        activeParticipantCount: session.activeParticipantCount,
                                        createdBy: session.createdBy, createdAt: session.createdAt,
                                        lastActivityAt: session.lastActivityAt)
                let activeCount = CoDrawLifecycle.activeParticipantIds(in: participants, now: now).count

                transaction.setData(["participants.\(userId)": participantFields], forDocument: ref, merge: true)
                transaction.updateData([
                    "activeParticipantCount": Int64(activeCount),
                    "status": CoDrawSession.Status.active.rawValue,
                    "lastActivityAt": FieldValue.serverTimestamp(),
                ], forDocument: ref)
                return false
            }
        }
        let createdNew = (createdNewResult as? Bool) ?? false
        return createdNew
    }

    /// Leave + mark inactive; ends the session when nobody present remains.
    func leaveSession(groupId: String, userId: String, now: Date = Date()) async throws {
        let ref = sessionRef(groupId)
        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard snapshot.exists, let data = snapshot.data() else { return nil }

            let session = CoDrawSession.from(documentID: snapshot.documentID, data: data)

            var departure: [String: Any] = ((data["participants"] as? [String: Any])?[userId] as? [String: Any]) ?? [:]
            departure["isActive"] = false
            departure["lastSeenAt"] = FieldValue.serverTimestamp()
            transaction.setData(["participants.\(userId)": departure], forDocument: ref, merge: true)

            // Recompute presence ignoring the leaver.
            var participants = session.participants
            participants[userId]?.isActive = false
            let remaining = CoDrawLifecycle.activeParticipantIds(in: participants, now: now)
            if remaining.isEmpty {
                transaction.updateData([
                    "status": CoDrawSession.Status.ended.rawValue,
                    "activeParticipantCount": 0,
                    "lastActivityAt": FieldValue.serverTimestamp(),
                ], forDocument: ref)
            } else {
                transaction.updateData([
                    "activeParticipantCount": Int64(remaining.count),
                    "lastActivityAt": FieldValue.serverTimestamp(),
                ], forDocument: ref)
            }
            return nil
        }
    }

    /// 45-second presence heartbeat.
    func sendHeartbeat(groupId: String, userId: String) async throws {
        try await sessionRef(groupId).updateData([
            "participants.\(userId).isActive": true,
            "participants.\(userId).lastSeenAt": FieldValue.serverTimestamp(),
            "lastActivityAt": FieldValue.serverTimestamp(),
        ])
    }

    // MARK: - Listeners

    func listenToSession(groupId: String,
                         onChange: @escaping (CoDrawSession?) -> Void) -> ListenerRegistration {
        sessionRef(groupId).addSnapshotListener { snapshot, error in
            if let error {
                print("CoDraw session listener error: \(error.localizedDescription)")
                return
            }
            guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                onChange(nil)
                return
            }
            onChange(CoDrawSession.from(documentID: snapshot.documentID, data: data))
        }
    }

    func listenToLiveStrokes(groupId: String,
                             onChange: @escaping ([CoDrawLiveStroke]) -> Void) -> ListenerRegistration {
        sessionRef(groupId).collection("live_strokes")
            .order(by: "createdAt")
            .limit(toLast: 200)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("CoDraw live_strokes listener error: \(error.localizedDescription)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                let events = documents.map { CoDrawLiveStroke.from(documentID: $0.documentID, data: $0.data()) }
                onChange(events)
            }
    }

    // MARK: - Live strokes

    private func liveStrokeRef(groupId: String, strokeId: String) -> DocumentReference {
        sessionRef(groupId).collection("live_strokes").document(strokeId)
    }

    /// Streams a point batch for a stroke (monotonic `seq` per stroke).
    func sendStrokePoints(groupId: String,
                          strokeId: String,
                          userId: String,
                          points: [CGPoint],
                          sequence: Int,
                          canvasSize: CGSize,
                          color: Int,
                          width: CGFloat,
                          brush: BrushType,
                          isComplete: Bool) async throws {
        var fields: [String: Any] = [
            "userId": userId,
            "op": CoDrawLiveStroke.Kind.stroke.rawValue,
            "seq": sequence,
            "isComplete": isComplete,
            "canvasW": Double(canvasSize.width),
            "canvasH": Double(canvasSize.height),
            "c": color,
            "w": Double(width),
            "b": brush.androidID,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        fields["points"] = points.map { [Double($0.x), Double($0.y)] as [Any] }
        try await liveStrokeRef(groupId: groupId, strokeId: strokeId).setData(fields, merge: true)
    }

    /// Commits a finished stroke to the archive subcollection (Android `strokes/`).
    func archiveStroke(groupId: String, strokeId: String, stroke: CoDrawLiveStroke) async throws {
        try await sessionRef(groupId).collection("strokes").document(strokeId)
            .setData(stroke.fields())
    }

    // MARK: - Synchronized operations

    /// Broadcasts an undo of the sender's own latest stroke (Android op semantics —
    /// a local undo never silently alters another participant's stroke).
    func broadcastUndo(groupId: String, userId: String) async throws {
        let fields: [String: Any] = [
            "userId": userId,
            "op": CoDrawLiveStroke.Kind.undo.rawValue,
            "seq": 0,
            "isComplete": true,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        try await sessionRef(groupId).collection("live_strokes").document().setData(fields)
    }

    func broadcastClear(groupId: String, userId: String) async throws {
        let fields: [String: Any] = [
            "userId": userId,
            "op": CoDrawLiveStroke.Kind.clear.rawValue,
            "seq": 0,
            "isComplete": true,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        try await sessionRef(groupId).collection("live_strokes").document().setData(fields)
    }
}
