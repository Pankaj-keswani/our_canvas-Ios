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
    
    func requestPermission() {
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        
        Messaging.messaging().delegate = self
    }
    
    // MARK: - MessagingDelegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData(["fcmToken": token]) { error in
            if let error = error {
                print("Error saving FCM token: \(error)")
            }
        }
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
