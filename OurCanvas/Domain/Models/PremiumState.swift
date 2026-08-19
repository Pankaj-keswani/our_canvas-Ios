import Foundation
import FirebaseFirestore

enum ListenerStatus: String, Codable {
    case WAITING
    case CONNECTED
    case DISCONNECTED
}

struct PremiumState: Codable {
    var isPremium: Bool = false
    var premiumSource: String? = nil
    var premiumExpiry: Timestamp? = nil
    var isLifetime: Bool = false
    var listenerStatus: ListenerStatus = .WAITING
    var lastSyncTime: Timestamp? = nil
    var isLoading: Bool = false
    var lastError: String? = nil
}
