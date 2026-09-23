import Foundation
import FirebaseFirestore

/// Firestore `users/{uid}` model.
///
/// Field names match the Android production schema exactly (spec A14). Decoding is manual and
/// tolerant: unknown fields written by Android (present or future) are ignored, and missing
/// fields fall back to defaults instead of throwing. This model is never used for full-document
/// writes — creation and updates go through `User.creationFields` / `UserFieldUpdate` payloads.
struct User: Identifiable {
    var id: String? = nil
    var uid: String = ""
    var displayName: String = ""
    var email: String = ""
    var createdAt: Date? = nil
    var plan: String = "free"
    var hideEmail: Bool = false
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastActiveDate: String = ""
    var lastActiveAt: Date? = nil
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
    var playPurchaseToken: String? = nil
    var playProductId: String? = nil
    var playOrderId: String? = nil
    var lastRedeemedCode: String? = nil
    var lastPremiumUpdate: Date? = nil
    var whatsNewSeenVersion: Int = 0
    var fcmToken: String? = nil
    var onboardingVersion: Int = 0
    var coins: Int = 3
    var recoveredDates: [String] = []
    var previousBrokenStreak: Int = 0
    var streakBrokenDate: String = ""
    var unlockedBrushes: [String] = []
    var unlockedBackgrounds: [String] = []
    var lastCoinRewardDate: String = ""
    var coinLoginStreak: Int = 0
    var lastLoginDate: String = ""
    var unlockedItems: [String] = []

    // Legacy iOS-only fields tolerated on read; not written anymore.
    var appStoreReceipt: String? = nil
    var lastRedeemedPromo: String? = nil

    var isPro: Bool { plan == "pro" }

    func isItemUnlocked(_ item: String) -> Bool {
        if isPro { return true }
        let lower = item.lowercased()
        if unlockedItems.contains(where: { $0.lowercased() == lower }) { return true }
        if unlockedBrushes.contains(where: { $0.lowercased() == lower }) { return true }
        if unlockedBackgrounds.contains(where: { $0.lowercased() == lower }) { return true }
        return false
    }

    func isBrushUnlocked(_ brush: BrushType) -> Bool {
        guard brush.isCoinUnlockable else { return true }
        if isPro { return true }
        return isItemUnlocked(brush.coinUnlockId) ||
               isItemUnlocked(brush.rawValue) ||
               isItemUnlocked("brush_\(brush.rawValue)")
    }

    func isBackgroundUnlocked(_ template: DrawingBackground.Template) -> Bool {
        guard template.isCoinUnlockable else { return true }
        if isPro { return true }
        return isItemUnlocked(template.coinUnlockId) ||
               isItemUnlocked(template.rawValue) ||
               isItemUnlocked("bg_\(template.rawValue)")
    }
}

extension User {
    /// Tolerant decoding of a `users/{uid}` document, including docs written by Android
    /// with fields this model doesn't know about.
    static func from(documentID: String?, data: [String: Any]) -> User {
        var user = User()
        user.id = documentID ?? FieldCast.string(data["uid"])
        user.uid = user.id ?? ""
        user.displayName = FieldCast.string(data["displayName"]) ?? ""
        user.email = FieldCast.string(data["email"]) ?? ""
        user.plan = FieldCast.string(data["plan"]) ?? "free"
        user.hideEmail = FieldCast.bool(data["hideEmail"]) ?? false
        user.currentStreak = FieldCast.int(data["currentStreak"]) ?? 0
        user.longestStreak = FieldCast.int(data["longestStreak"]) ?? 0
        user.lastActiveDate = FieldCast.string(data["lastActiveDate"]) ?? ""
        user.lastActiveAt = TimestampCast.date(data["lastActiveAt"]) ?? TimestampCast.date(data["lastSeenAt"])
        user.drawingCount = FieldCast.int(data["drawingCount"]) ?? 0
        user.favoriteCount = FieldCast.int(data["favoriteCount"]) ?? 0
        user.groupsJoinedCount = FieldCast.int(data["groupsJoinedCount"]) ?? 0
        user.reactionsReceivedCount = FieldCast.int(data["reactionsReceivedCount"]) ?? 0
        user.mostUsedColor = FieldCast.string(data["mostUsedColor"]) ?? "#1F2933"
        user.mostUsedBrush = FieldCast.string(data["mostUsedBrush"]) ?? "Pen"
        user.colorCounts = FieldCast.intStringMap(data["colorCounts"]) ?? [:]
        user.brushCounts = FieldCast.intStringMap(data["brushCounts"]) ?? [:]
        user.profilePictureBase64 = FieldCast.string(data["profilePictureBase64"]) ?? ""
        user.premiumExpiry = TimestampCast.date(data["premiumExpiry"])
        user.premiumSource = FieldCast.string(data["premiumSource"])
        user.playPurchaseToken = FieldCast.string(data["playPurchaseToken"])
        user.playProductId = FieldCast.string(data["playProductId"])
        user.playOrderId = FieldCast.string(data["playOrderId"])
        user.lastRedeemedCode = FieldCast.string(data["lastRedeemedCode"])
        user.lastPremiumUpdate = TimestampCast.date(data["lastPremiumUpdate"])
        user.whatsNewSeenVersion = FieldCast.int(data["whatsNewSeenVersion"]) ?? 0
        user.fcmToken = FieldCast.string(data["fcmToken"])
        user.onboardingVersion = FieldCast.int(data["onboardingVersion"]) ?? 0
        user.coins = FieldCast.int(data["coins"]) ?? 3
        user.recoveredDates = FieldCast.stringArray(data["recoveredDates"]) ?? []
        user.previousBrokenStreak = FieldCast.int(data["previousBrokenStreak"]) ?? 0
        user.streakBrokenDate = FieldCast.string(data["streakBrokenDate"]) ?? ""
        user.unlockedBrushes = FieldCast.stringArray(data["unlockedBrushes"]) ?? []
        user.unlockedBackgrounds = FieldCast.stringArray(data["unlockedBackgrounds"]) ?? []
        user.lastCoinRewardDate = FieldCast.string(data["lastCoinRewardDate"]) ?? ""
        user.coinLoginStreak = FieldCast.int(data["coinLoginStreak"]) ?? 0
        user.lastLoginDate = FieldCast.string(data["lastLoginDate"]) ?? ""
        user.unlockedItems = FieldCast.stringArray(data["unlockedItems"]) ?? []
        user.createdAt = TimestampCast.date(data["createdAt"])
        user.appStoreReceipt = FieldCast.string(data["appStoreReceipt"])
        user.lastRedeemedPromo = FieldCast.string(data["lastRedeemedPromo"])
        return user
    }

