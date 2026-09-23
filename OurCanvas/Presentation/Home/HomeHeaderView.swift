import SwiftUI
import FirebaseAuth

/// Constants and sizing calculations for the refined sleek Home navigation header layout.
enum HomeHeaderLayout {
    // Avatar proportions
    static let avatarDiameter: CGFloat = 40
    static let innerAvatarDiameter: CGFloat = 37
    static let avatarBorderWidth: CGFloat = 1.5

    // Typography
    static let greetingFontSize: CGFloat = 12
    static let nameFontSize: CGFloat = 18

    // PRO Micro-Pill
    static let proBadgeFontSize: CGFloat = 10
    static let proBadgeCornerRadius: CGFloat = 6
    static let proBadgeHorizontalPadding: CGFloat = 5
    static let proBadgeVerticalPadding: CGFloat = 1.5

    // Coins Pill
    static let coinEmojiFontSize: CGFloat = 12
    static let coinLabelFontSize: CGFloat = 11
    static let coinHorizontalPadding: CGFloat = 6
    static let coinVerticalPadding: CGFloat = 2.5

    // Action buttons (Bell & Gear)
    static let actionIconSize: CGFloat = 19
    static let actionTouchTargetSize: CGFloat = 34
    static let actionSpacing: CGFloat = 4

    // Spacing & Margins
    static let leftSectionSpacing: CGFloat = 8
    static let columnSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 16
    static let compactHorizontalPadding: CGFloat = 12

    // Backward-compatibility aliases
    static var avatarSize: CGFloat { avatarDiameter }
    static var actionItemSize: CGFloat { actionTouchTargetSize }

    /// Number of action items strictly permitted in the trailing action stack.
    static let trailingActionCount: Int = 3

    /// Returns the estimated width of the 3 trailing action items:
    /// [🪙 {coins}] (pill ~40–56pt) + 4pt + [🔔] (34pt) + 4pt + [⚙️] (34pt).
    static func trailingActionsWidth(coinDigits: Int = 1) -> CGFloat {
        let coinPillWidth: CGFloat = coinDigits <= 2 ? 40 : (coinDigits <= 4 ? 48 : 56)
        return coinPillWidth + actionSpacing + actionTouchTargetSize + actionSpacing + actionTouchTargetSize
    }

    /// Calculates available width for the left profile & name column given screen width and coin balance length.
    static func availableLeftColumnWidth(screenWidth: CGFloat, coinDigits: Int = 1) -> CGFloat {
        let padding = screenWidth <= 320 ? compactHorizontalPadding * 2 : horizontalPadding * 2
        let actions = trailingActionsWidth(coinDigits: coinDigits)
        return max(0, screenWidth - padding - actions - columnSpacing)
    }

    /// Validates that the Settings gear icon is fully within safe bounds on any screen width.
    static func isGearFullyVisible(screenWidth: CGFloat, coinDigits: Int = 1) -> Bool {
        let padding = screenWidth <= 320 ? compactHorizontalPadding * 2 : horizontalPadding * 2
        let actions = trailingActionsWidth(coinDigits: coinDigits)
        let minLeftWidth = avatarDiameter + leftSectionSpacing
        return (actions + minLeftWidth + padding + columnSpacing) <= screenWidth
    }
}

/// Refined sleek Home Screen navigation header matching Android's compact Option 1 design.
///
/// Proportions:
/// - Avatar: 40pt diameter (1.5pt gold/accent border ring, 37pt inner avatar image)
/// - Greeting: 12pt regular (labelMedium), 80% secondary text opacity
/// - User Name: 18pt bold (titleMedium) rendered with BrandGradient.primary
/// - PRO Badge: Sleek micro-pill (10pt extra-bold text, 6pt radius, 5×1.5pt padding) beside name
/// - Coins Pill: [🪙 {balance}] with 12pt coin emoji, 11pt bold label, and 6×2.5pt padding
/// - Bell & Settings Gear: 19pt icon size within 34pt square touch targets, spaced by 4pt
struct HomeHeaderView: View {
    let userProfile: User?
    let greeting: String
    let userName: String
    let isPro: Bool
    let coins: Int
    let unreadNotifications: Int
    let onOpenWallet: () -> Void

    var body: some View {
        HStack(spacing: HomeHeaderLayout.columnSpacing) {
            // MARK: - Left Column (Profile, Greeting, Gradient Name & PRO Badge)
            leftColumn
                .layoutPriority(0)

            Spacer(minLength: 8)

            // MARK: - Right Column (Coins Pill, Bell, Gear with 4pt spacing)
            trailingActionStack
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, HomeHeaderLayout.horizontalPadding)
        .padding(.top, 16)
    }

