import Foundation

enum DiscoveryFlag: String, CaseIterable {
    case drawingTools = "drawing_tools"
    case widgetConfig = "widget_config"
    case premium = "premium"
}

/// Notification preference categories exposed in Settings. Every push type maps
/// to exactly one category; a muted category suppresses BOTH the banner and the
/// in-app history entry for its push types on this device.
enum NotificationCategory: String, CaseIterable {
    case drawings
    case reactions
    case games
    case other
}

struct NotificationPreferences: Codable, Equatable {
    var newDrawingEnabled: Bool = true
    var newReactionEnabled: Bool = true
    var gameEventsEnabled: Bool = true
    var otherEnabled: Bool = true

    init() {}

    init(newDrawingEnabled: Bool = true,
         newReactionEnabled: Bool = true,
         gameEventsEnabled: Bool = true,
         otherEnabled: Bool = true) {
        self.newDrawingEnabled = newDrawingEnabled
        self.newReactionEnabled = newReactionEnabled
        self.gameEventsEnabled = gameEventsEnabled
        self.otherEnabled = otherEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case newDrawingEnabled
        case newReactionEnabled
        case gameEventsEnabled
        case otherEnabled
    }

    /// Migration-safe decode: preferences stored by older app versions carry only
    /// the two original keys — the new categories default to ON, and previously
    /// saved OFF states are preserved.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        newDrawingEnabled = try container.decodeIfPresent(Bool.self, forKey: .newDrawingEnabled) ?? true
        newReactionEnabled = try container.decodeIfPresent(Bool.self, forKey: .newReactionEnabled) ?? true
        gameEventsEnabled = try container.decodeIfPresent(Bool.self, forKey: .gameEventsEnabled) ?? true
        otherEnabled = try container.decodeIfPresent(Bool.self, forKey: .otherEnabled) ?? true
    }

    /// Push type → category (pure, tested). Unknown future types land in `other`.
    static func category(for pushType: PushPayload.PushType) -> NotificationCategory {
        switch pushType {
        case .newDrawing: return .drawings
        case .newReaction: return .reactions
        case .newGameTurn, .guessResult: return .games
        case .memberJoined: return .other
        }
    }

    /// The actual gate: is this push type allowed to banner/persist right now?
    func isEnabled(for pushType: PushPayload.PushType) -> Bool {
        switch Self.category(for: pushType) {
        case .drawings: return newDrawingEnabled
        case .reactions: return newReactionEnabled
        case .games: return gameEventsEnabled
        case .other: return otherEnabled
        }
    }
}

/// User-scoped local state, mirroring the Android SharedPreferences/DataStore keys
/// that are keyed per account (e.g. `whats_new` → `seen_{uid}`, `guess_reveals` → `{gameId}_{uid}`).
/// All keys are namespaced with the uid so account switches never leak state.
struct UserScopedStore {
    let uid: String
    private let defaults: UserDefaults

    init(uid: String, defaults: UserDefaults = .standard) {
        self.uid = uid
        self.defaults = defaults
    }

    private func scopedKey(_ name: String) -> String {
        "user.\(uid).\(name)"
    }

    // MARK: - Onboarding

    static let currentOnboardingVersion = 1

    var onboardingVersion: Int {
        get { defaults.integer(forKey: scopedKey("onboardingVersion")) }
        set { defaults.set(newValue, forKey: scopedKey("onboardingVersion")) }
    }

    var onboardingCompleted: Bool {
        onboardingVersion >= Self.currentOnboardingVersion
    }

    // MARK: - Walkthrough / discovery

    var walkthroughStep: Int {
        get { defaults.integer(forKey: scopedKey("walkthroughStep")) }
        set { defaults.set(newValue, forKey: scopedKey("walkthroughStep")) }
    }

    func isDiscovered(_ flag: DiscoveryFlag) -> Bool {
        defaults.bool(forKey: scopedKey("discovered.\(flag.rawValue)"))
    }

    func setDiscovered(_ flag: DiscoveryFlag) {
        defaults.set(true, forKey: scopedKey("discovered.\(flag.rawValue)"))
    }

    // MARK: - What's New (versioned seen flag; Android mirrors this in Firestore too)

    var whatsNewSeenVersion: Int {
        get { defaults.integer(forKey: scopedKey("whatsNewSeenVersion")) }
        set { defaults.set(newValue, forKey: scopedKey("whatsNewSeenVersion")) }
    }

    // MARK: - Notification preferences

    var notificationPreferences: NotificationPreferences {
        get {
            guard let data = defaults.data(forKey: scopedKey("notificationPreferences")) else {
                return NotificationPreferences()
            }
            return (try? JSONDecoder().decode(NotificationPreferences.self, from: data)) ?? NotificationPreferences()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: scopedKey("notificationPreferences"))
            }
        }
    }

    // MARK: - Per-group last-visit timestamps (unseen drawings badge)

    func lastVisit(forGroup groupId: String) -> Date? {
        let key = scopedKey("group.lastVisit.\(groupId)")
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }

    func setLastVisit(_ date: Date, forGroup groupId: String) {
        defaults.set(date.timeIntervalSince1970, forKey: scopedKey("group.lastVisit.\(groupId)"))
    }

    // MARK: - Onboarding completion actions

    /// `action_create` flag: set by onboarding completion, consumed once by MainTab.
    var postOnboardingCreate: Bool {
        get { defaults.bool(forKey: scopedKey("postOnboardingCreate")) }
        set { defaults.set(newValue, forKey: scopedKey("postOnboardingCreate")) }
    }

    mutating func consumePostOnboardingCreate() -> Bool {
        guard postOnboardingCreate else { return false }
        postOnboardingCreate = false
        return true
    }

    // MARK: - Guess My Doodle reveals (later phase; key mirrors Android `{gameId}_{uid}`)

    func revealedWord(gameId: String) -> String? {
        defaults.string(forKey: scopedKey("guessReveals.\(gameId)_\(uid)"))
    }

    func setRevealedWord(_ word: String, gameId: String) {
        defaults.set(word, forKey: scopedKey("guessReveals.\(gameId)_\(uid)"))
    }

    // MARK: - Profile cache metadata (10-minute TTL parity with Android)

    var profileCacheUpdatedAt: Date? {
        get {
            let key = scopedKey("profileCache.updatedAt")
            guard defaults.object(forKey: key) != nil else { return nil }
            return Date(timeIntervalSince1970: defaults.double(forKey: key))
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: scopedKey("profileCache.updatedAt"))
            } else {
                defaults.removeObject(forKey: scopedKey("profileCache.updatedAt"))
            }
        }
    }
}

/// Device-level (not user-scoped) local state.
struct DeviceLocalStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Cached FCM token so association can happen whenever the user logs in.
    var cachedFCMToken: String? {
        get { defaults.string(forKey: "device.fcmToken") }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "device.fcmToken")
            } else {
                defaults.removeObject(forKey: "device.fcmToken")
            }
        }
    }

    var notificationsPermissionRequested: Bool {
        get { defaults.bool(forKey: "device.notificationsPermissionRequested") }
        set { defaults.set(newValue, forKey: "device.notificationsPermissionRequested") }
    }

    /// Deep link that arrived before the router/Main was ready (cold launch).
    /// Consumed once routing is possible.
    var pendingDeepLinkURL: String? {
        get { defaults.string(forKey: "device.pendingDeepLinkURL") }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "device.pendingDeepLinkURL")
            } else {
                defaults.removeObject(forKey: "device.pendingDeepLinkURL")
            }
        }
    }
}
