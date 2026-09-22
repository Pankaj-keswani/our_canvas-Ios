import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var currentUserProfile: User?
    @Published var groups: [Group] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var unreadNotifications = 0
    /// Set to `true` when the daily +1 coin reward is successfully claimed; drives the toast.
    @Published var dailyRewardClaimed = false
    /// The streak day (1–7) of the last claimed reward. Used to build the toast message.
    @Published var dailyRewardStreakDay: Int = 1
    /// `true` when the day-7 jackpot (+5 coins) was awarded.
    @Published var dailyRewardIsJackpot: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let groupRepo = GroupRepository()
    private var notificationListener: ListenerRegistration?

    var isPro: Bool { currentUserProfile?.isPro ?? false }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Good Night"
        }
    }

    var userName: String {
        if let name = currentUserProfile?.displayName, !name.isEmpty {
            return name
        }
        if let authName = Auth.auth().currentUser?.displayName, !authName.isEmpty {
            return authName
        }
        return "Partner"
    }

    init() {
        groupRepo.$groups
            .receive(on: RunLoop.main)
            .assign(to: &$groups)

        UserRepository.shared.$currentUserProfile
            .receive(on: RunLoop.main)
            .assign(to: &$currentUserProfile)

        loadData()
    }

    deinit {
        notificationListener?.remove()
    }

    func loadData() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        listenToUnreadNotifications(uid: uid)

        Task {
            do {
                _ = try await UserRepository.shared.getUser(uid: uid)
                groupRepo.listenToUserGroups()
                isLoading = false
                // Attempt daily coin claim after profile is loaded.
                await claimDailyReward(uid: uid)
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    /// Attempts to claim the daily coin reward. Shows streak-specific toast if awarded.
    func claimDailyReward(uid: String) async {
        do {
            let result = try await CoinManager.shared.claimDailyCoinIfEligible(userId: uid)
            guard result.coinsAwarded != nil else { return }
            dailyRewardStreakDay = result.streakDay
            dailyRewardIsJackpot = result.isJackpot
            dailyRewardClaimed = true
            // Auto-dismiss the toast after 4 seconds.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            dailyRewardClaimed = false
        } catch {
            // Daily reward failure is silent — not worth surfacing to user.
        }
    }

    /// Lightweight unread badge: count unread docs in the user's own collection.
    private func listenToUnreadNotifications(uid: String) {
        guard notificationListener == nil else { return }
        notificationListener = Firestore.firestore()
            .collection("users").document(uid).collection("notifications")
            .whereField("read", isEqualTo: false)
            .limit(to: 21)
            .addSnapshotListener { [weak self] snapshot, _ in
                DispatchQueue.main.async {
                    self?.unreadNotifications = snapshot?.documents.count ?? 0
                }
            }
    }

    func refreshGroups() {
        groupRepo.listenToUserGroups()
    }
}
