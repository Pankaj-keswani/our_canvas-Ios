import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    @StateObject private var router: AppRouter
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _router = StateObject(wrappedValue: AppRouter())
    }

    var body: some View {
        ZStack {
            BrandBackground()
            content
        }
        .environmentObject(router)
        .onOpenURL { url in
            router.openURL(url)
        }
        .onAppear {
            NotificationManager.shared.router = router
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // Foreground flush is the PRIMARY retry path (iOS background limits).
                OfflineQueueService.shared.flushForCurrentUser(reason: "foreground")
                StreakWarningManager.shared.scheduleOrVerifyStreakWarning()
                UserActivityService.shared.recordActivityIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = router.bootstrapError {
            BootstrapErrorView(error: error) {
                router.refreshSession()
            }
        } else {
            switch router.state {
            case .loading:
                ProgressView()
                    .tint(BrandColor.primary)
            case .signedOut:
                if !isOnboardingCompleted {
                    OnboardingView()
                } else {
                    AuthView()
                }
            case .needsVerification:
                VerificationView()
            case .needsProfileSetup:
                ProfileSetupView()
            case .needsOnboarding:
                OnboardingView()
            case .ready:
                MainTabView()
            }
        }
    }
}

struct BootstrapErrorView: View {
    let error: AppError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(BrandColor.warning)
            Text(error.title)
                .font(BrandFont.headline())
                .foregroundColor(BrandColor.textPrimary)
            Text(error.message)
                .font(BrandFont.body())
                .foregroundColor(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryGradientButton(title: "Try Again", action: retry)
        }
        .padding(32)
    }
}

/// Phase 3 shell: the five final destinations (Home, Circles, center Create, What's New
/// with red dot, Profile) rendered under the Android-parity premium pill tab bar,
/// What's New versioned badge, persisted deep-link consumption, post-onboarding
/// create action and the first-run walkthrough.
struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedTab = 0
    @State private var visitedTabs: Set<Int> = [0]
    @State private var showCreate = false
    @StateObject private var whatsNew = WhatsNewViewModel()
    @ObservedObject private var offlineQueue = OfflineQueueService.shared

    private var bannerText: String {
        if offlineQueue.isOffline {
            return offlineQueue.pendingCount > 0
                ? "Offline — \(offlineQueue.pendingCount) doodle\(offlineQueue.pendingCount == 1 ? "" : "s") queued"
                : "You're offline"
        }
        return "Sending \(offlineQueue.pendingCount) queued doodle\(offlineQueue.pendingCount == 1 ? "" : "s")…"
    }

    /// Five slots for the premium bar: Home, Circles, center Create, What's New (red
    /// dot via `showUnreadDot`), Profile. Ids match `selectedTab`.
    private var premiumTabs: [PremiumTab] {
        [
            PremiumTab(id: 0, label: "Home", icon: "house", activeIcon: "house.fill"),
            PremiumTab(id: 1, label: "Circles", icon: "person.2", activeIcon: "person.2.fill"),
            PremiumTab(id: 2, label: "What's New", icon: "sparkles",
                       showUnreadDot: whatsNew.hasUnseen),
            PremiumTab(id: 3, label: "Profile", icon: "person.crop.circle", activeIcon: "person.crop.circle.fill"),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The system TabView is intentionally NOT used: its bottom bar cannot be
            // reliably hidden across pushed destinations on iOS 16, so the four stacks
            // live in a ZStack instead — the selected one visible, previously visited
            // ones kept mounted (state preservation) but hidden, unvisited ones lazy.
            ZStack {
                NavigationStack {
                    HomeView()
                }
                .tabVisibility(selectedTab == 0)

                if visitedTabs.contains(1) {
                    NavigationStack {
                        GroupsView()
                    }
                    .tabVisibility(selectedTab == 1)
                }

                if visitedTabs.contains(2) {
                    NavigationStack {
                        WhatsNewView(viewModel: whatsNew)
                    }
                    .tabVisibility(selectedTab == 2)
                }

                if visitedTabs.contains(3) {
                    NavigationStack {
                        ProfileView()
                    }
                    .tabVisibility(selectedTab == 3)
                }
            }
            .tint(BrandColor.primary)
            .onChange(of: selectedTab) { tab in
                visitedTabs.insert(tab)
                // System TabView semantics: keyboard dismisses on tab switch.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
                // What's New marks its version seen when the tab is viewed (its onAppear
                // used to re-fire on every re-entry under the system TabView).
                if tab == 2, whatsNew.hasUnseen {
                    whatsNew.markCurrentSeen()
                }
            }
            // Android-parity floating pill bar replaces the system tab bar; content
            // reserves bottom space via safeAreaInset so nothing hides behind it.
            .premiumTabBarChrome(
                tabs: premiumTabs,
                selection: $selectedTab,
                onCreate: { showCreate = true }
            )

            // Offline / pending-sends banner (Android OfflineBanner parity).
            if offlineQueue.isOffline || offlineQueue.pendingCount > 0 {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: offlineQueue.isOffline ? "wifi.slash" : "airplane.circle")
                        Text(bannerText)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(BrandColor.warning.opacity(0.95)))
                    .foregroundColor(.black)
                    .padding(.top, 6)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .environmentObject(offlineQueue)
        .onAppear {
            NotificationManager.shared.requestAuthorizationIfNeeded()
            router.consumePersistedDeepLink()
            maybeOpenPostOnboardingCreate()
            OfflineQueueService.shared.refreshPendingCount()
            OfflineQueueService.shared.flushForCurrentUser(reason: "mainAppear")
        }
        .sheet(isPresented: $showCreate) {
            CreateLauncherView()
        }
    }

    /// `action_create` (Android): completing onboarding drops the user into the
    /// create flow once.
    private func maybeOpenPostOnboardingCreate() {
        guard let uid = router.currentUID else { return }
        var store = UserScopedStore(uid: uid)
        if store.consumePostOnboardingCreate() {
            showCreate = true
        }
    }
}

// MARK: - ZStack tab visibility

/// Non-selected tabs stay mounted for state preservation but are invisible,
/// non-interactive and hidden from accessibility (system TabView selection parity).
private extension View {
    func tabVisibility(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}

/// Circle picker shown by the center Create action.
struct CreateLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateLauncherViewModel()

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if viewModel.isLoading {
                    ProgressView("Loading circles...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.groups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 40))
                            .foregroundColor(BrandColor.textSecondary)
                        Text("You haven't joined a circle yet.")
                            .font(BrandFont.body())
                            .foregroundColor(BrandColor.textSecondary)
                        Text("Create or join a circle first, then come back to draw.")
                            .font(BrandFont.caption())
                            .foregroundColor(BrandColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    List(viewModel.groups) { group in
                        NavigationLink {
                            DrawingComposerView(group: group)
                        } label: {
                            HStack {
                                Image(systemName: "paintpalette.fill")
                                    .foregroundColor(BrandColor.primary)
                                Text(group.groupName)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("New Drawing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

final class CreateLauncherViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var isLoading = true

    private let groupRepo = GroupRepository()
    private var cancellables = Set<AnyCancellable>()

    init() {
        groupRepo.$groups
            .receive(on: RunLoop.main)
            .sink { [weak self] groups in
                self?.groups = groups
                self?.isLoading = false
            }
            .store(in: &cancellables)
        groupRepo.listenToUserGroups()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
