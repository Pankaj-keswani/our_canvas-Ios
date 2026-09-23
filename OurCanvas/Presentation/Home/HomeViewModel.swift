import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

enum HomeLoadingConfig {
    static let cachePreloadTimeout: TimeInterval = 2.5
    static let slowLoadingThreshold: TimeInterval = 3.5
    static let watchdogTimeout: TimeInterval = 5.0
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var currentUserProfile: User?
    @Published var groups: [Group] = []
    @Published var isLoading = false
    @Published var isSlowLoading = false
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
    private var slowLoadingTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?

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
            .sink { [weak self] newGroups in
                guard let self = self else { return }
                self.groups = newGroups
                if !newGroups.isEmpty {
                    self.isLoading = false
                    self.isSlowLoading = false
                    self.cancelWatchdogs()
                }
            }
            .store(in: &cancellables)

        UserRepository.shared.$currentUserProfile
            .receive(on: RunLoop.main)
            .assign(to: &$currentUserProfile)

        loadData()
    }

    deinit {
        notificationListener?.remove()
        cancelWatchdogs()
    }

    func loadData() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        isSlowLoading = false
        errorMessage = nil

        listenToUnreadNotifications(uid: uid)
        observeGroups(uid: uid)

        Task {
            do {
                _ = try await UserRepository.shared.getUser(uid: uid)
                await claimDailyReward(uid: uid)
            } catch {
                // Profile fetch failure is tolerated
            }
        }
    }

    func observeGroups(uid: String) {
        cancelWatchdogs()

        // 1. Fast Cache-First Preload (<2.5s bounded read)
        preloadTask = Task { [weak self] in
            guard let self = self else { return }
            if let cached = await self.groupRepo.fetchCachedUserGroups(), !cached.isEmpty {
                if !Task.isCancelled {
                    self.groups = cached
                    self.isLoading = false
                    self.isSlowLoading = false
                    self.cancelWatchdogs()
                }
            }
        }

        // 2. Slow Loading Watchdog (3.5s)
        slowLoadingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(HomeLoadingConfig.slowLoadingThreshold * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            if self.isLoading {
                self.isSlowLoading = true
            }
        }

        // 3. Fallback Watchdog (5.0s)
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(HomeLoadingConfig.watchdogTimeout * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            if self.isLoading {
                do {
                    let fallbackGroups = try await self.groupRepo.fetchUserGroups(source: .default)
                    self.groups = fallbackGroups
                    self.isLoading = false
                    self.isSlowLoading = false
                } catch {
                    self.isLoading = false
                    self.isSlowLoading = false
                    if self.groups.isEmpty {
                        self.errorMessage = "Connection is slow. Tap to retry."
                    }
                }
            }
        }

        // 4. Real-time listener with metadata changes included
        groupRepo.listenToUserGroups { [weak self] fetched in
            guard let self = self else { return }
            self.cancelWatchdogs()
            self.isLoading = false
            self.isSlowLoading = false
            self.errorMessage = nil
        }
    }

    func cancelWatchdogs() {
        slowLoadingTask?.cancel()
        slowLoadingTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        preloadTask?.cancel()
        preloadTask = nil
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
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        isSlowLoading = false
        errorMessage = nil
        observeGroups(uid: uid)
    }
}
