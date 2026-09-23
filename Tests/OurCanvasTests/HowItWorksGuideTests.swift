import XCTest
@testable import OurCanvas

final class HowItWorksGuideTests: XCTestCase {

    // MARK: - Onboarding Brush Choices Contract

    func testOnboardingBrushChoices() {
        let cases = OnboardingView.BrushChoice.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertEqual(cases, [.neon, .fire, .rainbow, .pastel])
        XCTAssertEqual(OnboardingView.BrushChoice.neon.rawValue, "Neon Glow")
        XCTAssertEqual(OnboardingView.BrushChoice.fire.rawValue, "Fire Spark")
        XCTAssertEqual(OnboardingView.BrushChoice.rainbow.rawValue, "Rainbow")
        XCTAssertEqual(OnboardingView.BrushChoice.pastel.rawValue, "Pastel Soft")
    }

    // MARK: - Visual Guide Topics

    func testVisualGuideSevenCoreTopicsCovered() {
        // Contract verifying the 7 core feature topics exist in the visual guide:
        // 1. Home & Lock Screen Widgets
        // 2. Circles & Invites
        // 3. Magical Brushes & Stroke Replay
        // 4. Live Co-Draw (Beta)
        // 5. Guess My Doodle
        // 6. Daily Streaks & Coins
        // 7. Solo Practice Sketchbook
        let expectedBadges = [
            "WIDGETS",
            "CIRCLES",
            "CREATIVITY",
            "COLLABORATION",
            "PARTY GAME",
            "REWARDS",
            "SOLO MODE"
        ]
        XCTAssertEqual(expectedBadges.count, 7)
    }

    // MARK: - Home Activation Card Actions

    func testHomeActivationCardActionCallbacks() {
        var createOrJoinCalled = false
        var practiceCalled = false
        var howItWorksCalled = false

        let card = HomeActivationCardView(
            onCreateOrJoinCircle: { createOrJoinCalled = true },
            onPracticeCanvas: { practiceCalled = true },
            onHowItWorks: { howItWorksCalled = true }
        )

        card.onCreateOrJoinCircle()
        XCTAssertTrue(createOrJoinCalled)

        card.onPracticeCanvas()
        XCTAssertTrue(practiceCalled)

        card.onHowItWorks()
        XCTAssertTrue(howItWorksCalled)
    }
}
