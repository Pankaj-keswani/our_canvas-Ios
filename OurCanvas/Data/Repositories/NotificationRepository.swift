import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Repository for the CURRENT USER's notification history (`users/{uid}/notifications`).
/// The client never writes another user's documents — cross-user fan-out belongs to
/// the worker; this path is receiver-side persistence only (Android parity).
final class NotificationRepository {

    /// Hub display cap (Android A6.2).
    static let displayCap = 20
    /// Auto-cleanup window.
    static let cleanupAge: TimeInterval = 30 * 24 * 60 * 60
    /// Max documents touched per cleanup pass.
    static let cleanupBatchLimit = 100

    private let db = Firestore.firestore()

    private func collection(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("notifications")
    }

    // MARK: - Listening

    func listen(uid: String,
                onChange: @escaping ([InAppNotification]) -> Void) -> ListenerRegistration {
        collection(uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("Notification listener error: \(error.localizedDescription)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                let notifications = documents
                    .map { InAppNotification.from(documentID: $0.documentID, data: $0.data()) }
                    .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                onChange(notifications)
            }
    }

    // MARK: - Receiver-side persistence (own documents only)

    /// Persists a push payload as the current user's own notification.
    /// Deduplicates by the Android-style stable notificationId; preserves the
    /// original createdAt and read state on re-delivery.
    @discardableResult
    func persistOwn(notification: InAppNotification, uid: String) async throws -> Bool {
        let ref = collection(uid).document(notification.notificationId)
        let snapshot = try await ref.getDocument()
        if snapshot.exists {
            return false // duplicate delivery — original timestamp/state preserved
        }
        try await ref.setData(notification.fields())
        return true
    }

    // MARK: - Actions

    func markAsRead(uid: String, notificationId: String) async throws {
        try await collection(uid).document(notificationId).updateData(["read": true])
    }

    func markAllRead(uid: String, notificationIds: [String]) async throws {
        guard !notificationIds.isEmpty else { return }
        let batch = db.batch()
        for notificationId in notificationIds.prefix(Self.cleanupBatchLimit) {
            batch.updateData(["read": true], forDocument: collection(uid).document(notificationId))
        }
        try await batch.commit()
    }

    func delete(uid: String, notificationId: String) async throws {
        try await collection(uid).document(notificationId).delete()
    }

    func clearAll(uid: String, notificationIds: [String]) async throws {
        guard !notificationIds.isEmpty else { return }
        let batch = db.batch()
        for notificationId in notificationIds.prefix(Self.cleanupBatchLimit) {
            batch.deleteDocument(collection(uid).document(notificationId))
        }
        try await batch.commit()
    }

    // MARK: - Auto-cleanup (30 days, oldest 100 per pass)

    /// Pure date predicate (tested).
    static func isExpired(_ notification: InAppNotification, now: Date = Date()) -> Bool {
        guard let createdAt = notification.createdAt else { return false }
        return now.timeIntervalSince(createdAt) > cleanupAge
    }

    func cleanupExpired(uid: String, notifications: [InAppNotification]) async throws {
        let expired = notifications
            .filter { Self.isExpired($0) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .prefix(Self.cleanupBatchLimit)
        guard !expired.isEmpty else { return }
        let batch = db.batch()
        for notification in expired {
            batch.deleteDocument(collection(uid).document(notification.notificationId))
        }
        try await batch.commit()
    }
}
