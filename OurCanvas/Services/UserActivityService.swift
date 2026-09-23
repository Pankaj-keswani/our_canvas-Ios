import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Manages throttled user presence and last active timestamp updates on Firestore.
final class UserActivityService {
    static let shared = UserActivityService()

    /// Throttling window: minimum 120 seconds between activity updates to protect Firestore writes.
    let debounceInterval: TimeInterval
    private(set) var lastRecordedTime: Date? = nil

    private let auth: Auth
    private let userRepository: UserRepository

    init(debounceInterval: TimeInterval = 120,
         auth: Auth = .auth(),
         userRepository: UserRepository = .shared) {
        self.debounceInterval = debounceInterval
        self.auth = auth
        self.userRepository = userRepository
    }

    /// Records current user's activity on Firestore if authenticated and not within the debounce window.
    func recordActivityIfNeeded(force: Bool = false, now: Date = Date()) {
        guard let uid = auth.currentUser?.uid else { return }

        if !force, let last = lastRecordedTime, now.timeIntervalSince(last) < debounceInterval {
            return
        }

        lastRecordedTime = now
        Task {
            let todayStr = UserRepository.dayFormatter.string(from: now)
            let fields = UserFieldUpdate.lastActive(day: todayStr)
            try? await userRepository.updateFields(uid: uid, fields)
        }
    }
}
