import SwiftUI
import FirebaseAuth
import Combine

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var showingWidgetConfig = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.pink.opacity(0.1), Color.blue.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
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
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .sheet(isPresented: $showingWidgetConfig) {
            WidgetConfigView()
        }
    }

    // MARK: - Header (greeting, avatar, bell, settings, Go Pro)

    private var header: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ProfileView()
            } label: {
                if let base64 = viewModel.currentUserProfile?.profilePictureBase64, !base64.isEmpty,
                   let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    MemberAvatar(uid: Auth.auth().currentUser?.uid ?? "me", size: 44)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.greeting)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(viewModel.userName)
                    .font(.title3.weight(.bold))
            }

            Spacer()

            NavigationLink {
                NotificationsView()
            } label: {
                Image(systemName: "bell.fill")
                    .foregroundColor(.gray)
                    .font(.title3)
                    .padding(8)
                    .background(Color.white.opacity(0.6))
                    .clipShape(Circle())
                    .overlay(alignment: .topTrailing) {
                        if viewModel.unreadNotifications > 0 {
                            Text("\(min(viewModel.unreadNotifications, 9))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Color.red))
                                .offset(x: 5, y: -5)
                        }
                    }
            }

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.gray)
                    .font(.title3)
                    .padding(8)
                    .background(Color.white.opacity(0.6))
                    .clipShape(Circle())
            }

            if !viewModel.isPro {
                NavigationLink {
                    SubscriptionView()
                } label: {
                    Text("Go Pro")
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(BrandGradient.primary))
                        .foregroundColor(.black)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
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
                ProgressView()
                    .padding(.top, 40)
            } else if viewModel.groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("You haven't joined any circles yet.")
                        .foregroundColor(.secondary)
                    NavigationLink {
                        GroupsView()
                    } label: {
                        Text("New Circle")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(BrandColor.primary)
                    }
                }
                .padding(.top, 40)
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
