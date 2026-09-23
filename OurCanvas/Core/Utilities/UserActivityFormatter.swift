import Foundation

/// Pure utility for formatting user activity timestamps and calculating online status.
struct UserActivityFormatter {

    /// Default online threshold: 5 minutes (300 seconds).
    static let onlineThreshold: TimeInterval = 300

    /// Returns true if the user was active within the given threshold.
    static func isOnline(lastActiveAt: Date?, threshold: TimeInterval = onlineThreshold, now: Date = Date()) -> Bool {
        guard let date = lastActiveAt else { return false }
        let diff = now.timeIntervalSince(date)
        return diff >= 0 && diff < threshold
    }

    /// Formats a last active timestamp into a human-readable string.
    /// Examples:
    /// - "Active now" (less than 5 minutes ago)
    /// - "Active 15m ago"
    /// - "Active 3h ago"
    /// - "Active yesterday"
    /// - "Active Sep 19"
    /// - "Offline" (if timestamp is nil)
    static func format(lastActiveAt: Date?, now: Date = Date(), locale: Locale = .current) -> String {
        guard let date = lastActiveAt else { return "Offline" }

        let diff = now.timeIntervalSince(date)
        if diff < 0 {
            return "Active now"
        }

        if diff < onlineThreshold {
            return "Active now"
        }

        if diff < 3600 {
            let minutes = max(1, Int(diff / 60))
            return "Active \(minutes)m ago"
        }

        if diff < 86400 {
            let hours = max(1, Int(diff / 3600))
            return "Active \(hours)h ago"
        }

        if diff < 172800 {
            return "Active yesterday"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "MMM d"
        return "Active \(formatter.string(from: date))"
    }
}
