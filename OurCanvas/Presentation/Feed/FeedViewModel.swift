import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class FeedViewModel: ObservableObject {
    enum FeedTab: String, CaseIterable, Identifiable {
        case recent
        case favorites
        case guess

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recent: return "Recent"
            case .favorites: return "Favorites"
            case .guess: return "Guess 🎮"
            }
        }
    }

    @Published var drawings: [Drawing] = []
    @Published var group: Group
    @Published var selectedTab: FeedTab = .recent
    @Published var isLoading = true
    @Published var error: AppError?
    @Published var senderProfiles: [String: User] = [:]
    @Published var unseenCount: Int = 0
    @Published var members: [User] = []

    private let drawingRepo = DrawingRepository()
    private let userRepository = UserRepository.shared
    private var listenerRegistration: ListenerRegistration?
    private var didTrackVisit = false
    private var unseenListener: ListenerRegistration?

    var currentUID: String? { Auth.auth().currentUser?.uid }

    var isPro: Bool { userRepository.currentUserProfile?.isPro ?? false }

    /// Plan-based visible recent count (Android A3.3: free 3 / pro 5).
    var visibleRecentCount: Int {
        isPro ? DrawingLimits.proVisibleRecentDrawings : DrawingLimits.freeVisibleRecentDrawings
    }

    var visibleDrawings: [Drawing] {
        switch selectedTab {
        case .recent:
            return Array(drawings.prefix(visibleRecentCount))
        case .favorites:
            return drawings.filter { $0.isFavorite }
        case .guess:
            return []
        }
    }

    var hasMoreRecentThanVisible: Bool {
        selectedTab == .recent && drawings.count > visibleRecentCount
    }

    init(group: Group) {
        self.group = group
        listenToDrawings()
    }

    deinit {
        listenerRegistration?.remove()
        unseenListener?.remove()
    }

    func listenToDrawings() {
        isLoading = true
        listenerRegistration?.remove()

        listenerRegistration = drawingRepo.listenToDrawings(groupId: group.groupId) { [weak self] newDrawings in
            DispatchQueue.main.async {
                guard let self else { return }
                self.drawings = newDrawings
                self.isLoading = false
                self.refreshSenderProfiles()
                self.trackVisitIfNeeded()
            }
        }
    }

    func senderProfile(for drawing: Drawing) -> User? {
        senderProfiles[drawing.senderId]
    }

    func refreshSenderProfiles() {
        let senderIds = Array(Set(drawings.map { $0.senderId }))
        guard !senderIds.isEmpty else { return }
        Task {
            let profiles = (try? await userRepository.getUsersBatch(uids: senderIds)) ?? [:]
            self.senderProfiles = profiles
        }
    }

    func loadMembers() {
        let memberIds = group.memberIds
        guard !memberIds.isEmpty else { return }
        Task {
            let profiles = (try? await userRepository.getUsersBatch(uids: memberIds)) ?? [:]
            self.members = memberIds.compactMap { profiles[$0] }
        }
    }

    /// Unseen-drawings foundation: count drawings newer than the stored last visit
    /// (from others), then advance the per-group last-visit timestamp.
    private func trackVisitIfNeeded() {
        guard !didTrackVisit, let uid = currentUID else { return }
        didTrackVisit = true
        let store = UserScopedStore(uid: uid)
        let lastVisit = store.lastVisit(forGroup: group.groupId) ?? .distantPast
        unseenCount = drawings.filter { drawing in
            drawing.senderId != uid && (drawing.sentAt ?? .distantPast) > lastVisit
        }.count
        store.setLastVisit(Date(), forGroup: group.groupId)
    }

    // MARK: - Actions

    func toggleFavorite(drawing: Drawing) {
        let newStatus = !drawing.isFavorite
        guard let id = drawing.id else { return }
        Task {
            do {
                try await drawingRepo.toggleFavorite(drawingId: id, isFavorite: newStatus)
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    func addReaction(drawing: Drawing, emoji: String, emojiName: String) {
        guard let id = drawing.id,
              let currentUser = Auth.auth().currentUser else { return }
        let userName = senderProfiles[currentUser.uid]?.displayName
            ?? currentUser.displayName
            ?? "Someone"
        Task {
            do {
                try await drawingRepo.addReaction(
                    drawingId: id,
                    emoji: emoji,
                    emojiName: emojiName,
                    senderName: userName,
                    senderId: currentUser.uid
                )
            } catch {
                self.error = AppError.from(error)
            }
        }
    }
}
