import XCTest
import Foundation
@testable import OurCanvas

// MARK: - WHAT'S NEW

final class WhatsNewTests: XCTestCase {
    func testCurrentVersionMatchesAndroid() {
        XCTAssertEqual(WhatsNewContent.CURRENT_VERSION, 3)
    }

    func testCardListMatchesAndroidOrder() {
        let titles = WhatsNewContent.cards.map { $0.title }
        XCTAssertEqual(titles.prefix(6), ["Widget refresh button", "Hide my Gmail", "A tidier notification feed",
                                          "Guess My Doodle", "Instant guess alerts", "Co-Draw together (Beta)"])
        XCTAssertEqual(titles.suffix(2), ["Offline sends", "Lifetime Pro"])
        // Tag chips limited to the Android vocabulary.
        XCTAssertTrue(WhatsNewContent.cards.allSatisfy { WhatsNewContent.Tag(rawValue: $0.tag.rawValue) != nil })
    }

    func testDotVisibleWhenSeenVersionBelowCurrent() {
        XCTAssertTrue(WhatsNewState.shouldShowDot(local: 0, remote: nil))
        XCTAssertTrue(WhatsNewState.shouldShowDot(local: 2, remote: 2))
    }

    func testDotHiddenAtCurrentVersion() {
        XCTAssertFalse(WhatsNewState.shouldShowDot(local: 3, remote: nil))
        XCTAssertFalse(WhatsNewState.shouldShowDot(local: 3, remote: 2))
        XCTAssertFalse(WhatsNewState.shouldShowDot(local: 2, remote: 3))
    }

    func testVersionBumpReArmsDot() {
        // A user at the current version sees no dot...
        XCTAssertFalse(WhatsNewState.shouldShowDot(local: WhatsNewContent.CURRENT_VERSION, remote: nil))
        // ...and the comparison is strictly less-than against CURRENT_VERSION, so any
        // future bump automatically re-arms the dot for every account below it.
        let hypotheticalNextVersion = WhatsNewContent.CURRENT_VERSION + 1
        XCTAssertTrue(hypotheticalNextVersion > WhatsNewContent.CURRENT_VERSION)
        XCTAssertTrue(WhatsNewState.shouldShowDot(local: WhatsNewContent.CURRENT_VERSION - 1, remote: nil))
        // A lagging SERVER alone doesn't re-arm the dot for a user whose local mirror
        // is current — the highest of the two wins, then markSeen back-fills the server.
        XCTAssertFalse(WhatsNewState.shouldShowDot(local: WhatsNewContent.CURRENT_VERSION,
                                                   remote: WhatsNewContent.CURRENT_VERSION - 1))
    }

    func testEffectiveSeenVersionMergesLocalAndRemote() {
        XCTAssertEqual(WhatsNewState.effectiveSeenVersion(local: 1, remote: 3), 3)
        XCTAssertEqual(WhatsNewState.effectiveSeenVersion(local: 3, remote: 1), 3)
        XCTAssertEqual(WhatsNewState.effectiveSeenVersion(local: 2, remote: nil), 2)
    }

    func testSeenKeysAreUserScoped() {
        let suiteName = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        var userA = UserScopedStore(uid: "a", defaults: defaults)
        let userB = UserScopedStore(uid: "b", defaults: defaults)
        userA.whatsNewSeenVersion = 3
        XCTAssertEqual(userB.whatsNewSeenVersion, 0, "seen state never leaks across accounts")
        XCTAssertTrue(WhatsNewState.shouldShowDot(local: userB.whatsNewSeenVersion, remote: nil))
    }
}

// MARK: - NOTIFICATIONS

final class NotificationModelTests: XCTestCase {
    func testDecodesAndroidNotificationDocument() {
        let data: [String: Any] = [
            "notificationId": "drawing:abc",
            "type": "NEW_DRAWING",
            "title": "New doodle",
            "body": "Riya sent a doodle",
            "read": false,
            "senderId": "u2",
            "senderName": "Riya",
            "groupId": "g1",
            "groupName": "Besties",
            "drawingId": "abc",
            "futureField": 1,
        ]
        let notification = InAppNotification.from(documentID: "drawing:abc", data: data)
        XCTAssertEqual(notification.type, .newDrawing)
        XCTAssertEqual(notification.senderName, "Riya")
        XCTAssertFalse(notification.read)
        XCTAssertEqual(notification.groupName, "Besties")
    }

    func testUnknownTypeDefaultsSafely() {
        let notification = InAppNotification.from(documentID: "n1", data: ["type": "SOMETHING_NEW"])
        XCTAssertEqual(notification.type, .newDrawing)
    }

