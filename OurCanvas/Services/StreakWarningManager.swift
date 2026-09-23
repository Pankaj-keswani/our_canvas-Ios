import Foundation
import UserNotifications
import FirebaseAuth

/// Pure eligibility evaluator for the 60-minute streak expiration alert (Android parity).
struct StreakWarningEligibility {
    static func isEligible(
        isAuthenticated: Bool,
        isNotifyOtherEnabled: Bool,
        currentStreak: Int,
        lastActiveDate: String?,
        lastDrawingSentDate: String?,
        todayDateString: String
    ) -> Bool {
        guard isAuthenticated else { return false }
        guard isNotifyOtherEnabled else { return false }
        guard currentStreak >= 2 else { return false }
        if let lastActive = lastActiveDate, lastActive == todayDateString {
            return false
        }
        if let lastDrawing = lastDrawingSentDate, lastDrawing == todayDateString {
            return false
        }
        return true
    }
}

/// Service managing the 60-minute streak expiration local notification (Android commit 8340ff7).
/// Schedules a recurring 23:00 notification warning users if their >= 2-day streak is at risk of expiring at midnight.
final class StreakWarningManager {
    static let shared = StreakWarningManager()

    static let notificationIdentifier = "streak_expiration_warning"
    static let notifyOtherKey = "notify_other"

    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter

    init(defaults: UserDefaults = .standard, notificationCenter: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    static func lastDrawingSentDateKey(for uid: String) -> String {
        "last_drawing_sent_date_\(uid)"
    }

    static func dayFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        return formatter
    }

    /// Invoked whenever a user sends a drawing to record the send date and cancel any expiring warning.
    func onDrawingSent(uid: String, date: Date = Date(), timeZone: TimeZone = .current) {
        let todayStr = Self.dayFormatter(timeZone: timeZone).string(from: date)
        defaults.set(todayStr, forKey: Self.lastDrawingSentDateKey(for: uid))
        cancelStreakWarning()
    }

    /// Removes any pending or delivered streak expiration notifications.
    func cancelStreakWarning() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    /// Builds notification content with dynamic streak count.
    static func buildNotificationContent(currentStreak: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "🔥 Streak Expiring Soon!"
        content.body = "Your \(currentStreak)-day streak will break in 60 minutes! Send a doodle to keep the flame alive 🔥"
        content.sound = .default
        content.userInfo = [
            "type": notificationIdentifier,
            "route": "home"
        ]
        return content
    }

    /// Builds the 23:00 daily trigger matching local timezone.
    static func buildTrigger() -> UNCalendarNotificationTrigger {
        var dateComponents = DateComponents()
        dateComponents.hour = 23
        dateComponents.minute = 0
        return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
    }

    /// Asynchronously verifies eligibility and schedules or removes the warning.
    func scheduleOrVerifyStreakWarning() {
        Task {
            await scheduleOrVerifyStreakWarningAsync()
        }
    }

    func scheduleOrVerifyStreakWarningAsync() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            cancelStreakWarning()
            return
        }

        let isNotifyOther = (defaults.object(forKey: Self.notifyOtherKey) as? Bool) != false
        guard isNotifyOther else {
            cancelStreakWarning()
            return
        }

        let profile = UserRepository.shared.cachedUser(uid) ?? (try? await UserRepository.shared.getUser(uid: uid))
        guard let profile else { return }

        let todayStr = Self.dayFormatter().string(from: Date())
        let lastDrawingDate = defaults.string(forKey: Self.lastDrawingSentDateKey(for: uid))

        let eligible = StreakWarningEligibility.isEligible(
            isAuthenticated: true,
            isNotifyOtherEnabled: isNotifyOther,
            currentStreak: profile.currentStreak,
            lastActiveDate: profile.lastActiveDate,
            lastDrawingSentDate: lastDrawingDate,
            todayDateString: todayStr
        )

        if eligible {
            let content = Self.buildNotificationContent(currentStreak: profile.currentStreak)
            let trigger = Self.buildTrigger()
            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier,
                content: content,
                trigger: trigger
            )
            try? await notificationCenter.add(request)
        } else {
            cancelStreakWarning()
        }
    }
}
