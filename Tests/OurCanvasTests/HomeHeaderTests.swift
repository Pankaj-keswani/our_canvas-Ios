import XCTest
@testable import OurCanvas

final class HomeHeaderTests: XCTestCase {

    // MARK: - Visual Proportions Parity

    func testAvatarDimensionsAndBorder() {
        XCTAssertEqual(HomeHeaderLayout.avatarDiameter, 40,
                       "Avatar diameter must be 40pt.")
        XCTAssertEqual(HomeHeaderLayout.innerAvatarDiameter, 37,
                       "Inner avatar image diameter must be 37pt.")
        XCTAssertEqual(HomeHeaderLayout.avatarBorderWidth, 1.5,
                       "Avatar border ring width must be 1.5pt.")
        XCTAssertEqual(HomeHeaderLayout.avatarSize, 40)
    }

    func testTypographyProportions() {
        XCTAssertEqual(HomeHeaderLayout.greetingFontSize, 12,
                       "Greeting text must be 12pt regular.")
        XCTAssertEqual(HomeHeaderLayout.nameFontSize, 18,
                       "User name text must be 18pt bold.")
    }

    func testProBadgeProportions() {
        XCTAssertEqual(HomeHeaderLayout.proBadgeFontSize, 10,
                       "PRO badge text must be 10pt extra-bold.")
        XCTAssertEqual(HomeHeaderLayout.proBadgeCornerRadius, 6,
                       "PRO badge micro-pill corner radius must be 6pt.")
        XCTAssertEqual(HomeHeaderLayout.proBadgeHorizontalPadding, 5,
                       "PRO badge horizontal padding must be 5pt.")
        XCTAssertEqual(HomeHeaderLayout.proBadgeVerticalPadding, 1.5,
                       "PRO badge vertical padding must be 1.5pt.")
    }

    func testCoinsPillProportions() {
        XCTAssertEqual(HomeHeaderLayout.coinEmojiFontSize, 12,
                       "Coins emoji font size must be 12pt.")
        XCTAssertEqual(HomeHeaderLayout.coinLabelFontSize, 11,
                       "Coins label font size must be 11pt bold.")
        XCTAssertEqual(HomeHeaderLayout.coinHorizontalPadding, 6,
                       "Coins pill horizontal padding must be 6pt.")
        XCTAssertEqual(HomeHeaderLayout.coinVerticalPadding, 2.5,
                       "Coins pill vertical padding must be 2.5pt.")
    }

    func testActionTouchTargetsAndSpacing() {
        XCTAssertEqual(HomeHeaderLayout.actionTouchTargetSize, 34,
                       "Action item touch target size must be 34pt square.")
        XCTAssertEqual(HomeHeaderLayout.actionItemSize, 34)
        XCTAssertEqual(HomeHeaderLayout.actionIconSize, 19,
                       "Action icon size must be 19pt.")
        XCTAssertEqual(HomeHeaderLayout.actionSpacing, 4,
                       "Spacing between trailing action buttons must be 4pt.")
        XCTAssertEqual(HomeHeaderLayout.leftSectionSpacing, 8,
                       "Spacing between avatar and name column must be 8pt.")
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
        XCTAssertGreaterThanOrEqual(availableLeft, 200,
                                    "Left column should have generous whitespace (>= 200pt) on 375pt screen.")
    }

    func testStandardScreenWidth393GearIsFullyVisible() {
        // iPhone 14/15/16 Pro (393pt width)
        let screenWidth: CGFloat = 393
        let isVisible = HomeHeaderLayout.isGearFullyVisible(screenWidth: screenWidth, coinDigits: 3)
        XCTAssertTrue(isVisible, "Settings gear must be completely visible on standard modern iPhones.")

        let availableLeft = HomeHeaderLayout.availableLeftColumnWidth(screenWidth: screenWidth, coinDigits: 3)
        XCTAssertGreaterThanOrEqual(availableLeft, 210)
    }

    func testCompactScreenWidth320GearIsFullyVisible() {
        // iPhone SE (1st gen), compact mini viewports (320pt width)
        let screenWidth: CGFloat = 320
        let isVisible = HomeHeaderLayout.isGearFullyVisible(screenWidth: screenWidth, coinDigits: 2)
        XCTAssertTrue(isVisible, "Settings gear must be completely visible within screen safe area margins on 320pt compact screen.")

        let trailingWidth = HomeHeaderLayout.trailingActionsWidth(coinDigits: 2)
        XCTAssertLessThanOrEqual(trailingWidth, 120,
                                 "Trailing actions width must stay sleek and compact (<= 120pt) so gear is never pushed off.")

        let availableLeft = HomeHeaderLayout.availableLeftColumnWidth(screenWidth: screenWidth, coinDigits: 2)
        XCTAssertGreaterThanOrEqual(availableLeft, HomeHeaderLayout.avatarDiameter + HomeHeaderLayout.leftSectionSpacing + 60,
                                    "Left column must accommodate avatar, 8pt spacing, and generous name width on 320pt screen.")
    }

    func testTrailingActionsWidthWithVariousCoinBalances() {
        let width1Digit = HomeHeaderLayout.trailingActionsWidth(coinDigits: 1)
        let width2Digits = HomeHeaderLayout.trailingActionsWidth(coinDigits: 2)
        let width4Digits = HomeHeaderLayout.trailingActionsWidth(coinDigits: 4)

        XCTAssertEqual(width1Digit, width2Digits)
        XCTAssertLessThan(width2Digits, width4Digits)
        XCTAssertLessThan(width4Digits, 140, "Even 4-digit coin balances must stay under 140pt.")
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
