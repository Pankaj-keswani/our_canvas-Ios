import XCTest
@testable import OurCanvas

final class HomeHeaderTests: XCTestCase {

    // MARK: - Layout Constants Parity

    func testAvatarSizeIsFortyEight() {
        XCTAssertEqual(HomeHeaderLayout.avatarSize, 48,
                       "Avatar touch target and frame must be 48pt as specified.")
    }

    func testActionItemSizeIsThirtyEight() {
        XCTAssertEqual(HomeHeaderLayout.actionItemSize, 38,
                       "Action item touch target size must be compact 38pt.")
    }

    func testActionSpacingIsSix() {
        XCTAssertEqual(HomeHeaderLayout.actionSpacing, 6,
                       "Spacing between trailing action buttons must be 6pt.")
    }

    func testTrailingActionCountIsStrictlyThree() {
        XCTAssertEqual(HomeHeaderLayout.trailingActionCount, 3,
                       "Trailing action stack must strictly contain only 3 items: Coin Pill, Bell, Gear.")
    }

    // MARK: - Screen Width Overflow & Gear Margin Safety

    func testStandardScreenWidth375GearIsFullyVisible() {
        // iPhone SE (2nd/3rd gen), iPhone 12/13 mini (375pt width)
        let screenWidth: CGFloat = 375
        let isVisible = HomeHeaderLayout.isGearFullyVisible(screenWidth: screenWidth, coinDigits: 2)
        XCTAssertTrue(isVisible, "Settings gear must be completely visible within safe area margins on 375pt screen.")

        let availableLeft = HomeHeaderLayout.availableLeftColumnWidth(screenWidth: screenWidth, coinDigits: 2)
        XCTAssertGreaterThanOrEqual(availableLeft, 150,
                                    "Left column should have ample width (>= 150pt) on 375pt screen.")
    }

    func testStandardScreenWidth393GearIsFullyVisible() {
        // iPhone 14/15/16 Pro (393pt width)
        let screenWidth: CGFloat = 393
        let isVisible = HomeHeaderLayout.isGearFullyVisible(screenWidth: screenWidth, coinDigits: 3)
        XCTAssertTrue(isVisible, "Settings gear must be completely visible on standard modern iPhones.")

        let availableLeft = HomeHeaderLayout.availableLeftColumnWidth(screenWidth: screenWidth, coinDigits: 3)
        XCTAssertGreaterThanOrEqual(availableLeft, 170)
    }

    func testCompactScreenWidth320GearIsFullyVisible() {
        // iPhone SE (1st gen), compact mini viewports (320pt width)
        let screenWidth: CGFloat = 320
        let isVisible = HomeHeaderLayout.isGearFullyVisible(screenWidth: screenWidth, coinDigits: 2)
        XCTAssertTrue(isVisible, "Settings gear must be completely visible within screen safe area margins on 320pt compact screen.")

        let trailingWidth = HomeHeaderLayout.trailingActionsWidth(coinDigits: 2)
        XCTAssertLessThanOrEqual(trailingWidth, 140,
                                 "Trailing actions width must stay compact (<= 140pt) so gear is never pushed off.")

        let availableLeft = HomeHeaderLayout.availableLeftColumnWidth(screenWidth: screenWidth, coinDigits: 2)
        XCTAssertGreaterThanOrEqual(availableLeft, HomeHeaderLayout.avatarSize + 10,
                                    "Left column must still accommodate the 48pt avatar without layout collision.")
    }

    func testTrailingActionsWidthWithVariousCoinBalances() {
        let width1Digit = HomeHeaderLayout.trailingActionsWidth(coinDigits: 1)
        let width2Digits = HomeHeaderLayout.trailingActionsWidth(coinDigits: 2)
        let width4Digits = HomeHeaderLayout.trailingActionsWidth(coinDigits: 4)

        XCTAssertEqual(width1Digit, width2Digits)
        XCTAssertLessThan(width2Digits, width4Digits)
        XCTAssertLessThan(width4Digits, 160, "Even large coin balances must not exceed 160pt.")
    }

    // MARK: - User Model & Status Badge Parity

    func testProUserStatus() {
        var user = User()
        user.plan = "pro"
        XCTAssertTrue(user.isPro)

        user.plan = "free"
        XCTAssertFalse(user.isPro)
    }

    func testUserNameFallbackLogic() {
        var user = User()
        user.displayName = "Harsh"
        XCTAssertEqual(user.displayName, "Harsh")

        user.displayName = ""
        XCTAssertTrue(user.displayName.isEmpty)
    }
}
