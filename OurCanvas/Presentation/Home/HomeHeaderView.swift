import SwiftUI
import FirebaseAuth

/// Constants and sizing calculations for the Home navigation header layout.
enum HomeHeaderLayout {
    static let avatarSize: CGFloat = 48
    static let actionItemSize: CGFloat = 38
    static let actionSpacing: CGFloat = 6
    static let horizontalPadding: CGFloat = 16
    static let compactHorizontalPadding: CGFloat = 12
    static let columnSpacing: CGFloat = 8

    /// Number of action items strictly permitted in the trailing action stack.
    static let trailingActionCount: Int = 3

    /// Returns the estimated width of the 3 trailing action items:
    /// [🪙 {coins}] (pill ~46–64pt) + 6pt + [🔔] (38pt) + 6pt + [⚙️] (38pt).
    static func trailingActionsWidth(coinDigits: Int = 1) -> CGFloat {
        let coinPillWidth: CGFloat = coinDigits <= 2 ? 46 : (coinDigits <= 4 ? 54 : 64)
        return coinPillWidth + actionSpacing + actionItemSize + actionSpacing + actionItemSize
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
        let minLeftWidth = avatarSize + 10 // Minimum avatar space
        return (actions + minLeftWidth + padding + columnSpacing) <= screenWidth
    }
}

/// Compact Option 1 navigation header for the Home Screen.
///
/// Layout:
/// - Left Column: Avatar (48pt) + Greeting ("Good Morning") + Display Name & PRO badge / star.
///   Name line has lineLimit(1) and tail truncation to guarantee it never overflows.
/// - Right Column: Strictly 3 compact action items (38pt touch targets, 6pt spacing):
///   1. Coin pill: [🪙 {balance}] -> opens Coin Wallet sheet
///   2. Notification bell: [🔔] with unread dot -> navigates to Notifications
///   3. Settings gear: [⚙️] -> navigates to Settings
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
            // MARK: - Left Column (Profile, Greeting, Name & PRO Badge)
            leftColumn
                .layoutPriority(0)

            Spacer(minLength: 4)

            // MARK: - Right Column (Coin Pill, Bell, Gear)
            trailingActionStack
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, HomeHeaderLayout.horizontalPadding)
        .padding(.top, 16)
    }

    // MARK: - Left Column Subviews

    private var leftColumn: some View {
        HStack(spacing: 10) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                nameAndStatusRow
            }
        }
    }

    private var avatarView: some View {
        NavigationLink {
            ProfileView()
        } label: {
            if let base64 = userProfile?.profilePictureBase64, !base64.isEmpty,
               let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: HomeHeaderLayout.avatarSize, height: HomeHeaderLayout.avatarSize)
                    .clipShape(Circle())
            } else {
                MemberAvatar(uid: Auth.auth().currentUser?.uid ?? "me", size: HomeHeaderLayout.avatarSize)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile for \(userName)")
    }

    private var nameAndStatusRow: some View {
        HStack(spacing: 5) {
            Text(userName)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .truncationMode(.tail)

            if isPro {
                NavigationLink {
                    SubscriptionView()
                } label: {
                    Text("PRO")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(BrandColor.warning))
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
                    .font(.system(size: 12))
                Text("\(coins)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: HomeHeaderLayout.actionItemSize)
            .background(Capsule().fill(Color.yellow.opacity(0.22)))
            .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.55), lineWidth: 1))
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
                    .frame(width: HomeHeaderLayout.actionItemSize, height: HomeHeaderLayout.actionItemSize)
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)

                Image(systemName: "bell.fill")
                    .foregroundColor(.gray)
                    .font(.system(size: 15))
                    .frame(width: HomeHeaderLayout.actionItemSize, height: HomeHeaderLayout.actionItemSize)

                if unreadNotifications > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: -3, y: 3)
                }
            }
            .frame(width: HomeHeaderLayout.actionItemSize, height: HomeHeaderLayout.actionItemSize)
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
                    .frame(width: HomeHeaderLayout.actionItemSize, height: HomeHeaderLayout.actionItemSize)
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)

                Image(systemName: "gearshape.fill")
                    .foregroundColor(.gray)
                    .font(.system(size: 15))
            }
            .frame(width: HomeHeaderLayout.actionItemSize, height: HomeHeaderLayout.actionItemSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}
