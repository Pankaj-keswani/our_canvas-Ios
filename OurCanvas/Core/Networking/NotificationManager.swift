import Foundation
import UserNotifications
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {

    static let shared = NotificationManager()

    private let deviceStore = DeviceLocalStore()

    /// Sets delegates only. Called at app launch; safe before authentication.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }

    /// Requests notification permission at the login-equivalent moment (first entry to Main),
    /// matching the Android runtime-permission gate. Idempotent per install.
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

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Cache-first: PushTokenStore associates with the user whenever they sign in.
        PushTokenStore.shared.tokenDidUpdate(fcmToken)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Handle foreground notifications
        let userInfo = notification.request.content.userInfo
        handleFCMData(userInfo: userInfo)

        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap
        let userInfo = response.notification.request.content.userInfo
        handleFCMData(userInfo: userInfo)

        completionHandler()
    }

    private func handleFCMData(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }

        let drawingId = userInfo["drawingId"] as? String ?? ""
        let groupId = userInfo["groupId"] as? String ?? userInfo["gId"] as? String ?? ""

        switch type {
        case "new_drawing":
            let senderName = userInfo["senderName"] as? String ?? "Someone"
            print("Received new_drawing from \(senderName) in group \(groupId)")
            // Trigger WidgetKit reload
            reloadWidgets()

        case "new_reaction":
            let reactorName = userInfo["reactorName"] as? String ?? "Someone"
            let emoji = userInfo["emoji"] as? String ?? "❤️"
            print("Received reaction \(emoji) from \(reactorName) on drawing \(drawingId)")
            reloadWidgets()

        case "new_game_turn", "guess_result":
            // Guess My Doodle push handling lands with the games phase.
            print("Received \(type) push (handling arrives with the games phase)")

        default:
            print("Unhandled FCM type: \(type)")
        }
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
