import XCTest
import Photos
@testable import OurCanvas

final class InteractiveOnboardingAndPracticeTests: XCTestCase {

    // MARK: - Practice Group Contract

    func testPracticeGroupContract() {
        let practice = Group.practice
        XCTAssertEqual(practice.groupId, "practice")
        XCTAssertEqual(practice.groupName, "Practice Sketchbook")
        XCTAssertEqual(practice.createdBy, "practice")
        XCTAssertEqual(practice.inviteCode, "PRACTICE")
        XCTAssertEqual(practice.memberIds, ["practice"])
    }

    // MARK: - Onboarding Completion Persistence

    func testOnboardingCompletionFlags() {
        let suiteName = "tests.onboarding.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to instantiate test UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        // Initial state
        XCTAssertFalse(defaults.bool(forKey: "isOnboardingCompleted"))
        XCTAssertFalse(defaults.bool(forKey: "onboarding_completed"))

        // Set completed (as done in OnboardingView finish/skip)
        defaults.set(true, forKey: "isOnboardingCompleted")
        defaults.set(true, forKey: "onboarding_completed")

        XCTAssertTrue(defaults.bool(forKey: "isOnboardingCompleted"))
        XCTAssertTrue(defaults.bool(forKey: "onboarding_completed"))

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - What's New Version 9

    func testWhatsNewVersion9Highlights() {
        XCTAssertEqual(WhatsNewContent.CURRENT_VERSION, 9)
        guard let firstCard = WhatsNewContent.cards.first else {
            XCTFail("Expected cards in WhatsNewContent")
            return
        }
        XCTAssertEqual(firstCard.title, "Interactive Onboarding & Solo Practice Canvas")
        XCTAssertEqual(firstCard.tag, .experience)
        XCTAssertEqual(firstCard.tag.rawValue, "Experience")
        XCTAssertTrue(firstCard.isNew)
    }

    // MARK: - Photo Library Saver Decisions

    func testPhotoLibrarySaverDecisions() {
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .authorized), .allowed)
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .limited), .allowed)
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .denied), .denied)
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .restricted), .denied)
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .notDetermined), .undetermined)
    }

    func testPhotoLibraryFriendlyMessages() {
        XCTAssertEqual(PhotoLibrarySaver.friendlyMessage(for: .allowed), "Saved to Photos!")
        XCTAssertTrue(PhotoLibrarySaver.friendlyMessage(for: .denied).contains("Settings → Our Canvas → Photos"))
        XCTAssertEqual(PhotoLibrarySaver.friendlyMessage(for: .undetermined), "Photo permission is needed to save doodles.")
    }
}
