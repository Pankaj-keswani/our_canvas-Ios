import Foundation
import FirebaseFirestore
import FirebaseAuth

class DrawingRepository: ObservableObject {
    private let db = Firestore.firestore()

    /// Writes `drawings/{id}.reactions.{senderId}` with the Android-compatible field set.
    /// (emojiName + reactedAt per spec A14; senderName/senderId kept for the shared
    /// Cloud Functions reaction push trigger.)
    func addReaction(drawingId: String, emoji: String, senderName: String, senderId: String) async throws {
        let reactionFields: [String: Any] = [
            "emoji": emoji,
            "emojiName": emoji,
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

        let fields: [String: Any] = [
            "drawingId": mutableDrawing.drawingId,
            "groupId": mutableDrawing.groupId,
            "senderId": mutableDrawing.senderId,
            "recipientIds": mutableDrawing.recipientIds,
            "drawingData": mutableDrawing.drawingData,
            "strokeData": mutableDrawing.strokeData,
            "stickerData": mutableDrawing.stickerData,
            "textData": mutableDrawing.textData,
            "sentAt": FieldValue.serverTimestamp(),
            "isFavorite": mutableDrawing.isFavorite,
        ]
        try await db.collection("drawings").document(mutableDrawing.drawingId).setData(fields)
    }

    func toggleFavorite(drawingId: String, isFavorite: Bool) async throws {
        try await db.collection("drawings").document(drawingId).updateData([
            "isFavorite": isFavorite
        ])
    }
}
