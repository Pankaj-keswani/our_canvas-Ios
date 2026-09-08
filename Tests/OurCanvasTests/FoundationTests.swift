import XCTest
import FirebaseFirestore
@testable import OurCanvas

// MARK: - Helpers

private func makeDefaults() -> UserDefaults {
    let suiteName = "tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private final class MockAuthProvider: AuthSessionProviding {
    var stubbedUser: AuthUserSnapshot?
    private var handlers: [(AuthUserSnapshot?) -> Void] = []

    var activeUser: AuthUserSnapshot? { stubbedUser }

    func addStateObserver(_ handler: @escaping (AuthUserSnapshot?) -> Void) -> () -> Void {
        handlers.append(handler)
        handler(stubbedUser)
        return { [weak self] in
            self?.handlers.removeAll()
        }
    }

    func simulate(_ user: AuthUserSnapshot?) {
        stubbedUser = user
        handlers.forEach { $0(user) }
    }

    func signOut() throws {
        simulate(nil)
    }
}

private final class MockProfileProvider: UserProfileProviding {
    var profile: User = User()
    var fetchError: Error?
    private(set) var updateCalls: [[String: Any]] = []

    func fetchOrCreateProfile(uid: String,
                              fallbackDisplayName: String?,
                              fallbackEmail: String?) async throws -> User {
        if let fetchError {
            throw fetchError
        }
        if profile.uid.isEmpty {
            var copy = profile
            copy.uid = uid
            copy.id = uid
            profile = copy
        }
        return profile
    }

    func updateFields(uid: String, _ fields: [String: Any]) async throws {
        updateCalls.append(fields)
    }
}

/// Waits for a MainActor-hopping condition (router transitions run in Tasks).
private func waitFor(_ condition: @escaping @MainActor () -> Bool,
                     timeout: TimeInterval = 2,
                     file: StaticString = #filePath,
                     line: UInt = #line) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await MainActor.run(body: condition) {
            return
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Condition not met within \(timeout)s", file: file, line: line)
}

// MARK: - Deep link parsing

final class DeepLinkParsingTests: XCTestCase {
    func testFeedSchemeURL() {
        let url = URL(string: "ourcanvas://feed?groupId=g1&groupName=Besties")!
        XCTAssertEqual(AppRoute(url: url), .drawingFeed(groupId: "g1", groupName: "Besties"))
    }

    func testAndroidPushStyleHTTPSURL() {
        let url = URL(string: "https://prempatra-c91fd.web.app/open?route=drawing_feed&groupId=g2")!
        XCTAssertEqual(AppRoute(url: url), .drawingFeed(groupId: "g2", groupName: nil))
    }

    func testDrawingRouteWithDrawingId() {
        let url = URL(string: "ourcanvas://feed?groupId=g1&drawingId=d9&groupName=Circle")!
        XCTAssertEqual(AppRoute(url: url), .drawing(groupId: "g1", drawingId: "d9", groupName: "Circle"))
    }

    func testGameRoute() {
        let url = URL(string: "ourcanvas://game?gameId=game7")!
        XCTAssertEqual(AppRoute(url: url), .guessGame(gameId: "game7"))
    }

    func testInviteCodeViaQuery() {
        let url = URL(string: "ourcanvas://invite?code=ABC123")!
        XCTAssertEqual(AppRoute(url: url), .circleInvite(code: "ABC123"))
    }

    func testInviteCodeViaPath() {
        let url = URL(string: "ourcanvas://invite/ABC123")!
        XCTAssertEqual(AppRoute(url: url), .circleInvite(code: "ABC123"))
    }

    func testMalformedLinksFailGracefully() {
        XCTAssertNil(AppRoute(url: URL(string: "ourcanvas://unknown?x=1")!))
        XCTAssertNil(AppRoute(url: URL(string: "https://example.com?foo=bar")!))
        XCTAssertNil(AppRoute(url: URL(string: "ourcanvas://feed")!))
    }
}

// MARK: - AppRouter session states

