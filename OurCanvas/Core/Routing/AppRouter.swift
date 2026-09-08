import Foundation
import Combine
import FirebaseAuth

/// Snapshot of the Firebase auth user the router reasons about (mockable in tests).
struct AuthUserSnapshot: Equatable {
    let uid: String
    let email: String?
    let isEmailVerified: Bool
    let providerDisplayName: String?
}

/// Auth-state surface used by the router so tests can drive it without Firebase.
protocol AuthSessionProviding: AnyObject {
    var activeUser: AuthUserSnapshot? { get }
    func addStateObserver(_ handler: @escaping (AuthUserSnapshot?) -> Void) -> () -> Void
    func signOut() throws
}

final class FirebaseAuthSessionProvider: AuthSessionProviding {
    var activeUser: AuthUserSnapshot? {
        guard let user = Auth.auth().currentUser else { return nil }
        return AuthUserSnapshot(uid: user.uid,
                                email: user.email,
                                isEmailVerified: user.isEmailVerified,
                                providerDisplayName: user.displayName)
    }

    func addStateObserver(_ handler: @escaping (AuthUserSnapshot?) -> Void) -> () -> Void {
        let listener = Auth.auth().addStateDidChangeListener { _, user in
            handler(user.map { authUser in
                AuthUserSnapshot(uid: authUser.uid,
                                 email: authUser.email,
                                 isEmailVerified: authUser.isEmailVerified,
                                 providerDisplayName: authUser.displayName)
            })
        }
        return { Auth.auth().removeStateDidChangeListener(listener) }
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}

/// Session routing (Android `SessionRouter` equivalent).
///
/// States: signed out → Auth; signed in but unverified → Verification; profile setup
/// incomplete → Profile Setup; onboarding incomplete → Onboarding; otherwise Main.
/// Deep links are parsed and parked in `pendingRoute` until later phases wire navigation.
@MainActor
final class AppRouter: ObservableObject {
    enum SessionState: Equatable {
        case loading
        case signedOut
        case needsVerification
        case needsProfileSetup
        case needsOnboarding
        case ready
    }

    @Published private(set) var state: SessionState = .loading
    @Published private(set) var currentUID: String?
    @Published private(set) var currentEmail: String?
    @Published var pendingRoute: AppRoute?
    @Published var bootstrapError: AppError?

    /// Weak global reference for system entry points (push taps, widget URLs).
    private(set) static weak var shared: AppRouter?

    static let currentOnboardingVersion = UserScopedStore.currentOnboardingVersion

    private let authProvider: AuthSessionProviding
    private let profileProvider: UserProfileProviding
    private let defaults: UserDefaults
    private var unsubscribe: (() -> Void)?

    init(authProvider: AuthSessionProviding = FirebaseAuthSessionProvider(),
         profileProvider: UserProfileProviding = UserRepository.shared,
         defaults: UserDefaults = .standard) {
        self.authProvider = authProvider
        self.profileProvider = profileProvider
        self.defaults = defaults
        Self.shared = self
        // Firebase fires this listener immediately with the current user on registration,
        // which covers fresh install (nil → signedOut) and relaunch (user → full flow).
        unsubscribe = authProvider.addStateObserver { [weak self] snapshot in
            Task { @MainActor in
                self?.handleAuthSnapshot(snapshot)
            }
        }
    }

    deinit {
        unsubscribe?()
    }

    // MARK: - State machine

    func handleAuthSnapshot(_ snapshot: AuthUserSnapshot?) {
        bootstrapError = nil
        currentUID = snapshot?.uid
        currentEmail = snapshot?.email

        guard let snapshot else {
            state = .signedOut
            PushTokenStore.shared.userDidSignOut()
            return
        }

        guard snapshot.isEmailVerified else {
            state = .needsVerification
            return
        }

        state = .loading
        Task {
            do {
                let profile = try await profileProvider.fetchOrCreateProfile(
                    uid: snapshot.uid,
                    fallbackDisplayName: snapshot.providerDisplayName,
                    fallbackEmail: snapshot.email
                )
                self.evaluate(profile: profile, uid: snapshot.uid)
            } catch {
                // Keep the splash alive with a retry affordance instead of dropping the
                // user back to Auth with no explanation.
                self.bootstrapError = AppError.from(error)
            }
        }
    }

    private func evaluate(profile: User, uid: String) {
        let store = UserScopedStore(uid: uid, defaults: defaults)
        if profile.displayName.trimmed.isEmpty {
            state = .needsProfileSetup
        } else if profile.onboardingVersion < Self.currentOnboardingVersion && !store.onboardingCompleted {
            state = .needsOnboarding
        } else {
            state = .ready
            PushTokenStore.shared.userDidAuthenticate(uid: uid)
        }
    }

    /// Re-reads the current auth snapshot (used after verification reload / profile save).
    func refreshSession() {
        handleAuthSnapshot(authProvider.activeUser)
    }

    func completeOnboarding() {
        guard let uid = currentUID else { return }
        var store = UserScopedStore(uid: uid, defaults: defaults)
        store.onboardingVersion = Self.currentOnboardingVersion
        state = .ready
        PushTokenStore.shared.userDidAuthenticate(uid: uid)
        Task {
            try? await profileProvider.updateFields(
                uid: uid,
                UserFieldUpdate.onboardingVersion(Self.currentOnboardingVersion)
            )
        }
    }

    func signOut() {
        // The auth listener drives the transition back to signedOut.
        try? authProvider.signOut()
    }

    // MARK: - Deep links (foundation)

    func openURL(_ url: URL) {
        // Unknown/malformed links are ignored (fail gracefully).
        guard let route = AppRoute(url: url) else { return }
        pendingRoute = route
    }

    /// Later phases call this when a destination becomes able to handle the parked route.
    func consumePendingRoute() -> AppRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    /// Notification-tap routing (hub rows): maps the notification's fields through
    /// the same route model the push/widget/invite paths use.
    func openDeepLink(notification: InAppNotification) {
        let route: AppRoute
        switch notification.type {
        case .guessResult:
            let gameId = notification.targetId.isEmpty ? notification.drawingId : notification.targetId
            route = .guessGame(gameId: gameId)
        case .newDrawing, .newReaction:
            if notification.drawingId.isEmpty {
                route = .drawingFeed(groupId: notification.groupId,
                                     groupName: notification.groupName.isEmpty ? nil : notification.groupName)
            } else {
                route = .drawing(groupId: notification.groupId,
                                 drawingId: notification.drawingId,
                                 groupName: notification.groupName.isEmpty ? nil : notification.groupName)
            }
        }
        pendingRoute = route
    }

    /// Consumes a deep link persisted before routing was possible (cold launch).
    func consumePersistedDeepLink() {
        let store = DeviceLocalStore()
        guard let stored = store.pendingDeepLinkURL, let url = URL(string: stored) else { return }
        store.pendingDeepLinkURL = nil
        openURL(url)
    }
}