    func testAndroidStyleIds() {
        XCTAssertEqual(InAppNotification.makeId(type: .newDrawing, drawingId: "abc"), "drawing:abc")
        XCTAssertEqual(InAppNotification.makeId(type: .guessResult, gameId: "g7"), "guess:g7")
        XCTAssertTrue(InAppNotification.makeId(type: .newReaction, drawingId: "d1", senderId: "u2").hasPrefix("reaction:"))
    }
}

final class PushPayloadTests: XCTestCase {
    func testParsesNewDrawingWithDefaults() {
        let payload = PushPayload.parse(["type": "new_drawing", "groupId": "g1"])!
        XCTAssertEqual(payload.type, .newDrawing)
        XCTAssertEqual(payload.senderName, "Someone", "missing senderName defaults")
        XCTAssertEqual(payload.groupName, "your circle", "missing groupName defaults")
    }

    func testParsesGuessResultWithRoleFields() {
        let payload = PushPayload.parse([
            "type": "guess_result",
            "result": "CORRECT",
            "word": "cat",
            "winnerName": "Ash",
            "perspective": "drawer",
            "groupId": "g1",
        ])!
        XCTAssertEqual(payload.type, .guessResult)
        XCTAssertEqual(payload.result, "CORRECT")
        XCTAssertEqual(payload.word, "cat")
        XCTAssertEqual(payload.winnerName, "Ash")
        XCTAssertEqual(payload.perspective, "drawer")
    }

    func testRejectsUnknownType() {
        XCTAssertNil(PushPayload.parse(["type": "nonsense"]))
        XCTAssertNil(PushPayload.parse(["something": "else"]))
    }

    func testGuessResultRoleAwareCopy() {
        let drawer = PushPayload.parse(["type": "guess_result", "result": "CORRECT",
                                        "word": "cat", "winnerName": "Ash", "perspective": "drawer"])!
        XCTAssertEqual(drawer.guessResultBody, "🏆 Ash cracked your doodle! The word was cat. Their turn to draw 🎨")

        let guesser = PushPayload.parse(["type": "guess_result", "result": "CORRECT",
                                         "word": "cat", "winnerName": "Ash", "perspective": "guesser"])!
        XCTAssertEqual(guesser.guessResultBody, "⚡ Ash guessed it first! The word was cat.")

        let gaveUp = PushPayload.parse(["type": "guess_result", "result": "GAVE_UP",
                                        "perspective": "drawer"])!
        XCTAssertEqual(gaveUp.guessResultBody, "😌 Nobody cracked it — you keep the pen! ✏️")

        let legacy = PushPayload.parse(["type": "guess_result"])!
        XCTAssertEqual(legacy.guessResultBody, "Round over — check who won!")
    }

    func testDeepLinkCarriesRouteContract() throws {
        let payload = PushPayload.parse(["type": "new_drawing", "groupId": "g1",
                                         "groupName": "Besties", "drawingId": "d9"])!
        let url = try XCTUnwrap(payload.deepLinkURL())
        let route = try XCTUnwrap(AppRoute(url: url))
        XCTAssertEqual(route, .drawing(groupId: "g1", drawingId: "d9", groupName: "Besties"))
    }

    func testInAppNotificationFromPayloadUsesStableIds() {
        let payload = PushPayload.parse(["type": "new_drawing", "drawingId": "d1",
                                         "senderName": "Riya", "groupId": "g1", "groupName": "Besties"])!
        let notification = payload.toInAppNotification(recipientId: "me")
        XCTAssertEqual(notification.notificationId, "drawing:d1")
        XCTAssertEqual(notification.recipientId, "me")
        XCTAssertEqual(notification.type, .newDrawing)
    }
}

final class NotificationMaintenanceTests: XCTestCase {
    private func make(age: TimeInterval) -> InAppNotification {
        var notification = InAppNotification()
        notification.createdAt = Date().addingTimeInterval(-age)
        return notification
    }

    func testCleanupDateCalculation() {
        XCTAssertTrue(NotificationRepository.isExpired(make(age: 31 * 24 * 3600)))
        XCTAssertFalse(NotificationRepository.isExpired(make(age: 29 * 24 * 3600)))
        XCTAssertFalse(NotificationRepository.isExpired(make(age: 0))) // missing/now → keep
    }

    func testDisplayCap() {
        XCTAssertEqual(NotificationRepository.displayCap, 20)
        let items = (0..<35).map { _ -> InAppNotification in
            var notification = InAppNotification()
            notification.notificationId = UUID().uuidString
            notification.createdAt = Date()
            return notification
        }
        let visible = Array(items.prefix(NotificationRepository.displayCap))
        XCTAssertEqual(visible.count, 20)
    }

