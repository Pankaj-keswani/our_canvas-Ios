import Foundation
import FirebaseFirestore
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
                var fetchedGroups = documents.map { Group.from(documentID: $0.documentID, data: $0.data()) }
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
            throw AppError.permissionDenied
        }

        let groupRef = db.collection("groups").document(groupId)
        let groupSnapshot = try await groupRef.getDocument()
        guard let data = groupSnapshot.data() else {
            throw AppError.notFound("Circle")
        }
        let group = Group.from(documentID: groupSnapshot.documentID, data: data)

        if group.createdBy != currentUser.uid {
            throw AppError.permissionDenied
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
            throw AppError.permissionDenied
        }

        // Deployed rules: members may touch ONLY memberIds (+updatedAt) —
        // removing their own uid. Nothing else may change on a leave.
        let groupRef = db.collection("groups").document(groupId)
        try await groupRef.updateData([
            "memberIds": FieldValue.arrayRemove([currentUser.uid]),
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    /// Owner-only rename. The deployed rules deny this for non-owners even if the
    /// client is modified — callers surface AppError.permissionDenied gracefully.
    func renameGroup(groupId: String, newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CircleRenameRules.isValidName(trimmed) else {
            throw AppError.invalidInput("Circle names need 1–30 characters.")
        }
        try await db.collection("groups").document(groupId).updateData([
            "groupName": trimmed,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }
}