    /// Field set used ONLY when creating a brand-new `users/{uid}` document.
    /// Matches the production Firestore create rules (plan "free", no purchase fields).
    static func creationFields(uid: String, displayName: String, email: String) -> [String: Any] {
        [
            "uid": uid,
            "displayName": displayName,
            "email": email,
            "plan": "free",
            "hideEmail": false,
            "currentStreak": 0,
            "longestStreak": 0,
            "lastActiveDate": "",
            "lastActiveAt": FieldValue.serverTimestamp(),
            "drawingCount": 0,
            "favoriteCount": 0,
            "groupsJoinedCount": 0,
            "reactionsReceivedCount": 0,
            "mostUsedColor": "#1F2933",
            "mostUsedBrush": "Pen",
            "colorCounts": [String: Int](),
            "brushCounts": [String: Int](),
            "profilePictureBase64": "",
            "onboardingVersion": 0,
            "whatsNewSeenVersion": 0,
            "coins": 3,
            "recoveredDates": [String](),
            "previousBrokenStreak": 0,
            "streakBrokenDate": "",
            "unlockedBrushes": [String](),
            "unlockedBackgrounds": [String](),
            "lastCoinRewardDate": "",
            "coinLoginStreak": 0,
            "lastLoginDate": "",
            "unlockedItems": [String](),
            "createdAt": FieldValue.serverTimestamp(),
        ]
    }
}

/// Explicit, narrow field-level update payloads for `users/{uid}`.
/// These exist so partial updates provably touch only their own keys and can be unit tested.
enum UserFieldUpdate {
    static func displayName(_ value: String) -> [String: Any] {
        ["displayName": value]
    }

    static func profilePicture(_ base64: String) -> [String: Any] {
        ["profilePictureBase64": base64]
    }

    static func hideEmail(_ value: Bool) -> [String: Any] {
        ["hideEmail": value]
    }

    static func whatsNewSeenVersion(_ value: Int) -> [String: Any] {
        ["whatsNewSeenVersion": value]
    }

    static func onboardingVersion(_ value: Int) -> [String: Any] {
        ["onboardingVersion": value]
    }

    static func fcmToken(_ value: String) -> [String: Any] {
        ["fcmToken": value]
    }

    static func coins(_ value: Int) -> [String: Any] {
        ["coins": value]
    }

    static func recoveredDates(_ value: [String]) -> [String: Any] {
        ["recoveredDates": value]
    }

    static func previousBrokenStreak(_ value: Int) -> [String: Any] {
        ["previousBrokenStreak": value]
    }

    static func streakBrokenDate(_ value: String) -> [String: Any] {
        ["streakBrokenDate": value]
    }

    static func unlockedBrushes(_ value: [String]) -> [String: Any] {
        ["unlockedBrushes": value]
    }

    static func unlockedBackgrounds(_ value: [String]) -> [String: Any] {
        ["unlockedBackgrounds": value]
    }

    static func unlockedItems(_ value: [String]) -> [String: Any] {
        ["unlockedItems": value]
    }

    static func lastLoginDate(_ value: String) -> [String: Any] {
        ["lastLoginDate": value]
    }

    static func lastActive(day: String? = nil) -> [String: Any] {
        var fields: [String: Any] = [
            "lastActiveAt": FieldValue.serverTimestamp()
        ]
        if let day, !day.isEmpty {
            fields["lastActiveDate"] = day
        }
        return fields
    }
}
