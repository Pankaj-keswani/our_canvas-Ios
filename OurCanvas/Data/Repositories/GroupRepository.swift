import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import FirebaseAuth

class GroupRepository: ObservableObject {
    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    @Published var groups: [Group] = []
    
    func listenToUserGroups() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        listenerRegistration?.remove()
        
        listenerRegistration = db.collection("groups")
            .whereField("memberIds", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to groups: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                var fetchedGroups = documents.compactMap { try? $0.data(as: Group.self) }
                fetchedGroups.sort { $0.groupName.lowercased() < $1.groupName.lowercased() }
                
                DispatchQueue.main.async {
                    self.groups = fetchedGroups
                }
            }
    }
    
    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }
    
    func deleteGroupWithDrawings(groupId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        
        let groupRef = db.collection("groups").document(groupId)
        let groupSnapshot = try await groupRef.getDocument()
        guard let group = try? groupSnapshot.data(as: Group.self) else {
            throw NSError(domain: "Group", code: 404, userInfo: [NSLocalizedDescriptionKey: "Circle not found"])
        }
        
        if group.createdBy != currentUser.uid {
            throw NSError(domain: "Group", code: 403, userInfo: [NSLocalizedDescriptionKey: "Only creator can delete"])
        }
        
        let drawingsSnapshot = try await db.collection("drawings").whereField("groupId", isEqualTo: groupId).getDocuments()
        
        let batch = db.batch()
        for doc in drawingsSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        batch.deleteDocument(groupRef)
        try await batch.commit()
    }
    
    func leaveGroup(groupId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        
        let groupRef = db.collection("groups").document(groupId)
        try await groupRef.updateData([
            "memberIds": FieldValue.arrayRemove([currentUser.uid])
        ])
    }
}
