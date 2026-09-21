import Foundation
import Combine
import FirebaseAuth

/// What's New content + versioned seen-state (Android A6.1).
/// CURRENT_VERSION bump re-arms the red dot per account across devices via the
/// shared `users/{uid}.whatsNewSeenVersion` field.
enum WhatsNewContent {
    static let CURRENT_VERSION = 5

    enum Tag: String, CaseIterable {
        case play = "Play"
        case create = "Create"
        case together = "Together"
        case pro = "Pro"
    }

    struct Card: Identifiable, Equatable {
        let emoji: String
        let title: String
        let subtitle: String
        let tag: Tag
        let isNew: Bool
        var id: String { title }
    }

    /// Current content/order from the Android production spec (A6.1).
    static let cards: [Card] = [
        Card(emoji: "🔥", title: "Streak Recovery", subtitle: "Never lose your streak again — recover missed days within 48h using coins.", tag: .play, isNew: true),
        Card(emoji: "🪙", title: "Coins & Letter Hints", subtitle: "Earn coins with rewarded ads and reveal tricky letters slot by slot.", tag: .play, isNew: true),
        Card(emoji: "❤️", title: "Avatar & Name Reactions", subtitle: "See who reacted to your doodle with circular avatars and short names.", tag: .together, isNew: false),
        Card(emoji: "⚡", title: "Ultra-Fast Doodle Sync", subtitle: "Drawings downsampled cleanly for instant delivery and reliable widget refreshes.", tag: .create, isNew: false),
        Card(emoji: "⏳", title: "24h Auto-Pass & Claim", subtitle: "If a drawer is inactive for 24h, anyone in the circle can claim the pen and draw!", tag: .play, isNew: false),
        Card(emoji: "🔄", title: "Widget refresh button", subtitle: "Refresh your home-screen doodle widget with one tap.", tag: .play, isNew: false),
        Card(emoji: "🔒", title: "Hide my Gmail", subtitle: "WhatsApp-style privacy: hide your email, and theirs hides from you.", tag: .together, isNew: false),
        Card(emoji: "🧹", title: "A tidier notification feed", subtitle: "Capped history, swipe-to-delete, mark-all-read and easy cleanup.", tag: .together, isNew: false),
        Card(emoji: "🎮", title: "Guess My Doodle", subtitle: "Now multiplayer — the whole circle races to guess at once. First correct answer wins!", tag: .play, isNew: false),
        Card(emoji: "🔔", title: "Instant guess alerts", subtitle: "Know the moment someone cracks your doodle — or beats you to it.", tag: .play, isNew: false),
        Card(emoji: "🤝", title: "Co-Draw together (Beta)", subtitle: "Draw on one live canvas with your circle, stroke by stroke.", tag: .together, isNew: false),
        Card(emoji: "📱", title: "Home screen widget", subtitle: "Your circle's latest doodle, right on your home screen.", tag: .create, isNew: false),
        Card(emoji: "▶️", title: "Doodle replay", subtitle: "Watch every doodle redraw itself, stroke by stroke.", tag: .create, isNew: false),
        Card(emoji: "🎨", title: "One-tap circle invites", subtitle: "Share an invite link and doodle together in seconds.", tag: .together, isNew: false),
        Card(emoji: "✈️", title: "Offline sends", subtitle: "Queue doodles while offline; they send the moment you're back.", tag: .create, isNew: false),
        Card(emoji: "💎", title: "Lifetime Pro", subtitle: "One payment, Pro forever. Special brushes, colors and more.", tag: .pro, isNew: false),
    ]
}

/// Pure seen-state logic (tested): merges the local user-scoped mirror with the
/// Firestore per-account version; never mutates the user document beyond the
/// single `whatsNewSeenVersion` field.
enum WhatsNewState {
    static func effectiveSeenVersion(local: Int, remote: Int?) -> Int {
        max(local, remote ?? 0)
    }

    static func shouldShowDot(local: Int, remote: Int?) -> Bool {
        effectiveSeenVersion(local: local, remote: remote) < WhatsNewContent.CURRENT_VERSION
    }
}

@MainActor
final class WhatsNewViewModel: ObservableObject {
    @Published private(set) var hasUnseen: Bool = false
    @Published private(set) var seenVersion: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        UserRepository.shared.$currentUserProfile
            .receive(on: RunLoop.main)
            .sink { [weak self] profile in
                self?.refresh(local: nil, remote: profile?.whatsNewSeenVersion)
            }
            .store(in: &cancellables)
        refreshFromLocal()
    }

    private var uid: String? { Auth.auth().currentUser?.uid }

    private func refreshFromLocal() {
        let store = currentUserStore()
        refresh(local: store?.whatsNewSeenVersion ?? 0, remote: nil)
    }

    private func refresh(local: Int?, remote: Int?) {
        if let local {
            // Keep the local mirror at least as high as the server's version
            // (cross-device sync-in).
            if let remote, remote > local, var store = currentUserStore() {
                store.whatsNewSeenVersion = remote
            }
        }
        let store = currentUserStore()
        let effectiveLocal = store?.whatsNewSeenVersion ?? 0
        seenVersion = WhatsNewState.effectiveSeenVersion(local: effectiveLocal,
                                                         remote: remote)
        hasUnseen = WhatsNewState.shouldShowDot(local: effectiveLocal, remote: remote)
    }

    private func currentUserStore() -> UserScopedStore? {
        guard let uid else { return nil }
        return UserScopedStore(uid: uid, defaults: defaults)
    }

    /// Mark the current version seen: local mirror + single-field Firestore update.
    func markCurrentSeen() {
        let version = WhatsNewContent.CURRENT_VERSION
        if var store = currentUserStore() {
            store.whatsNewSeenVersion = version
        }
        seenVersion = version
        hasUnseen = false

        guard let uid else { return }
        Task {
            try? await UserRepository.shared.markWhatsNewSeen(uid: uid, version: version)
        }
    }
}
