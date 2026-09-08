import Foundation

/// Owns the FCM token lifecycle so token registration never depends on the user
/// already being signed in at the moment Firebase delivers the token.
///
/// Flow (spec §Phase0-8):
/// 1. `tokenDidUpdate` receives a token → cache it locally.
/// 2. If a user is authenticated, immediately persist `users/{uid}.fcmToken`.
/// 3. When authentication state changes, `userDidAuthenticate` re-associates the cached token.
/// 4. New tokens re-associate with the signed-in user.
final class PushTokenStore {
    static let shared = PushTokenStore()

    /// Production wiring (set at app launch) writes the token to Firestore. Injectable for tests.
    var persistHandler: ((_ token: String, _ uid: String) -> Void)?

    private let deviceStore: DeviceLocalStore
    private var associatedUID: String?

    private(set) var cachedToken: String?

    init(defaults: UserDefaults = .standard) {
        self.deviceStore = DeviceLocalStore(defaults: defaults)
        self.cachedToken = deviceStore.cachedFCMToken
    }

    func tokenDidUpdate(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        cachedToken = token
        deviceStore.cachedFCMToken = token
        if let uid = associatedUID {
            persistHandler?(token, uid)
        }
    }

    func userDidAuthenticate(uid: String) {
        associatedUID = uid
        if cachedToken == nil, let stored = deviceStore.cachedFCMToken, !stored.isEmpty {
            cachedToken = stored
        }
        if let token = cachedToken, !token.isEmpty {
            persistHandler?(token, uid)
        }
    }

    func userDidSignOut() {
        associatedUID = nil
        // Token stays cached so the next login can re-associate immediately.
    }
}
