import SwiftUI
import FirebaseAuth
import Combine

class ProfileViewModel: ObservableObject {
    @Published var currentUserProfile: User?
    @Published var premiumState: PremiumState = PremiumState()
    @Published var hideEmailError: String?

    private let premiumManager = PremiumManager()
    private var cancellables = Set<AnyCancellable>()

    init() {
        UserRepository.shared.$currentUserProfile.assign(to: &$currentUserProfile)
        premiumManager.$premiumState.assign(to: &$premiumState)
    }

    var isPro: Bool { currentUserProfile?.isPro ?? false }
}

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @EnvironmentObject var router: AppRouter

    @State private var optimisticHideEmail: Bool?

    var body: some View {
        ZStack {
            Color(red: 247/255, green: 249/255, blue: 251/255).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    streakCard
                    statsCards
                    accountInformation
                    options
                    signOutButton
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Profile")
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            if let base64 = viewModel.currentUserProfile?.profilePictureBase64, !base64.isEmpty,
               let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
            } else {
                MemberAvatar(uid: Auth.auth().currentUser?.uid ?? "me", size: 100)
            }

            Text(viewModel.currentUserProfile?.displayName ?? "User")
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 8) {
                Text(viewModel.currentUserProfile?.plan.uppercased() ?? "FREE")
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(viewModel.isPro ? BrandColor.warning : Color.gray.opacity(0.25)))
                    .foregroundColor(viewModel.isPro ? .black : .secondary)

                if !viewModel.isPro {
                    NavigationLink {
                        SubscriptionView()
                    } label: {
                        Text("Go Pro")
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(BrandGradient.primary))
                            .foregroundColor(.black)
                    }
                }
            }
        }
        .padding(.top, 24)
    }

    // MARK: - Streaks / stats

    private var streakCard: some View {
        HStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("\(viewModel.currentUserProfile?.currentStreak ?? 0)🔥")
                    .font(.title3.weight(.bold))
                Text("day streak")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                Text("\(viewModel.currentUserProfile?.longestStreak ?? 0)🏆")
                    .font(.title3.weight(.bold))
                Text("best streak")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                Text("\(viewModel.currentUserProfile?.drawingCount ?? 0)✏️")
                    .font(.title3.weight(.bold))
                Text("doodles")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private var statsCards: some View {
        HStack(spacing: 16) {
            StatCard(title: "Reactions", value: "\(viewModel.currentUserProfile?.reactionsReceivedCount ?? 0)")
            StatCard(title: "Circles", value: "\(viewModel.currentUserProfile?.groupsJoinedCount ?? 0)")
        }
        .padding(.horizontal)
    }

    // MARK: - Account Information (Hide my Gmail)

    private var effectiveHideEmail: Bool {
        optimisticHideEmail ?? viewModel.currentUserProfile?.hideEmail ?? false
    }

    private var accountInformation: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(BrandColor.secondary)
                    .cornerRadius(8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email")
                        .font(.subheadline)
                    Text(router.currentEmail ?? viewModel.currentUserProfile?.email ?? "—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider().padding(.leading, 48)

            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(BrandColor.primary)
                    .cornerRadius(8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide my Gmail")
                        .font(.subheadline)
                    Text("When on, members can't see your email — and you can't see theirs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { effectiveHideEmail },
                    set: { setHideEmail($0) }
                ))
                .labelsHidden()
            }
            .padding()

            if let error = viewModel.hideEmailError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    /// Optimistic toggle with revert on failed write (field-level update only).
    private func setHideEmail(_ value: Bool) {
        let previous = viewModel.currentUserProfile?.hideEmail ?? false
        optimisticHideEmail = value
        viewModel.hideEmailError = nil
        guard let uid = router.currentUID ?? Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                try await UserRepository.shared.updateHideEmail(uid: uid, value)
                await MainActor.run { optimisticHideEmail = nil }
            } catch {
                await MainActor.run {
                    optimisticHideEmail = previous
                    viewModel.hideEmailError = AppError.from(error).message
                }
            }
        }
    }

    // MARK: - Options

    private var options: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: SettingsView()) {
                ProfileRow(icon: "gearshape.fill", title: "Settings")
            }
            Divider().padding(.leading, 48)
            NavigationLink(destination: SubscriptionView()) {
                ProfileRow(icon: "crown.fill", title: "Lifetime Pro", iconColor: BrandColor.warning)
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private var signOutButton: some View {
        Button(action: {
            router.signOut()
        }) {
            Text("Log Out")
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(16)
        }
        .padding(.horizontal)
    }
}

struct ProfileRow: View {
    let icon: String
    let title: String
    var iconColor: Color = .pink

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(iconColor)
                .cornerRadius(8)

            Text(title)
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding()
    }
}