@MainActor
final class AppRouterTests: XCTestCase {
    private var defaults: UserDefaults!
    private var auth: MockAuthProvider!
    private var profiles: MockProfileProvider!

    override func setUp() async throws {
        defaults = makeDefaults()
        auth = MockAuthProvider()
        profiles = MockProfileProvider()
    }

    private func makeRouter() -> AppRouter {
        AppRouter(authProvider: auth, profileProvider: profiles, defaults: defaults)
    }

    private static func snapshot(uid: String = "u1",
                                 verified: Bool = true,
                                 name: String? = "Pankaj") -> AuthUserSnapshot {
        AuthUserSnapshot(uid: uid, email: "someone@example.com", isEmailVerified: verified, providerDisplayName: name)
    }

    func testFreshInstallStartsSignedOut() async {
        auth.stubbedUser = nil
        let router = makeRouter()
        await waitFor { router.state == .signedOut }
        XCTAssertEqual(router.state, .signedOut)
    }

    func testSignedInUnverifiedRoutesToVerification() async {
        let router = makeRouter()
        await waitFor { router.state == .signedOut }
        auth.simulate(Self.snapshot(verified: false))
        await waitFor { router.state == .needsVerification }
        XCTAssertEqual(router.state, .needsVerification)
    }

    func testIncompleteProfileRoutesToProfileSetup() async {
        profiles.profile = User() // displayName empty
        let router = makeRouter()
        await waitFor { router.state == .signedOut }
        auth.simulate(Self.snapshot())
        await waitFor { router.state == .needsProfileSetup }
        XCTAssertEqual(router.state, .needsProfileSetup)
    }

    func testMissingOnboardingRoutesToOnboardingThenReady() async {
        var profile = User()
        profile.displayName = "Pankaj"
        profile.onboardingVersion = 0
        profiles.profile = profile

        let router = makeRouter()
        await waitFor { router.state == .signedOut }
        auth.simulate(Self.snapshot())
        await waitFor { router.state == .needsOnboarding }
        XCTAssertEqual(router.state, .needsOnboarding)

        router.completeOnboarding()
        await waitFor { router.state == .ready }
        XCTAssertEqual(router.state, .ready)

        // Local user-scoped completion persisted with the right version.
        let store = UserScopedStore(uid: "u1", defaults: defaults)
        XCTAssertTrue(store.onboardingCompleted)
        XCTAssertEqual(store.onboardingVersion, 1)

        // Firestore field update was requested via the narrow payload.
        await waitFor { profiles.updateCalls.count == 1 }
        XCTAssertEqual(profiles.updateCalls.first?["onboardingVersion"] as? Int, 1)
    }

    func testFullyInitializedUserRoutesStraightToReady() async {
        var profile = User()
        profile.displayName = "Pankaj"
        profile.onboardingVersion = 1
        profiles.profile = profile

        let router = makeRouter()
        await waitFor { router.state == .signedOut }
        auth.simulate(Self.snapshot())
        await waitFor { router.state == .ready }
        XCTAssertEqual(router.state, .ready)
    }

    func testProfileFetchFailureSurfacesBootstrapErrorWithoutCrashing() async {
        profiles.fetchError = NSError(domain: NSURLErrorDomain, code: -1009)
        let router = makeRouter()
        await waitFor { router.state == .signedOut }
        auth.simulate(Self.snapshot())
        await waitFor { router.bootstrapError != nil }
        XCTAssertEqual(router.bootstrapError, .network)

        // Retry recovers when the backend comes back.
        profiles.fetchError = nil
        router.refreshSession()
        await waitFor { router.state == .ready }
    }

    func testPendingDeepLinkStoredAndResumedLater() async {
        let router = makeRouter()
        await waitFor { router.state == .signedOut }

        router.openURL(URL(string: "ourcanvas://invite?code=WELCOME")!)
        XCTAssertEqual(router.pendingRoute, .circleInvite(code: "WELCOME"))

        // Unknown/malformed links are ignored.
        router.openURL(URL(string: "ourcanvas://nonsense?zzz=1")!)
        XCTAssertEqual(router.pendingRoute, .circleInvite(code: "WELCOME"))
    }