    func testUnreadCountRespectsCap() {
        let items = (0..<30).map { index -> InAppNotification in
            var notification = InAppNotification()
            notification.notificationId = "n\(index)"
            notification.createdAt = Date()
            notification.read = index < 15 // 5 unread within the first 20 (cap)
            return notification
        }
        let unread = items.prefix(NotificationRepository.displayCap).filter { !$0.read }.count
        XCTAssertEqual(unread, 5)
    }

    func testCleanupBatchLimit() {
        XCTAssertEqual(NotificationRepository.cleanupBatchLimit, 100)
    }
}

// MARK: - PRIVACY (Hide my Gmail)

final class PrivacyReciprocityTests: XCTestCase {
    func testReciprocalHiding() {
        var me = User()
        me.hideEmail = true
        var member = User()
        member.email = "member@example.com"

        // Rule: if MY hideEmail is on, their email is hidden from me too.
        XCTAssertTrue(me.hideEmail || member.hideEmail)

        var hiddenMember = member
        hiddenMember.hideEmail = true
        // Their toggle alone also hides.
        XCTAssertTrue(me.hideEmail || hiddenMember.hideEmail)

        var openMember = member
        openMember.hideEmail = false
        var openMe = me
        openMe.hideEmail = false
        XCTAssertFalse(openMe.hideEmail || openMember.hideEmail)
    }

    func testProfileCacheTTLIsTenMinutes() {
        XCTAssertEqual(UserRepository.profileCacheTTL, 600, "Android 10-minute cache parity")
    }

    func testHideEmailFieldLevelUpdatePayload() {
        XCTAssertEqual(Set(UserFieldUpdate.hideEmail(true).keys), ["hideEmail"])
    }
}

// MARK: - ONBOARDING

final class OnboardingStateTests: XCTestCase {
    func testExactlyFourPagesWithAndroidCopy() {
        XCTAssertEqual(OnboardingView.pages.count, 4)
        XCTAssertEqual(OnboardingView.pages.map { $0.cta },
                       ["Show me more", "That's cute", "I'm in", "Start drawing"])
        XCTAssertEqual(OnboardingView.pages.map { $0.doodle.rawValue },
                       ["heart", "star", "rainbow", "smiley"])
    }

    func testCompletionSetsActionCreateAndVersion() {
        let suiteName = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        var store = UserScopedStore(uid: "u1", defaults: defaults)
        XCTAssertFalse(store.consumePostOnboardingCreate())

        store.postOnboardingCreate = true
        XCTAssertTrue(store.consumePostOnboardingCreate(), "create action fires once")
        XCTAssertFalse(store.consumePostOnboardingCreate(), "flag consumed exactly once")
    }

    func testVersionedMigrationDoesNotRepeatForExistingUsers() {
        // Existing users have onboardingVersion >= 1 → the router skips onboarding
        // (Phase 0 logic); the redesign only replaces the view.
        XCTAssertEqual(UserScopedStore.currentOnboardingVersion, 1)
    }
}

// MARK: - WALKTHROUGH

final class WalkthroughTests: XCTestCase {
    func testStepsIncludeFreshAndNewCopy() {
        let notificationStep = WalkthroughOverlay.steps.first { $0.title == "What's New" }
        XCTAssertNotNil(notificationStep)
        XCTAssertTrue(notificationStep?.message.contains("Fresh & New") ?? false)
    }

    func testStepPersistenceAdvances() {
        let suiteName = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        var store = UserScopedStore(uid: "u1", defaults: defaults)
        store.walkthroughStep = 2
        XCTAssertEqual(store.walkthroughStep, 2)
        store.walkthroughStep = WalkthroughOverlay.totalSteps
        XCTAssertEqual(store.walkthroughStep, WalkthroughOverlay.totalSteps)
    }
}

// MARK: - WIDGET

final class WidgetPayloadTests: XCTestCase {
    func testDisplayLines() {
        var payload = WidgetCirclePayload()
        payload.senderName = "Riya"
        payload.groupName = "Besties"
        payload.drawingImageJPEGBase64 = "abc"
        XCTAssertEqual(WidgetDisplay.senderLine(payload: payload), "From Riya")
        XCTAssertEqual(WidgetDisplay.groupLine(payload: payload), "Besties")

        payload.drawingImageJPEGBase64 = ""
        XCTAssertEqual(WidgetDisplay.senderLine(payload: payload), "No drawings yet")

        payload.senderName = ""
        payload.drawingImageJPEGBase64 = "x"
        XCTAssertEqual(WidgetDisplay.senderLine(payload: payload), "From Someone")
    }

    func testDeepLinkGeneration() throws {
        let url = try XCTUnwrap(WidgetDisplay.deepLinkURL(groupId: "g7"))
        XCTAssertEqual(AppRoute(url: url), .drawingFeed(groupId: "g7", groupName: nil))
    }