    // MARK: - Left Column Subviews

    private var leftColumn: some View {
        HStack(spacing: HomeHeaderLayout.leftSectionSpacing) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: HomeHeaderLayout.greetingFontSize, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.80))
                    .lineLimit(1)

                nameAndStatusRow
            }
        }
    }

    private var avatarRingColor: Color {
        isPro ? BrandColor.warning : BrandColor.primary
    }

    private var avatarView: some View {
        NavigationLink {
            ProfileView()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(avatarRingColor, lineWidth: HomeHeaderLayout.avatarBorderWidth)
                    .frame(width: HomeHeaderLayout.avatarDiameter, height: HomeHeaderLayout.avatarDiameter)

                if let base64 = userProfile?.profilePictureBase64, !base64.isEmpty,
                   let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: HomeHeaderLayout.innerAvatarDiameter, height: HomeHeaderLayout.innerAvatarDiameter)
                        .clipShape(Circle())
                } else {
                    MemberAvatar(uid: Auth.auth().currentUser?.uid ?? "me", size: HomeHeaderLayout.innerAvatarDiameter)
                }
            }
            .frame(width: HomeHeaderLayout.avatarDiameter, height: HomeHeaderLayout.avatarDiameter)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile for \(userName)")
    }

    private var nameAndStatusRow: some View {
        HStack(spacing: 5) {
            Text(userName)
                .font(.system(size: HomeHeaderLayout.nameFontSize, weight: .bold))
                .foregroundStyle(BrandGradient.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if isPro {
                NavigationLink {
                    SubscriptionView()
                } label: {
                    Text("PRO")
                        .font(.system(size: HomeHeaderLayout.proBadgeFontSize, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, HomeHeaderLayout.proBadgeHorizontalPadding)
                        .padding(.vertical, HomeHeaderLayout.proBadgeVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: HomeHeaderLayout.proBadgeCornerRadius)
                                .fill(BrandColor.warning)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("PRO Member")
            } else {
                NavigationLink {
                    SubscriptionView()
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BrandColor.warning)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Upgrade to Pro")
            }
        }
    }

    // MARK: - Right Column Subviews

    private var trailingActionStack: some View {
        HStack(spacing: HomeHeaderLayout.actionSpacing) {
            coinPillButton
            notificationBellButton
            settingsGearButton
        }
    }

    private var coinPillButton: some View {
        Button(action: onOpenWallet) {
            HStack(spacing: 3) {
                Text("🪙")
                    .font(.system(size: HomeHeaderLayout.coinEmojiFontSize))
                Text("\(coins)")
                    .font(.system(size: HomeHeaderLayout.coinLabelFontSize, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, HomeHeaderLayout.coinHorizontalPadding)
            .padding(.vertical, HomeHeaderLayout.coinVerticalPadding)
            .background(Capsule().fill(Color.yellow.opacity(0.20)))
            .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.50), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Coin balance \(coins)")
    }

    private var notificationBellButton: some View {
        NavigationLink {
            NotificationsView()
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: HomeHeaderLayout.actionTouchTargetSize, height: HomeHeaderLayout.actionTouchTargetSize)
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)

                Image(systemName: "bell.fill")
                    .foregroundColor(.gray)
                    .font(.system(size: HomeHeaderLayout.actionIconSize))
                    .frame(width: HomeHeaderLayout.actionTouchTargetSize, height: HomeHeaderLayout.actionTouchTargetSize)

                if unreadNotifications > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .offset(x: -2, y: 2)
                }
            }
            .frame(width: HomeHeaderLayout.actionTouchTargetSize, height: HomeHeaderLayout.actionTouchTargetSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unreadNotifications > 0 ? "\(unreadNotifications) unread notifications" : "Notifications")
    }

    private var settingsGearButton: some View {
        NavigationLink {
            SettingsView()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: HomeHeaderLayout.actionTouchTargetSize, height: HomeHeaderLayout.actionTouchTargetSize)
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)

                Image(systemName: "gearshape.fill")
                    .foregroundColor(.gray)
                    .font(.system(size: HomeHeaderLayout.actionIconSize))
            }
            .frame(width: HomeHeaderLayout.actionTouchTargetSize, height: HomeHeaderLayout.actionTouchTargetSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}
