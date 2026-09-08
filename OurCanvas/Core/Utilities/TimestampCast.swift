import Foundation
import FirebaseFirestore

/// Timestamp tolerance for Firestore values that may arrive as Timestamp, Date or NSNumber(seconds).
enum TimestampCast {
    static func date(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
