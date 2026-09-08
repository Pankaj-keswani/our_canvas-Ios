import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // Delegates only — the notification PERMISSION prompt is deferred to the
        // login-equivalent moment (MainTabView.onAppear), matching Android's behavior.
        NotificationManager.shared.configure()

        // FCM token persistence: users/{uid}.fcmToken via field-level update.
        // PushTokenStore owns caching + re-association, so token delivery timing
        // relative to login no longer matters.
        PushTokenStore.shared.persistHandler = { token, uid in
            Firestore.firestore().collection("users").document(uid).updateData(["fcmToken": token]) { error in
                if let error {
                    print("PushTokenStore: failed to persist FCM token: \(error.localizedDescription)")
                }
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

@main
struct OurCanvasApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