    func testConsumePendingRouteClearsIt() async {
        let router = makeRouter()
        router.openURL(URL(string: "ourcanvas://feed?groupId=g7")!)
        XCTAssertEqual(router.consumePendingRoute(), .drawingFeed(groupId: "g7", groupName: nil))
        XCTAssertNil(router.pendingRoute)
    }

    func testSignOutReturnsToSignedOut() async {
        var profile = User()
        profile.displayName = "Pankaj"
        profile.onboardingVersion = 1
        profiles.profile = profile

        let router = makeRouter()
        await waitFor { router.state == .signedOut }
        auth.simulate(Self.snapshot())
        await waitFor { router.state == .ready }

        router.signOut()
        await waitFor { router.state == .signedOut }
        XCTAssertEqual(router.state, .signedOut)
    }
}

// MARK: - User-scoped local storage

final class UserScopedStoreTests: XCTestCase {
    func testOnboardingVersionIsUserScoped() {
        let defaults = makeDefaults()
        var storeA = UserScopedStore(uid: "userA", defaults: defaults)
        let storeB = UserScopedStore(uid: "userB", defaults: defaults)

        storeA.onboardingVersion = 1
        XCTAssertEqual(storeB.onboardingVersion, 0)
        XCTAssertTrue(storeA.onboardingCompleted)
        XCTAssertFalse(storeB.onboardingCompleted)
    }

    func testDiscoveryFlagsAreIndependent() {
        let defaults = makeDefaults()
        let store = UserScopedStore(uid: "u1", defaults: defaults)

        XCTAssertFalse(store.isDiscovered(.drawingTools))
        store.setDiscovered(.drawingTools)
        XCTAssertTrue(store.isDiscovered(.drawingTools))
        XCTAssertFalse(store.isDiscovered(.premium))
    }

    func testWhatsNewSeenVersionRoundTrip() {
        let defaults = makeDefaults()
        var store = UserScopedStore(uid: "u1", defaults: defaults)
        XCTAssertEqual(store.whatsNewSeenVersion, 0)
        store.whatsNewSeenVersion = 3
        XCTAssertEqual(store.whatsNewSeenVersion, 3)
    }

    func testNotificationPreferencesRoundTrip() {
        let defaults = makeDefaults()
        var store = UserScopedStore(uid: "u1", defaults: defaults)

        XCTAssertEqual(store.notificationPreferences, NotificationPreferences())
        var prefs = NotificationPreferences()
        prefs.newReactionEnabled = false
        store.notificationPreferences = prefs
        XCTAssertEqual(store.notificationPreferences, prefs)
    }

    func testGroupLastVisitRoundTrip() {
        let defaults = makeDefaults()
        let store = UserScopedStore(uid: "u1", defaults: defaults)

        XCTAssertNil(store.lastVisit(forGroup: "g1"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.setLastVisit(date, forGroup: "g1")
        XCTAssertEqual(store.lastVisit(forGroup: "g1")?.timeIntervalSince1970,
                       date.timeIntervalSince1970,
                       accuracy: 0.001)
        XCTAssertNil(store.lastVisit(forGroup: "g2"))
    }

    func testGuessRevealUsesAndroidStyleKey() {
        let defaults = makeDefaults()
        let store = UserScopedStore(uid: "u1", defaults: defaults)

        XCTAssertNil(store.revealedWord(gameId: "game9"))
        store.setRevealedWord("cat", gameId: "game9")
        XCTAssertEqual(store.revealedWord(gameId: "game9"), "cat")

        // Android key format parity: {gameId}_{uid} under guess_reveals.
        XCTAssertEqual(defaults.string(forKey: "user.u1.guessReveals.game9_u1"), "cat")
    }
}

// MARK: - FCM token lifecycle

final class PushTokenStoreTests: XCTestCase {
    func testTokenCachedBeforeLoginPersistsAfterLogin() {
        let defaults = makeDefaults()
        let store = PushTokenStore(defaults: defaults)
        var calls: [(token: String, uid: String)] = []
        store.persistHandler = { token, uid in
            calls.append((token, uid))
        }

        // Token arrives while signed out → cached only, no remote write.
        store.tokenDidUpdate("token-1")
        XCTAssertTrue(calls.isEmpty)

        // Login → cached token is associated with the user.
        store.userDidAuthenticate(uid: "u1")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].token, "token-1")
        XCTAssertEqual(calls[0].uid, "u1")
    }

