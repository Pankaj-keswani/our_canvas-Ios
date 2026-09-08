import Foundation
import UserNotifications
import FirebaseMessaging
import FirebaseAuth
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Push reception, receiver-side persistence and system presentation.
///
/// Contract (Android A9 parity):
/// - 4 payload types validated/defaulted via `PushPayload.parse` (whitelist).
/// - The CURRENT user's own notification document is persisted (never another
///   user's; cross-user fan-out is worker-authoritative).
/// - Data-only FCM messages don't banner by themselves on iOS → a local
///   notification is composed in the foreground path. Background delivery of
///   data-only payloads is best-effort (iOS does not guarantee it) — the app
///   flushes any queued payloads on foreground.
/// - Taps route through the Phase 0 deep-link foundation (pending route survives
///   cold launch via device storage).
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {

    static let shared = NotificationManager()

    private var deviceStore = DeviceLocalStore()
    private let repository = NotificationRepository()

    /// Router set at app start; taps/payloads park routes until Main is ready.
    weak var router: AppRouter?

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }

    /// Requests notification permission at the login-equivalent moment (first entry
    /// to Main), matching the Android runtime-permission gate. Idempotent per install.
    func requestAuthorizationIfNeeded() {
        if deviceStore.notificationsPermissionRequested {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }
        deviceStore.notificationsPermissionRequested = true
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { _, _ in
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - MessagingDelegate (FCM token lifecycle — Phase 0, unchanged)

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        PushTokenStore.shared.tokenDidUpdate(fcmToken)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        // Settings gate: a muted category shows nothing — no banner, no sound.
        if let payload = PushPayload.parse(userInfo),
           !Self.currentPreferences().isEnabled(for: payload.type) {
            completionHandler([])
            return
        }
        handleIncoming(userInfo: userInfo, fromSystemNotification: true)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Notification tap → deep link via the router (survives cold launch).
        let userInfo = response.notification.request.content.userInfo
        if let payload = PushPayload.parse(userInfo), let url = payload.deepLinkURL() {
            DispatchQueue.main.async {
                if let router = self.router {
                    router.openURL(url)
                } else {
                    self.deviceStore.pendingDeepLinkURL = url.absoluteString
                }
            }
        }
        handleIncoming(userInfo: userInfo, fromSystemNotification: false)
        completionHandler()
    }

    // MARK: - Payload handling (foreground + tap paths)

    func handleIncoming(userInfo: [AnyHashable: Any], fromSystemNotification: Bool) {
        guard let payload = PushPayload.parse(userInfo) else { return }

        DispatchQueue.main.async {
            // Settings gate (muted category → no banner, no history entry; the
            // notification "doesn't come" on this device until re-enabled).
            let preferences = Self.currentPreferences()

            if preferences.isEnabled(for: payload.type) {
                self.persist(payload: payload)

                // FCM data-only messages never banner on their own — compose a local
                // notification when we're in the foreground (or arriving via tap).
                if !fromSystemNotification || UIApplication.shared.applicationState == .active {
                    self.presentLocally(payload: payload)
                }
            }

            // Widget content refresh is not a user-facing notification — keep it.
            switch payload.type {
            case .newDrawing, .newReaction, .newGameTurn, .guessResult, .memberJoined:
                self.reloadWidgets()
            }
        }
    }

    /// Current signed-in user's notification preferences (defaults when signed out).
    static func currentPreferences() -> NotificationPreferences {
        guard let uid = Auth.auth().currentUser?.uid else {
            return NotificationPreferences()
        }
        return UserScopedStore(uid: uid).notificationPreferences
    }

    private func persist(payload: PushPayload) {
        guard let uid = Auth.auth().currentUser?.uid else {
            // Not signed in (rare) — nothing to persist; the worker owns fan-out.
            return
        }
        let notification = payload.toInAppNotification(recipientId: uid)
        Task {
            try? await repository.persistOwn(notification: notification, uid: uid)
        }
    }

    private func presentLocally(payload: PushPayload) {
        let notification = payload.toInAppNotification(recipientId: Auth.auth().currentUser?.uid ?? "")

        // Deterministic dedupe: one system banner per notificationId per session
        // (delivered + tapped paths can both reach here).
        let dedupeKey = "notified.\(notification.notificationId)"
        if deviceStore.hasSystemNotified(key: dedupeKey) {
            return
        }
        deviceStore.markSystemNotified(key: dedupeKey)

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.groupId
        content.userInfo = ["type": payload.type.rawValue,
                            "groupId": payload.groupId,
                            "drawingId": payload.drawingId]

        let request = UNNotificationRequest(identifier: notification.notificationId,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

// MARK: - Dedupe keys (bounded set on device storage)

extension DeviceLocalStore {
    private static let systemNotifiedKey = "device.systemNotifiedKeys"

    func hasSystemNotified(key: String) -> Bool {
        Set(defaults.stringArray(forKey: Self.systemNotifiedKey) ?? []).contains(key)
    }

    func markSystemNotified(key: String) {
        var keys = Set(defaults.stringArray(forKey: Self.systemNotifiedKey) ?? [])
        keys.insert(key)
        // Bound the set so defaults never grow unbounded.
        if keys.count > 100 {
            keys = Set(keys.suffix(100))
        }
        defaults.set(Array(keys), forKey: Self.systemNotifiedKey)
    }
}
