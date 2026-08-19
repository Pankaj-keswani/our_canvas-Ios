import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift

struct ReactionInfo: Codable {
    var emoji: String = ""
    var senderName: String = ""
    var senderId: String = ""
    var profileUrl: String = ""
}

struct Drawing: Codable, Identifiable {
    @DocumentID var id: String?
    var drawingId: String = ""
    var groupId: String = ""
    var senderId: String = ""
    var drawingData: String = ""
    var isFavorite: Bool = false
    @ServerTimestamp var sentAt: Timestamp?
    var strokeData: String = ""
    var reaction: String = ""
    var reactionSenderName: String = ""
    var reactionSenderId: String = ""
    var reactions: [String: ReactionInfo] = [:]
    var stickerData: String = ""
    var textData: String = ""
}
