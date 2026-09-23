import SwiftUI
import FirebaseAuth
import Combine

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var showingWidgetConfig = false
    @State private var showingCoinWallet = false
    @State private var showingPracticeDrawing = false
    @State private var showingGroupsSheet = false
    @State private var showingHowItWorks = false

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                gradient: Gradient(colors: [Color.pink.opacity(0.1), Color.blue.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    if let user = viewModel.currentUserProfile {
                        StreakRecoveryBanner(user: user, onOpenWallet: {
                            showingCoinWallet = true
                        })
                    }
                    streakCard
                    widgetTipCard
                    circlesSection
                }
                .padding(.bottom, 30)
            }
            .refreshable {
                viewModel.refreshGroups()
                WidgetPayloadStore.shared.refreshSelectedCircleWidget()
            }

            // MARK: Daily reward toast
            if viewModel.dailyRewardClaimed {
                VStack {
                    HStack(spacing: 10) {
                        Text(viewModel.dailyRewardIsJackpot ? "🔥" : "🎉")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.dailyRewardIsJackpot
                                 ? "7-Day Login Streak Jackpot! 🔥"
                                 : "Daily Reward!")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.black)
                            Text(viewModel.dailyRewardIsJackpot
                                 ? "+5 Coins 🪙 awarded! Keep the streak going!"
                                 : "+1 Coin 🪙 claimed (Day \(viewModel.dailyRewardStreakDay) of 7) ✨")
                                .font(.caption2)
                                .foregroundColor(.black.opacity(0.7))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(viewModel.dailyRewardIsJackpot
                                  ? Color.orange.opacity(0.95)
                                  : Color.yellow.opacity(0.95))
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Spacer()
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.dailyRewardClaimed)
                .zIndex(10)
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .sheet(isPresented: $showingWidgetConfig) {
            WidgetConfigView()
        }
        .sheet(isPresented: $showingCoinWallet) {
            CoinWalletSheet()
        }
        .sheet(isPresented: $showingGroupsSheet) {
            NavigationStack {
                GroupsView()
            }
        }
        .sheet(isPresented: $showingHowItWorks) {
            NavigationStack {
                HowItWorksView()
            }
        }
        .fullScreenCover(isPresented: $showingPracticeDrawing) {
            NavigationStack {
                DrawingComposerView(group: .practice)
            }
        }
    }

    // MARK: - Header (compact Option 1 layout)

    private var header: some View {
        HomeHeaderView(
            userProfile: viewModel.currentUserProfile,
            greeting: viewModel.greeting,
            userName: viewModel.userName,
            isPro: viewModel.isPro,
            coins: viewModel.currentUserProfile?.coins ?? 3,
            unreadNotifications: viewModel.unreadNotifications,
            onOpenWallet: { showingCoinWallet = true }
        )
    }

    // MARK: - Streak card

    private var streakCard: some View {
        HStack(spacing: 14) {
            VStack(spacing: 3) {
                Text("\(viewModel.currentUserProfile?.currentStreak ?? 0)🔥")
                    .font(.title2.weight(.bold))
                Text("day streak")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 3) {
                Text("\(viewModel.currentUserProfile?.longestStreak ?? 0)🏆")
                    .font(.title2.weight(.bold))
                Text("best streak")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 3) {
                Text("\(viewModel.currentUserProfile?.drawingCount ?? 0)✏️")
                    .font(.title2.weight(.bold))
                Text("doodles")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Widget tip + configuration

    private var widgetTipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💡 Tip: Add the Our Canvas Widget")
                .font(.headline)
            Text("Add our widget to your home screen to see the latest drawings from your circles directly on your home screen.")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Button("Choose circle") {
                    showingWidgetConfig = true
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(BrandGradient.primary))

                if WidgetPayloadStore.shared.selectedGroupId != nil {
                    Text("Configured ✓")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Circles

    private var circlesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Circles")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Tap a circle to open its feed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                NavigationLink {
                    GroupsView()
                } label: {
                    Text("Manage")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(BrandColor.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            if viewModel.isLoading && viewModel.groups.isEmpty {
                skeletonLoadingView
            } else if let error = viewModel.errorMessage, viewModel.groups.isEmpty {
                errorRetryView(error: error)
            } else if viewModel.groups.isEmpty {
                HomeActivationCardView(
                    onCreateOrJoinCircle: {
                        showingGroupsSheet = true
                    },
                    onPracticeCanvas: {
                        showingPracticeDrawing = true
                    },
                    onHowItWorks: {
                        showingHowItWorks = true
                    }
                )
                .padding(.horizontal)
                .padding(.top, 10)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.groups) { group in
                        NavigationLink(destination: FeedView(group: group)) {
                            GroupCard(group: group)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Skeleton Loading & Error Views

    private var skeletonLoadingView: some View {
        VStack(spacing: 14) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.gray.opacity(0.18))
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 140, height: 16)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.12))
                            .frame(width: 200, height: 12)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
            }

            if viewModel.isSlowLoading {
                Button {
                    viewModel.refreshGroups()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text("Taking longer than usual... Tap to Refresh ↺")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .overlay(Capsule().stroke(Color.orange.opacity(0.4), lineWidth: 1))
                    .foregroundColor(.orange)
                    .shadow(color: Color.orange.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private func errorRetryView(error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.orange)

            Text("Connection Slow or Unavailable")
                .font(.headline.weight(.bold))
                .foregroundColor(BrandColor.textPrimary)

            Text(error)
                .font(.caption)
                .foregroundColor(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button {
                viewModel.refreshGroups()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Tap to Retry ↺")
                        .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(BrandGradient.primary))
                .foregroundColor(.black)
                .shadow(color: BrandColor.primary.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(BrandColor.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal)
        .padding(.top, 10)
    }
}

// MARK: - Widget circle configuration sheet

struct WidgetConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateLauncherViewModel()
    @State private var selectedGroupId: String?

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if viewModel.isLoading {
                    ProgressView("Loading circles...")
                } else if viewModel.groups.isEmpty {
                    VStack(spacing: 10) {
                        Text("Create or join a circle first — then pick it here to light up your widget.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(32)
                    }
                } else {
                    List(viewModel.groups) { group in
                        Button {
                            select(group)
                        } label: {
                            HStack {
                                Image(systemName: "paintpalette.fill")
                                    .foregroundColor(BrandColor.primary)
                                Text(group.groupName)
                                Spacer()
                                if selectedGroupId == group.groupId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(BrandColor.primary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Widget Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                selectedGroupId = WidgetPayloadStore.shared.selectedGroupId
            }
        }
    }

    private func select(_ group: Group) {
        WidgetPayloadStore.shared.selectedGroupId = group.groupId
        selectedGroupId = group.groupId
        WidgetPayloadStore.shared.refreshSelectedCircleWidget()
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
