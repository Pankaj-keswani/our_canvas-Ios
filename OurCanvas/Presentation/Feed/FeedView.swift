import SwiftUI
import FirebaseAuth

struct FeedView: View {
    let group: Group
    @StateObject private var viewModel: FeedViewModel
    @State private var showingDrawingSheet = false
    @State private var showingMembers = false
    @State private var replayDrawing: Drawing?

    init(group: Group) {
        self.group = group
        _viewModel = StateObject(wrappedValue: FeedViewModel(group: group))
    }

    var body: some View {
        ZStack {
            Color(red: 247/255, green: 249/255, blue: 251/255).ignoresSafeArea()

            VStack(spacing: 0) {
                memberHeader

                tabPicker

                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading Feed...")
                    Spacer()
                } else if viewModel.drawings.isEmpty {
                    emptyState
                } else {
                    tabContent
                }
            }

            createFAB
        }
        .navigationTitle(group.groupName)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingDrawingSheet) {
            NavigationStack {
                DrawingComposerView(group: group)
            }
        }
        .sheet(isPresented: $showingMembers) {
            MembersSheet(group: group, members: viewModel.members, isPro: viewModel.isPro)
                .onAppear { viewModel.loadMembers() }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $replayDrawing) { drawing in
            NavigationStack {
                ReplayView(drawing: drawing)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.error?.message ?? "")
        }
    }

    // MARK: - Header (avatar stack + member count)

    private var memberHeader: some View {
        Button {
            showingMembers = true
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: -10) {
                    ForEach(Array(group.memberIds.prefix(5).enumerated()), id: \.element) { _, uid in
                        MemberAvatar(uid: uid, size: 28)
                    }
                }
                Text("\(group.memberIds.count) members")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if viewModel.unseenCount > 0 {
                    Text("\(viewModel.unseenCount) new")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(BrandColor.primary.opacity(0.2)))
                        .foregroundColor(BrandColor.primary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("Feed", selection: $viewModel.selectedTab) {
            ForEach(FeedViewModel.FeedTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .recent:
            recentList
        case .favorites:
            if viewModel.drawings.filter({ $0.isFavorite }).isEmpty {
                emptyFavorites
            } else {
                favoritesList
            }
        case .guess:
            guessPlaceholder
        }
    }

    private var recentList: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(viewModel.visibleDrawings) { drawing in
                    DrawingCard(
                        drawing: drawing,
                        senderName: viewModel.senderProfile(for: drawing)?.displayName,
                        onFavorite: { viewModel.toggleFavorite(drawing: drawing) },
                        onReact: { emoji, name in viewModel.addReaction(drawing: drawing, emoji: emoji, emojiName: name) },
                        onReplay: { replayDrawing = drawing }
                    )
                }
                if viewModel.hasMoreRecentThanVisible {
                    upgradeBanner
                }
            }
            .padding()
        }
    }

    private var favoritesList: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(viewModel.drawings.filter { $0.isFavorite }) { drawing in
                    DrawingCard(
                        drawing: drawing,
                        senderName: viewModel.senderProfile(for: drawing)?.displayName,
                        onFavorite: { viewModel.toggleFavorite(drawing: drawing) },
                        onReact: { emoji, name in viewModel.addReaction(drawing: drawing, emoji: emoji, emojiName: name) },
                        onReplay: { replayDrawing = drawing }
                    )
                }
            }
            .padding()
        }
    }

    private var guessPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 44))
                .foregroundStyle(BrandGradient.primary)
            Text("Guess My Doodle")
                .font(.headline)
            Text("Multiplayer doodle guessing arrives in an upcoming update. The race is going to be worth it. ⚡")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var upgradeBanner: some View {
        VStack(spacing: 6) {
            Text("Showing the \(viewModel.visibleRecentCount) most recent doodles")
                .font(.subheadline.weight(.semibold))
            Text(viewModel.isPro
                 ? "Upgrade keeps the full history flowing."
                 : "Upgrade to Pro to see more of this circle's doodles.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(BrandGradient.primary.opacity(0.12))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BrandColor.primary.opacity(0.3), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.3))
            Text("No drawings yet in this circle.")
                .font(.headline)
                .foregroundColor(.secondary)

            Button(action: { showingDrawingSheet = true }) {
                Text("Create the first drawing")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.pink)
                    .cornerRadius(12)
            }
            .padding(.top, 16)
            Spacer()
        }
    }

    private var emptyFavorites: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "heart")
                .font(.system(size: 44))
                .foregroundColor(.gray.opacity(0.4))
            Text("No favorites yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Tap the heart on a doodle to keep it here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var createFAB: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { showingDrawingSheet = true }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(BrandGradient.primary))
                        .shadow(color: BrandColor.primary.opacity(0.4), radius: 8, x: 0, y: 4)
                }
            }
            .padding()
        }
    }
}

// MARK: - Member avatar (dicebear, deterministic per uid — Android parity)

struct MemberAvatar: View {
    let uid: String
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let url = AvatarIdentity.url(forUid: uid) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Circle().fill(Color.gray.opacity(0.25))
                            .overlay(Text(String(uid.prefix(1).uppercased()))
                                .font(.caption)
                                .foregroundColor(.secondary))
                    }
                }
            } else {
                Circle().fill(Color.gray.opacity(0.25))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
    }
}

// MARK: - Members sheet (emails respect the Hide-my-Gmail reciprocity rule)

struct MembersSheet: View {
    let group: Group
    let members: [User]
    let isPro: Bool

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userRepository = UserRepository.shared

    private var ownProfile: User? { userRepository.currentUserProfile }

    /// Reciprocity rule (Android A8.1): if I hide my email, members' emails are hidden
    /// from me too — and each member's own toggle hides theirs.
    private func emailDisplay(for member: User) -> String {
        if ownProfile?.hideEmail == true || member.hideEmail {
            return "Email hidden 🔒"
        }
        return member.email.isEmpty ? "—" : member.email
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(members) { member in
                        HStack(spacing: 12) {
                            MemberAvatar(uid: member.uid.isEmpty ? "user" : member.uid, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.displayName.isEmpty ? "Circle member" : member.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(emailDisplay(for: member))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Circle Members (\(group.memberIds.count))")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invite Code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(group.inviteCode)
                            .font(.title3.weight(.bold).monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Circle Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
