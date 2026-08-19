import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift

struct Group: Codable, Identifiable {
    @DocumentID var id: String?
    var groupId: String = ""
    var groupName: String = ""
    var groupType: String = ""
    var createdBy: String = ""
    var createdAt: Int64? = nil
    var inviteCode: String = ""
    var memberIds: [String] = []
}
