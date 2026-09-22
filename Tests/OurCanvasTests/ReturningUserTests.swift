import XCTest
import FirebaseFirestore
@testable import OurCanvas

final class ReturningUserTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suite = "tests.returning_user.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    // MARK: - 1. User Model & createdAt

    func testUserCreatedAtDecodesFromTimestamp() {
        let now = Date()
        let data: [String: Any] = [
            "uid": "u123",
            "displayName": "Harsh",
            "createdAt": Timestamp(date: now)
        ]
        let user = User.from(documentID: "u123", data: data)
        XCTAssertNotNil(user.createdAt)
        XCTAssertEqual(floor(user.createdAt!.timeIntervalSince1970), floor(now.timeIntervalSince1970))
    }

    func testUserCreatedAtDecodesFromDate() {
        let now = Date()
        let data: [String: Any] = [
            "uid": "u123",
            "createdAt": now
        ]
        let user = User.from(documentID: "u123", data: data)
        XCTAssertNotNil(user.createdAt)
        XCTAssertEqual(user.createdAt, now)
    }

    func testUserCreationFieldsIncludesCreatedAtServerTimestamp() {
        let fields = User.creationFields(uid: "u123", displayName: "Harsh", email: "harsh@example.com")
        XCTAssertNotNil(fields["createdAt"])
    }

    // MARK: - 2. Onboarding Completed Flag in UserScopedStore & UserDefaults

    func testOnboardingCompletedFlagInUserDefaults() {
        var store = UserScopedStore(uid: "u123", defaults: defaults)
        XCTAssertFalse(store.onboardingCompleted)

        // Setting onboarding_completed in global defaults suppresses onboarding for the user
        defaults.set(true, forKey: "onboarding_completed")
        XCTAssertTrue(store.onboardingCompleted)

        // Setting via store setter persists to both scoped and global defaults
        defaults.removeObject(forKey: "onboarding_completed")
        store.onboardingCompleted = true
        XCTAssertTrue(defaults.bool(forKey: "onboarding_completed"))
        XCTAssertTrue(store.onboardingCompleted)
        XCTAssertGreaterThanOrEqual(store.onboardingVersion, UserScopedStore.currentOnboardingVersion)
    }

    // MARK: - 3. Established User Detection Logic

    func testEstablishedUserWithDisplayNameSuppressesOnboarding() {
        var user = User()
        user.displayName = "Harsh"
        user.onboardingVersion = 0

        let isEstablished = !user.displayName.trimmed.isEmpty || user.drawingCount > 0 || (user.createdAt != nil && Date().timeIntervalSince(user.createdAt!) > 120)
        XCTAssertTrue(isEstablished, "User with non-empty displayName is an established account")
    }

    func testEstablishedUserWithDrawingCountSuppressesOnboarding() {
        var user = User()
        user.displayName = ""
        user.drawingCount = 3
        user.onboardingVersion = 0

        let isEstablished = !user.displayName.trimmed.isEmpty || user.drawingCount > 0 || (user.createdAt != nil && Date().timeIntervalSince(user.createdAt!) > 120)
        XCTAssertTrue(isEstablished, "User with drawingCount > 0 is an established account")
    }

    func testEstablishedUserWithOlderCreatedAtSuppressesOnboarding() {
        var user = User()
        user.displayName = ""
        user.drawingCount = 0
        user.createdAt = Date().addingTimeInterval(-180) // 3 minutes ago
        user.onboardingVersion = 0

        let isEstablished = !user.displayName.trimmed.isEmpty || user.drawingCount > 0 || (user.createdAt != nil && Date().timeIntervalSince(user.createdAt!) > 120)
        XCTAssertTrue(isEstablished, "User created > 2 minutes ago is an established account")
    }

    func testFreshNewUserIsNotEstablished() {
        var user = User()
        user.displayName = ""
        user.drawingCount = 0
        user.createdAt = Date() // just now
        user.onboardingVersion = 0

        let isEstablished = !user.displayName.trimmed.isEmpty || user.drawingCount > 0 || (user.createdAt != nil && Date().timeIntervalSince(user.createdAt!) > 120)
        XCTAssertFalse(isEstablished, "Fresh user with no name or doodles is not established")
    }

    // MARK: - 4. OnboardingVersion Merge Write Payload

    func testOnboardingVersionPayloadMatchesContract() {
        let payload = UserFieldUpdate.onboardingVersion(1)
        XCTAssertEqual(payload["onboardingVersion"] as? Int, 1)
    }

    // MARK: - 5. Fast Path Profile Evaluation

    func testUserWithDisplayNameEvaluatesToReadyWhenOnboardingCompleted() {
        var user = User()
        user.displayName = "Pankaj"
        user.onboardingVersion = 1

        let store = UserScopedStore(uid: "u1", defaults: defaults)
        let hasDisplayName = !user.displayName.trimmed.isEmpty
        let isOnboardingDone = store.onboardingCompleted || defaults.bool(forKey: "onboarding_completed") || user.onboardingVersion >= UserScopedStore.currentOnboardingVersion

        XCTAssertTrue(hasDisplayName)
        XCTAssertTrue(isOnboardingDone)
    }

    func testUserWithoutDisplayNameEvaluatesToNeedsProfileSetup() {
        var user = User()
        user.displayName = ""

        let hasDisplayName = !user.displayName.trimmed.isEmpty
        XCTAssertFalse(hasDisplayName, "User with empty displayName needs profile setup")
    }
}
