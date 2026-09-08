import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Profile access surface used by the router (mockable in tests).
protocol UserProfileProviding {
    func fetchOrCreateProfile(uid: String,
                              fallbackDisplayName: String?,
                              fallbackEmail: String?) async throws -> User
    func updateFields(uid: String, _ fields: [String: Any]) async throws
}

/// Repository for `users/{uid}`.
///
/// SAFETY RULE: this repository never performs full-document replacement on existing user
/// documents. Creation writes `User.creationFields` once on a new document; every later write
/// goes through `updateFields` with a narrow field payload so fields written by Android or
/// other services can never be clobbered by iOS.
class UserRepository: ObservableObject, UserProfileProviding {
    static let shared = UserRepository()

    private let db = Firestore.firestore()

    @Published var currentUserProfile: User?

    /// 10-minute cache TTL — parity with the Android user-profile cache (spec A8.1).
    static let profileCacheTTL: TimeInterval = 600

    private var memoryCache: [String: (user: User, fetchedAt: Date)] = [:]

    // MARK: - ProfileProviding

    func fetchOrCreateProfile(uid: String,
                              fallbackDisplayName: String?,
                              fallbackEmail: String?) async throws -> User {
        if let cached = cachedUser(uid) {
            publishIfCurrent(cached, uid: uid)
            return cached
        }

        let docRef = db.collection("users").document(uid)
        let snapshot = try await docRef.getDocument()
        if snapshot.exists, let data = snapshot.data() {
            let user = mapTestUserPlan(User.from(documentID: snapshot.documentID, data: data))
            cache(user, uid: uid)
            publishIfCurrent(user, uid: uid)
            return user
        }

        // First login on this account: create the initial document. This is the ONLY place
        // a user document is written in full, and only when it does not exist yet.
        let fields = User.creationFields(uid: uid,
                                         displayName: fallbackDisplayName ?? "",
                                         email: fallbackEmail ?? "")
        try await docRef.setData(fields)
        let user = mapTestUserPlan(User.from(documentID: uid, data: fields))
        cache(user, uid: uid)
        publishIfCurrent(user, uid: uid)
        return user
    }

    /// Fetches without creating. Returns nil when the document does not exist.
    func getUser(uid: String, ignoreCache: Bool = false) async throws -> User? {
        if !ignoreCache, let cached = cachedUser(uid) {
            publishIfCurrent(cached, uid: uid)
            return cached
        }
        let snapshot = try await db.collection("users").document(uid).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        let user = mapTestUserPlan(User.from(documentID: snapshot.documentID, data: data))
        cache(user, uid: uid)
        publishIfCurrent(user, uid: uid)
        return user
    }

    // MARK: - Field-safe updates

    /// THE update path for user documents. Applies only the given fields via updateData,
    /// leaving every other field (including Android-written ones) untouched.
    func updateFields(uid: String, _ fields: [String: Any]) async throws {
        try await db.collection("users").document(uid).updateData(fields)
        // Invalidate cache and re-fetch so currentUserProfile reflects the change.
        memoryCache[uid] = nil
        if uid == Auth.auth().currentUser?.uid {
            _ = try? await getUser(uid: uid, ignoreCache: true)
        }
    }

    func updateDisplayName(uid: String, _ name: String) async throws {
        try await updateFields(uid: uid, UserFieldUpdate.displayName(name))
    }

    func updateAvatar(uid: String, base64: String) async throws {
        try await updateFields(uid: uid, UserFieldUpdate.profilePicture(base64))
    }

    func updateHideEmail(uid: String, _ value: Bool) async throws {
        try await updateFields(uid: uid, UserFieldUpdate.hideEmail(value))
    }

    func markWhatsNewSeen(uid: String, version: Int) async throws {
        try await updateFields(uid: uid, UserFieldUpdate.whatsNewSeenVersion(version))
    }

    func completeOnboarding(uid: String, version: Int) async throws {
        try await updateFields(uid: uid, UserFieldUpdate.onboardingVersion(version))
    }

    func updateFCMToken(uid: String, token: String) async throws {
        try await updateFields(uid: uid, UserFieldUpdate.fcmToken(token))
    }

    // MARK: - Batch fetch

    func getUsersBatch(uids: [String]) async throws -> [String: User] {
        if uids.isEmpty { return [:] }
        var results: [String: User] = [:]
        var uncachedUids: [String] = []

        for uid in uids {
            if let cached = cachedUser(uid) {
                results[uid] = cached
            } else {
                uncachedUids.append(uid)
            }
        }

        if uncachedUids.isEmpty { return results }

        let chunks = uncachedUids.chunked(into: 10)

        try await withThrowingTaskGroup(of: [User].self) { group in
            for chunk in chunks {
                group.addTask {
                    let snapshot = try await self.db.collection("users")
                        .whereField(FieldPath.documentID(), in: chunk)
                        .getDocuments()
                    return snapshot.documents.map { doc in
                        User.from(documentID: doc.documentID, data: doc.data())
                    }
                }
            }

            for try await users in group {
                for user in users {
                    let finalUser = self.mapTestUserPlan(user)
                    self.cache(finalUser, uid: user.uid)
                    results[user.uid] = finalUser
                }
            }
        }
        return results
    }

    // MARK: - Cache

    private func cachedUser(_ uid: String) -> User? {
        guard let entry = memoryCache[uid] else { return nil }
        guard Date().timeIntervalSince(entry.fetchedAt) < Self.profileCacheTTL else {
            memoryCache[uid] = nil
            return nil
        }
        return entry.user
    }

    private func cache(_ user: User, uid: String) {
        memoryCache[uid] = (user, Date())
    }

    private func publishIfCurrent(_ user: User, uid: String) {
        if uid == Auth.auth().currentUser?.uid {
            DispatchQueue.main.async {
                self.currentUserProfile = user
            }
        }
    }

    // MARK: - Test-account override (Android parity: @prempatra.com/.test/@google.com)

    private func mapTestUserPlan(_ user: User) -> User {
        var modified = user
        let email = user.email.lowercased()
        let isTestUser = email.hasSuffix("@prempatra.com") ||
                         email.hasSuffix("@prempatra.test") ||
                         email.hasSuffix("@google.com")
        if isTestUser {
            modified.plan = "pro"
        }
        return modified
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