    func testNewTokenReassociatesWithLoggedInUser() {
        let defaults = makeDefaults()
        let store = PushTokenStore(defaults: defaults)
        var calls: [(token: String, uid: String)] = []
        store.persistHandler = { token, uid in
            calls.append((token, uid))
        }

        store.userDidAuthenticate(uid: "u1")
        store.tokenDidUpdate("token-2")
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[1].token, "token-2")
        XCTAssertEqual(calls[1].uid, "u1")
    }

    func testTokenSurvivesAppRelaunchViaDefaults() {
        let defaults = makeDefaults()
        let first = PushTokenStore(defaults: defaults)
        first.tokenDidUpdate("token-1")

        // New instance (relaunch) reads the cached token and associates on login.
        let second = PushTokenStore(defaults: defaults)
        var calls: [(token: String, uid: String)] = []
        second.persistHandler = { token, uid in
            calls.append((token, uid))
        }
        second.userDidAuthenticate(uid: "u9")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].token, "token-1")
        XCTAssertEqual(calls[0].uid, "u9")
    }

    func testSignOutClearsAssociationButKeepsCache() {
        let defaults = makeDefaults()
        let store = PushTokenStore(defaults: defaults)
        var calls: [(token: String, uid: String)] = []
        store.persistHandler = { token, uid in
            calls.append((token, uid))
        }

        store.userDidAuthenticate(uid: "u1")
        store.tokenDidUpdate("token-1")
        XCTAssertEqual(calls.count, 2)

        store.userDidSignOut()
        store.tokenDidUpdate("token-3")
        XCTAssertEqual(calls.count, 2) // no association while signed out
        XCTAssertEqual(defaults.string(forKey: "device.fcmToken"), "token-3") // still cached
    }
}

// MARK: - Model resilience against Android-written documents

final class ModelResilienceTests: XCTestCase {
    func testUserDecodesAndroidDocumentWithUnknownFields() {
        let data: [String: Any] = [
            "displayName": "Pankaj",
            "email": "pankaj@example.com",
            "plan": "pro",
            "hideEmail": true,
            "currentStreak": 3,
            "whatsNewSeenVersion": 3,
            "colorCounts": ["#FF0000": 2],
            "someFutureAndroidField": ["nested": true],
            "premiumExpiry": Timestamp(date: Date(timeIntervalSince1970: 32503680000)),
        ]

        let user = User.from(documentID: "uid1", data: data)
        XCTAssertEqual(user.uid, "uid1")
        XCTAssertEqual(user.displayName, "Pankaj")
        XCTAssertEqual(user.plan, "pro")
        XCTAssertTrue(user.hideEmail)
        XCTAssertEqual(user.whatsNewSeenVersion, 3)
        XCTAssertEqual(user.colorCounts["#FF0000"], 2)
        XCTAssertNotNil(user.premiumExpiry)
        // Missing fields fall back to defaults instead of throwing.
        XCTAssertEqual(user.longestStreak, 0)
        XCTAssertEqual(user.onboardingVersion, 0)
        XCTAssertTrue(user.isPro)
    }

    func testUserDecodesSparseLegacyDocument() {
        let user = User.from(documentID: "uid2", data: ["displayName": "Old User"])
        XCTAssertEqual(user.displayName, "Old User")
        XCTAssertEqual(user.plan, "free")
        XCTAssertFalse(user.hideEmail)
        XCTAssertEqual(user.email, "")
    }

