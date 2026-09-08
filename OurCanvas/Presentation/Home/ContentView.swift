import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    @StateObject private var router: AppRouter

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
                AuthView()
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
/// with red dot, Profile), What's New versioned badge, persisted deep-link consumption,
/// post-onboarding create action and the first-run walkthrough.
struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedTab = 0
    @State private var showCreate = false
    @State private var showWalkthrough = false
    @StateObject private var whatsNew = WhatsNewViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView()
                }
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

                NavigationStack {
                    GroupsView()
                }
                .tabItem {
                    Label("Circles", systemImage: "person.2.fill")
                }
                .tag(1)

                NavigationStack {
                    WhatsNewView(viewModel: whatsNew)
                }
                .tabItem {
                    Label("What's New", systemImage: "sparkles")
                }
                .tag(2)

                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
                .tag(3)
            }
            .tint(BrandColor.primary)

            // Center Create (+) action, anchored above the tab bar.
            HStack {
                Spacer()
                Button(action: { showCreate = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(BrandGradient.primary))
                        .shadow(color: BrandColor.primary.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .accessibilityLabel("Create")
                .padding(.trailing, 24)
                .padding(.bottom, 68)
            }

            // What's New red dot over the 3rd tab (tab bar slots: 0..3, dot sits at 62.5%).
            GeometryReader { geometry in
                if whatsNew.hasUnseen {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .position(x: geometry.size.width * 0.625, y: geometry.size.height - 52)
                        .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            NotificationManager.shared.requestAuthorizationIfNeeded()
            router.consumePersistedDeepLink()
            maybeShowWalkthrough()
            maybeOpenPostOnboardingCreate()
        }
        .onChange(of: selectedTab) { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .sheet(isPresented: $showCreate) {
            CreateLauncherView()
        }
        .fullScreenCover(isPresented: $showWalkthrough) {
            WalkthroughOverlay(isPresented: $showWalkthrough)
        }
    }

    private func maybeShowWalkthrough() {
        guard let uid = router.currentUID else { return }
        let store = UserScopedStore(uid: uid)
        let totalSteps = WalkthroughOverlay.totalSteps
        if store.walkthroughStep < totalSteps {
            showWalkthrough = true
        }
    }

    /// `action_create` (Android): completing onboarding drops the user into the
    /// create flow once.
    private func maybeOpenPostOnboardingCreate() {
        guard let uid = router.currentUID else { return }
        let store = UserScopedStore(uid: uid)
        if store.consumePostOnboardingCreate() {
            showCreate = true
        }
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
