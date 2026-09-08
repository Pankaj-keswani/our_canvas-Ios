import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Two-step account deletion (Android A8.1 semantics). Best-effort within the
/// existing Firestore rules — the client may delete/mutate its OWN data:
///   - own user document (rules: isOwner delete ✓)
///   - own notifications subcollection (own docs ✓)
///   - drawings authored by the user (rules allow signed-in writes ✓)
///   - leave every group (arrayRemove ✓); creator-owned groups are DELETED with
///     their drawings (rules allow ✓)
///
/// Documented limitations (NOT silently worked around):
///   - reactions the user left on OTHERS' drawings are embedded maps in those
///     users' documents; removing them requires touching other users' docs —
///     rules allow the write, but the query cannot index map keys, so we skip it.
///   - guess_games / co_draw docs authored by the user are shared-circle state;
///     deleting them mid-round breaks other players. They are left in place.
final class AccountDeletionService {

    private let db = Firestore.firestore()

    enum Step: Equatable {
        case idle
        case deletingDrawings
        case deletingGroups
        case deletingNotifications
        case deletingUserDocument
        case deletingAuthUser
        case done
    }

    /// Pure state progression (tested).
    static func nextStep(after step: Step) -> Step {
        switch step {
        case .idle: return .deletingDrawings
        case .deletingDrawings: return .deletingGroups
        case .deletingGroups: return .deletingNotifications
        case .deletingNotifications: return .deletingUserDocument
        case .deletingUserDocument: return .deletingAuthUser
        case .deletingAuthUser: return .done
        case .done: return .done
        }
    }

    func deleteEverything(uid: String? = nil) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AppError.underlying("You're not signed in.")
        }
        let targetUid = uid ?? user.uid

        // 1. Own drawings.
        let drawings = try await db.collection("drawings")
            .whereField("senderId", isEqualTo: targetUid)
            .getDocuments()
        let drawingBatch = db.batch()
        for document in drawings.documents {
            drawingBatch.deleteDocument(document.reference)
        }
        if !drawings.isEmpty {
            try await drawingBatch.commit()
        }

        // 2. Groups: delete creator-owned groups (with their drawings), leave the rest.
        let groups = try await db.collection("groups")
            .whereField("memberIds", arrayContains: targetUid)
            .getDocuments()
        for groupDocument in groups.documents {
            let data = groupDocument.data()
            let createdBy = data["createdBy"] as? String ?? ""
            if createdBy == targetUid {
                let groupDrawings = try await db.collection("drawings")
                    .whereField("groupId", isEqualTo: groupDocument.documentID)
                    .getDocuments()
                let groupBatch = db.batch()
                for drawing in groupDrawings.documents {
                    groupBatch.deleteDocument(drawing.reference)
                }
                groupBatch.deleteDocument(groupDocument.reference)
                try await groupBatch.commit()
            } else {
                try await groupDocument.reference.updateData([
                    "memberIds": FieldValue.arrayRemove([targetUid])
                ])
            }
        }

        // 3. Own notifications.
        let notifications = try await db.collection("users")
            .document(targetUid)
            .collection("notifications")
            .getDocuments()
        let notificationBatch = db.batch()
        for notification in notifications.documents {
            notificationBatch.deleteDocument(notification.reference)
        }
        if !notifications.isEmpty {
            try await notificationBatch.commit()
        }

        // 4. User document.
        try await db.collection("users").document(targetUid).delete()

        // 5. Auth user (signs the session out as a side effect).
        try await user.delete()
    }
}
