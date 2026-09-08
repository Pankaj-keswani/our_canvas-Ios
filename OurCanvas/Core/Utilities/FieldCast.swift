import Foundation

/// Tolerant field casting for decoding Firestore documents that may have been
/// written by Android (or older iOS versions) with different numeric/storage types.
/// Unknown fields are naturally ignored; missing fields fall back to defaults at call sites.
enum FieldCast {
    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func int(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? Int64 { return Int(v) }
        if let v = value as? Double { return Int(v) }
        if let v = value as? NSNumber { return v.intValue }
        return nil
    }

    static func int64(_ value: Any?) -> Int64? {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? Double { return Int64(v) }
        if let v = value as? NSNumber { return v.int64Value }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let v = value as? Double { return v }
        if let v = value as? Int { return Double(v) }
        if let v = value as? NSNumber { return v.doubleValue }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let v = value as? Bool { return v }
        if let v = value as? NSNumber { return v.boolValue }
        return nil
    }

    static func stringArray(_ value: Any?) -> [String]? {
        value as? [String]
    }

    static func intStringMap(_ value: Any?) -> [String: Int]? {
        guard let raw = value as? [String: Any] else { return nil }
        return raw.mapValues { int($0) ?? 0 }
    }

    /// Accepts either a JSON string (current iOS) or a native array/map (Android schema)
    /// and normalizes to a JSON string.
    static func jsonString(from value: Any?) -> String? {
        if let s = value as? String { return s }
        guard let obj = value else { return nil }
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }
}