    func testGroupDecodesMinimalAndroidDocument() {
        let data: [String: Any] = [
            "groupName": "Besties",
            "createdBy": "u1",
            "inviteCode": "ABC123",
            "memberIds": ["u1", "u2"],
        ]
        let group = Group.from(documentID: "gid1", data: data)
        XCTAssertEqual(group.id, "gid1")
        XCTAssertEqual(group.groupId, "gid1") // falls back to document ID
        XCTAssertEqual(group.groupName, "Besties")
        XCTAssertEqual(group.memberIds.count, 2)
        XCTAssertNil(group.createdAt) // missing → nil, no throw
    }

    func testDrawingDecodesAndroidDocument() {
        let data: [String: Any] = [
            "groupId": "g1",
            "senderId": "u2",
            "recipientIds": ["u1"],
            "drawingData": "aGVsbG8=",
            "stickerData": [["emoji": "⭐", "x": 0.5]],  // Android array → normalized JSON string
            "reactions": [
                "u1": ["emoji": "❤️", "emojiName": "heart", "reactedAt": Timestamp(date: Date())]
            ],
            "unknownFutureField": 42,
        ]
        let drawing = Drawing.from(documentID: "d1", data: data)
        XCTAssertEqual(drawing.drawingId, "d1")
        XCTAssertEqual(drawing.recipientIds, ["u1"])
        XCTAssertTrue(drawing.stickerData.contains("emoji"))
        XCTAssertEqual(drawing.reactions["u1"]?.emoji, "❤️")
        XCTAssertEqual(drawing.reactions["u1"]?.emojiName, "heart")
        XCTAssertNotNil(drawing.reactions["u1"]?.reactedAt)
    }

    func testDrawingMissingRecipientIdsDefaultsToEmpty() {
        let drawing = Drawing.from(documentID: "d2", data: ["groupId": "g1"])
        XCTAssertEqual(drawing.recipientIds, [])
        XCTAssertEqual(drawing.stickerData, "[]")
    }
}

// MARK: - Field-safe update payloads

final class UpdatePayloadTests: XCTestCase {
    func testUserFieldUpdatesTouchOnlyTheirOwnKey() {
        XCTAssertEqual(Set(UserFieldUpdate.displayName("Ann").keys), ["displayName"])
        XCTAssertEqual(Set(UserFieldUpdate.profilePicture("base64").keys), ["profilePictureBase64"])
        XCTAssertEqual(Set(UserFieldUpdate.hideEmail(true).keys), ["hideEmail"])
        XCTAssertEqual(Set(UserFieldUpdate.whatsNewSeenVersion(3).keys), ["whatsNewSeenVersion"])
        XCTAssertEqual(Set(UserFieldUpdate.onboardingVersion(1).keys), ["onboardingVersion"])
        XCTAssertEqual(Set(UserFieldUpdate.fcmToken("tok").keys), ["fcmToken"])
    }

    func testUserCreationFieldsAreRulesCompatible() {
        let fields = User.creationFields(uid: "u1", displayName: "Ann", email: "ann@x.com")
        // Production create rules require plan "free" and no purchase fields.
        XCTAssertEqual(fields["plan"] as? String, "free")
        XCTAssertNil(fields["playPurchaseToken"])
        XCTAssertNil(fields["premiumSource"])
        // Shared cross-platform fields present.
        XCTAssertTrue(fields.keys.contains("hideEmail"))
        XCTAssertTrue(fields.keys.contains("whatsNewSeenVersion"))
        XCTAssertTrue(fields.keys.contains("onboardingVersion"))
        XCTAssertEqual(fields["uid"] as? String, "u1")
    }

    func testGroupCreationFieldsMatchAndroidSchema() {
        let fields = Group.creationFields(groupName: "Besties",
                                          createdBy: "u1",
                                          inviteCode: "ABC123",
                                          memberIds: ["u1"],
                                          createdAtMs: 1_700_000_000_000)
        XCTAssertEqual(Set(fields.keys),
                       ["groupName", "createdBy", "inviteCode", "memberIds", "createdAt"])
    }
}
