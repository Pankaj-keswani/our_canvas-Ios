import Foundation
import FirebaseFirestore
import FirebaseAuth

class DrawingRepository: ObservableObject {
    private let db = Firestore.firestore()

    /// Writes `drawings/{id}.reactions.{senderId}` with the Android-compatible field set.
    func addReaction(drawingId: String,
                     emoji: String,
                     emojiName: String,
                     senderName: String,
                     senderId: String) async throws {
        let reactionFields: [String: Any] = [
            "emoji": emoji,
            "emojiName": emojiName.isEmpty ? emoji : emojiName,
            "senderName": senderName,
            "senderId": senderId,
            "reactedAt": FieldValue.serverTimestamp(),
            "profileUrl": "",
        ]
        try await db.collection("drawings").document(drawingId)
            .updateData(["reactions.\(senderId)": reactionFields])
    }

    func getLatestDrawing(groupId: String) async throws -> Drawing? {
        let snapshot = try await db.collection("drawings")
            .whereField("groupId", isEqualTo: groupId)
            .order(by: "sentAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first else { return nil }
        return Drawing.from(documentID: doc.documentID, data: doc.data())
    }

    func listenToDrawings(groupId: String, completion: @escaping ([Drawing]) -> Void) -> ListenerRegistration {
        return db.collection("drawings")
            .whereField("groupId", isEqualTo: groupId)
            .order(by: "sentAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to drawings: \(error)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                let drawings = documents.map { Drawing.from(documentID: $0.documentID, data: $0.data()) }
                completion(drawings)
            }
    }

    /// Creates a drawing document with an explicit field set (new documents only).
    /// `recipientIds` MUST be populated — the shared Android Cloud Function push fan-out
    /// exits early when it is missing.
    func saveDrawing(drawing: Drawing) async throws {
        var mutableDrawing = drawing
        if mutableDrawing.drawingId.isEmpty {
            let newDoc = db.collection("drawings").document()
            mutableDrawing.drawingId = newDoc.documentID
            mutableDrawing.id = newDoc.documentID
        } else if mutableDrawing.id == nil {
            mutableDrawing.id = mutableDrawing.drawingId
        }

        let fields = DrawingFieldBuilder.fields(for: mutableDrawing)
        try await db.collection("drawings").document(mutableDrawing.drawingId).setData(fields)
    }

    /// Free-plan limit support: how many drawings this sender has already sent to the
    /// circle. Fetches up to the limit (+1) — an exact count beyond it is irrelevant.
    func countDrawingsBySender(groupId: String, senderId: String) async throws -> Int {
        let snapshot = try await db.collection("drawings")
            .whereField("groupId", isEqualTo: groupId)
            .whereField("senderId", isEqualTo: senderId)
            .limit(to: DrawingLimits.freeDrawingsPerCircle)
            .getDocuments()
        return snapshot.documents.count
    }

    func toggleFavorite(drawingId: String, isFavorite: Bool) async throws {
        try await db.collection("drawings").document(drawingId).updateData([
            "isFavorite": isFavorite
        ])
    }
}

/// Explicit Firestore field set for drawing documents (unit-testable; keeps the schema
/// exactly Android-compatible — including `recipientIds` for the push fan-out trigger).
enum DrawingFieldBuilder {
    static func fields(for drawing: Drawing) -> [String: Any] {
        [
            "drawingId": drawing.drawingId,
            "groupId": drawing.groupId,
            "senderId": drawing.senderId,
            "recipientIds": drawing.recipientIds,
            "drawingData": drawing.drawingData,
            "strokeData": drawing.strokeData,
            "stickerData": drawing.stickerData,
            "textData": drawing.textData,
            "sentAt": FieldValue.serverTimestamp(),
            "isFavorite": drawing.isFavorite,
        ]
    }
}
