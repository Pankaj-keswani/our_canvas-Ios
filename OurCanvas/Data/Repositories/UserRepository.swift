import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Profile access surface used by the router (mockable in tests).
protocol UserProfileProviding {
    func fetchOrCreateProfile(uid: String,
                              fallbackDisplayName: String?,
                              fallbackEmail: String?) async throws -> User
    func updateFields(uid: String, _ fields: [String: Any]) async throws
    func completeOnboarding(uid: String, version: Int) async throws
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
    private var userListener: ListenerRegistration?

    func startListeningToUser(uid: String) {
        userListener?.remove()
        userListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, snapshot.exists, let data = snapshot.data() else { return }
            let user = self.mapTestUserPlan(User.from(documentID: snapshot.documentID, data: data))
            self.cache(user, uid: uid)
            self.publishIfCurrent(user, uid: uid)
        }
    }

    func stopListeningToUser() {
        userListener?.remove()
        userListener = nil
    }

    // MARK: - ProfileProviding

    func fetchOrCreateProfile(uid: String,
                              fallbackDisplayName: String?,
                              fallbackEmail: String?) async throws -> User {
        if let cached = cachedUser(uid) {
            publishIfCurrent(cached, uid: uid)
            return cached
        }

        let docRef = db.collection("users").document(uid)
        let snapshot: DocumentSnapshot
        do {
            snapshot = try await withThrowingTaskGroup(of: DocumentSnapshot.self) { group in
                group.addTask {
                    try await docRef.getDocument()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    throw AppError.underlying("Profile fetch timeout")
                }
                let res = try await group.next()!
                group.cancelAll()
                return res
            }
        } catch {
            if let cached = cachedUser(uid) {
                publishIfCurrent(cached, uid: uid)
                return cached
            }
            let fallbackName = (Auth.auth().currentUser?.displayName ?? fallbackDisplayName)?.trimmed ?? ""
            if !fallbackName.isEmpty {
                var user = User()
                user.uid = uid
                user.displayName = fallbackName
                user.email = fallbackEmail ?? ""
                publishIfCurrent(user, uid: uid)
                return user
            }
            throw error
        }

        if snapshot.exists, let data = snapshot.data() {
            var user = mapTestUserPlan(User.from(documentID: snapshot.documentID, data: data))
            checkAndBackfillEstablishedAccount(user: &user, data: data, docRef: docRef, uid: uid)
            cache(user, uid: uid)
            publishIfCurrent(user, uid: uid)
            startListeningToUser(uid: uid)
            return user
        }

        // Cache miss: do NOT interpret a cache miss as "user has no profile doc".
        if snapshot.metadata.isFromCache {
            let fallbackName = (Auth.auth().currentUser?.displayName ?? fallbackDisplayName)?.trimmed ?? ""
            var user = User()
            user.uid = uid
            user.displayName = fallbackName
            user.email = fallbackEmail ?? ""
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
        startListeningToUser(uid: uid)
        return user
    }

    /// Fetches without creating. Returns nil when the document does not exist.
    func getUser(uid: String, ignoreCache: Bool = false) async throws -> User? {
        if !ignoreCache, let cached = cachedUser(uid) {
            publishIfCurrent(cached, uid: uid)
            return cached
        }
        let docRef = db.collection("users").document(uid)
        let snapshot = try await docRef.getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        var user = mapTestUserPlan(User.from(documentID: snapshot.documentID, data: data))
        checkAndBackfillEstablishedAccount(user: &user, data: data, docRef: docRef, uid: uid)
        cache(user, uid: uid)
        publishIfCurrent(user, uid: uid)
        return user
    }

    /// Fast-path profile check: checks local Auth displayName first, queries Firestore with timeout,
    /// and treats cache misses or timeouts safely as false so users are never stranded.
    func needsProfileSetup(uid: String) async -> Bool {
        if let authName = Auth.auth().currentUser?.displayName?.trimmed, !authName.isEmpty {
            return false
        }

        let docRef = db.collection("users").document(uid)
        do {
            let snapshot: DocumentSnapshot = try await withThrowingTaskGroup(of: DocumentSnapshot.self) { group in
                group.addTask {
                    try await docRef.getDocument()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    throw AppError.underlying("Profile check timeout")
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }

            if !snapshot.exists {
                if snapshot.metadata.isFromCache {
                    return false
                }
                return true
            }

            let data = snapshot.data() ?? [:]
            let name = FieldCast.string(data["displayName"])?.trimmed ?? ""
            return name.isEmpty
        } catch {
            return false
        }
    }

    /// Checks if a returning user is an established account missing onboardingVersion.
    /// If established, sets onboardingVersion: 1, updates local store & UserDefaults, and backfills Firestore with merge.
    private func checkAndBackfillEstablishedAccount(user: inout User,
                                                    data: [String: Any],
                                                    docRef: DocumentReference,
                                                    uid: String) {
        let rawVersion = data["onboardingVersion"]
        let isMissingOrNull = (rawVersion == nil || rawVersion is NSNull)
        let isVersionZero = user.onboardingVersion == 0

        if isMissingOrNull || isVersionZero {
            let hasDisplayName = !user.displayName.trimmed.isEmpty
            let hasDrawings = user.drawingCount > 0
            let isOldAccount: Bool
            if let createdAt = user.createdAt {
                isOldAccount = Date().timeIntervalSince(createdAt) > 120
            } else {
                isOldAccount = false
            }

            if hasDisplayName || hasDrawings || isOldAccount {
                user.onboardingVersion = 1
                var store = UserScopedStore(uid: uid)
                store.onboardingCompleted = true
                store.walkthroughStep = WalkthroughOverlay.totalSteps
                UserDefaults.standard.set(true, forKey: "onboarding_completed")
                Task {
                    try? await docRef.setData(["onboardingVersion": 1], merge: true)
                }
            }
        }
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
        if Auth.auth().currentUser?.uid == uid {
            if let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest() {
                changeRequest.displayName = name
                try? await changeRequest.commitChanges()
            }
        }
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
        try await db.collection("users").document(uid).setData(
            UserFieldUpdate.onboardingVersion(version),
            merge: true
        )
        memoryCache[uid] = nil
        if uid == Auth.auth().currentUser?.uid {
            _ = try? await getUser(uid: uid, ignoreCache: true)
        }
    }

    func updateFCMToken(uid: String, token: String) async throws {
        try await updateFields(uid: uid, UserFieldUpdate.fcmToken(token))
    }

    // MARK: - Coins Economy (atomic transactions)

    func addCoins(uid: String, amount: Int) async throws {
        guard amount > 0 else { return }
        let userRef = db.collection("users").document(uid)
        _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(userRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            let currentCoins = FieldCast.int(snapshot.data()?["coins"]) ?? 3
            let newCoins = currentCoins + amount
            transaction.updateData(["coins": newCoins], forDocument: userRef)
            return newCoins
        }
        memoryCache[uid] = nil
        if uid == Auth.auth().currentUser?.uid {
            _ = try? await getUser(uid: uid, ignoreCache: true)
        }
    }

    func deductCoins(uid: String, amount: Int) async throws -> Bool {
        guard amount > 0 else { return true }
        let userRef = db.collection("users").document(uid)
        let success = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(userRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            let currentCoins = FieldCast.int(snapshot.data()?["coins"]) ?? 3
            if currentCoins < amount {
                return false
            }
            let newCoins = currentCoins - amount
            transaction.updateData(["coins": newCoins], forDocument: userRef)
            return true
        } as? Bool ?? false

        if success {
            memoryCache[uid] = nil
            if uid == Auth.auth().currentUser?.uid {
                _ = try? await getUser(uid: uid, ignoreCache: true)
            }
        }
        return success
    }

    // MARK: - Drawing-send analytics (Android A8.2 parity, field-level only)

    /// Updates streaks/counters/favorites after a successful drawing send.
    /// Read-modify-write on the non-incrementable fields (streaks, mostUsed*),
    /// `FieldValue.increment` style semantics achieved by explicit computed maps.
    func recordDrawingSent(uid: String, strokes: [Stroke]) async throws {
        var fields: [String: Any] = [:]

        let today = Self.dayFormatter.string(from: Date())

        var colorCounts: [String: Int] = [:]
        var brushCounts: [String: Int] = [:]
        for stroke in strokes where !stroke.isEraser {
            let hex = StrokeColor.hexString(fromARGB: stroke.color).uppercased()
            colorCounts[hex, default: 0] += 1
            brushCounts[stroke.brush.rawValue, default: 0] += 1
        }

        // Start from the freshest profile (bypass cache) so concurrent devices merge cleanly.
        let profile = try await getUser(uid: uid, ignoreCache: true)

        var mergedColors = profile?.colorCounts ?? [:]
        for (hex, count) in colorCounts { mergedColors[hex, default: 0] += count }
        var mergedBrushes = profile?.brushCounts ?? [:]
        for (brush, count) in brushCounts { mergedBrushes[brush, default: 0] += count }

        fields["drawingCount"] = (profile?.drawingCount ?? 0) + 1
        fields["colorCounts"] = mergedColors
        fields["brushCounts"] = mergedBrushes
        if let topColor = mergedColors.max(by: { $0.value < $1.value })?.key {
            fields["mostUsedColor"] = topColor
        }
        if let topBrush = mergedBrushes.max(by: { $0.value < $1.value })?.key {
            fields["mostUsedBrush"] = topBrush.capitalized
        }

        // Streak: consecutive active days; breaks after a missed day.
        if let profile {
            if profile.lastActiveDate != today {
                let yesterday = Self.dayFormatter.string(from: Date().addingTimeInterval(-86400))
                let isYesterday = profile.lastActiveDate == yesterday
                if isYesterday {
                    let newStreak = profile.currentStreak + 1
                    fields["currentStreak"] = newStreak
                    fields["longestStreak"] = max(profile.longestStreak, newStreak)
                    fields["lastActiveDate"] = today
                } else {
                    // Missed day: streak broken! Store metadata for recovery before resetting.
                    fields["previousBrokenStreak"] = profile.currentStreak
                    fields["streakBrokenDate"] = yesterday
                    fields["currentStreak"] = 1
                    fields["longestStreak"] = max(profile.longestStreak, 1)
                    fields["lastActiveDate"] = today
                }
            }
        } else {
            fields["currentStreak"] = 1
            fields["longestStreak"] = 1
            fields["lastActiveDate"] = today
        }

        try await updateFields(uid: uid, fields)
        StreakWarningManager.shared.onDrawingSent(uid: uid)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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

    func cachedUser(_ uid: String) -> User? {
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