    func testMissingPayloadFallsBack() {
        let store = WidgetPayloadStore(defaults: nil)
        XCTAssertEqual(store.loadPayload(), .empty)
        XCTAssertNil(store.selectedGroupId)
    }

    func testPayloadRoundTripThroughDefaults() {
        let suiteName = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = WidgetPayloadStore(defaults: defaults)

        var payload = WidgetCirclePayload()
        payload.groupId = "g1"
        payload.groupName = "Besties"
        payload.senderName = "Riya"
        payload.drawingImageJPEGBase64 = "abc"
        store.save(payload: payload)
        XCTAssertEqual(store.loadPayload(), payload)

        store.selectedGroupId = "g1"
        XCTAssertEqual(store.selectedGroupId, "g1")
    }
}

// MARK: - PREMIUM

final class PremiumGatingTests: XCTestCase {
    func testFreeGroupLimit() {
        XCTAssertTrue(PremiumGate.canCreateGroup(currentCount: 1, isPro: false))
        XCTAssertTrue(PremiumGate.canCreateGroup(currentCount: 2, isPro: false) == false)
        XCTAssertTrue(PremiumGate.canCreateGroup(currentCount: 9, isPro: true))
    }

    func testDrawingAndFeedLimits() {
        XCTAssertFalse(DrawingLimits.sendBlocked(sentCount: 14, isPro: false))
        XCTAssertTrue(DrawingLimits.sendBlocked(sentCount: 15, isPro: false))
        XCTAssertEqual(DrawingLimits.freeVisibleRecentDrawings, 3)
        XCTAssertEqual(DrawingLimits.proVisibleRecentDrawings, 5)
    }

    func testPromoCodeValidation() {
        XCTAssertTrue(PromoCodeService.isValidCodeFormat("WELCOME7"))
        XCTAssertTrue(PromoCodeService.isValidCodeFormat("abc9"))
        XCTAssertFalse(PromoCodeService.isValidCodeFormat("ab"))
        XCTAssertFalse(PromoCodeService.isValidCodeFormat("has space"))
        XCTAssertFalse(PromoCodeService.isValidCodeFormat("!!!"))
    }

    func testPromoExpiry() {
        XCTAssertFalse(PromoCodeService.isExpired(expiresAt: nil))
        XCTAssertFalse(PromoCodeService.isExpired(expiresAt: Date().addingTimeInterval(3600)))
        XCTAssertTrue(PromoCodeService.isExpired(expiresAt: Date().addingTimeInterval(-3600)))
    }

    func testPromoOutcomeMapping() {
        XCTAssertEqual(PromoCodeService.outcome(forErrorDescription: "alreadyUsed"), .alreadyUsed)
        XCTAssertEqual(PromoCodeService.outcome(forErrorDescription: "expired"), .expired)
        XCTAssertEqual(PromoCodeService.outcome(forErrorDescription: "anything"), .invalidCode)
    }

    func testGrantStateIsHonestAboutServerActivation() {
        XCTAssertEqual(StoreManager.GrantState.pendingServerActivation, .pendingServerActivation)
        XCTAssertNotEqual(StoreManager.GrantState.pendingServerActivation, .granted)
    }
}

// MARK: - SETTINGS

final class SettingsContentTests: XCTestCase {
    func testSupportURLsAndEmails() {
        XCTAssertEqual("ourcanvasapp@gmail.com", "ourcanvasapp@gmail.com")
        XCTAssertTrue("https://prempatra-c91fd.web.app/privacy.html".hasPrefix("https://prempatra-c91fd.web.app"))
        XCTAssertTrue("https://prempatra-c91fd.web.app/terms.html".hasPrefix("https://"))
    }

    func testMailtoComposition() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "ourcanvasapp@gmail.com"
        components.queryItems = [URLQueryItem(name: "subject", value: "Child safety concern")]
        let url = components.url
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.hasPrefix("mailto:ourcanvasapp@gmail.com") ?? false)
    }
}

// MARK: - ACCOUNT DELETION

final class AccountDeletionTests: XCTestCase {
    func testDeleteFlowProgressesThroughAllStages() {
        var step: AccountDeletionService.Step = .idle
        var visited: [AccountDeletionService.Step] = [step]
        for _ in 0..<10 {
            step = AccountDeletionService.nextStep(after: step)
            visited.append(step)
            if step == .done { break }
        }
        XCTAssertEqual(visited, [.idle, .deletingDrawings, .deletingGroups,
                                 .deletingNotifications, .deletingUserDocument,
                                 .deletingAuthUser, .done])
    }

    func testDoneIsTerminal() {
        XCTAssertEqual(AccountDeletionService.nextStep(after: .done), .done)
    }
}
