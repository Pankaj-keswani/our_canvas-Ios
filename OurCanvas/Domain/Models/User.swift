import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift

struct User: Codable, Identifiable {
    @DocumentID var id: String?
    var uid: String = ""
    var displayName: String = ""
    var email: String = ""
    var plan: String = "free"
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastActiveDate: String = ""
    var drawingCount: Int = 0
    var favoriteCount: Int = 0
    var groupsJoinedCount: Int = 0
    var reactionsReceivedCount: Int = 0
    var mostUsedColor: String = "#1F2933"
    var mostUsedBrush: String = "Pen"
    var colorCounts: [String: Int] = [:]
    var brushCounts: [String: Int] = [:]
    var profilePictureBase64: String = ""
    var premiumExpiry: Date? = nil
    var premiumSource: String? = nil
    var lastRedeemedCode: String? = nil
    var lastPremiumUpdate: Date? = nil
    var onboardingVersion: Int = 0
    var fcmToken: String? = nil
    var playPurchaseToken: String? = nil
    var playProductId: String? = nil
    var playOrderId: String? = nil
    var appStoreReceipt: String? = nil
    var lastRedeemedPromo: String? = nil
}
