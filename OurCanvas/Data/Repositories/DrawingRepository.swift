import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import FirebaseAuth

class DrawingRepository: ObservableObject {
    private let db = Firestore.firestore()
    
    func addReaction(drawingId: String, emoji: String, senderName: String, senderId: String) async throws {
        let drawingRef = db.collection("drawings").document(drawingId)
        let reaction = ReactionInfo(emoji: emoji, senderName: senderName, senderId: senderId, profileUrl: "")
        
        guard let encodedReaction = try? Firestore.Encoder().encode(reaction) else { return }
        
        let updateData: [String: Any] = [
            "reactions.\(senderId)": encodedReaction
        ]
        try await drawingRef.updateData(updateData)
    }
    
    func getLatestDrawing(groupId: String) async throws -> Drawing? {
        let snapshot = try await db.collection("drawings")
            .whereField("groupId", isEqualTo: groupId)
            .order(by: "sentAt", descending: true)
            .limit(to: 1)
            .getDocuments()
            
        return try snapshot.documents.first?.data(as: Drawing.self)
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
                let drawings = documents.compactMap { try? $0.data(as: Drawing.self) }
                completion(drawings)
            }
    }
    
    func saveDrawing(drawing: Drawing) async throws {
        var mutableDrawing = drawing
        if mutableDrawing.id == nil {
            if mutableDrawing.drawingId.isEmpty {
                let newDoc = db.collection("drawings").document()
                mutableDrawing.drawingId = newDoc.documentID
                mutableDrawing.id = newDoc.documentID
            } else {
                mutableDrawing.id = mutableDrawing.drawingId
            }
        }
        
        try db.collection("drawings").document(mutableDrawing.drawingId).setData(from: mutableDrawing)
    }
    
    func toggleFavorite(drawingId: String, isFavorite: Bool) async throws {
        try await db.collection("drawings").document(drawingId).updateData([
            "isFavorite": isFavorite
        ])
    }
}
