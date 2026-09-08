import Foundation
import FirebaseFirestore
import FirebaseAuth

/// `premium_codes/{code}` redemption (Android A7.2 CODE path — rules-compatible
/// via `isRedeemCodeUpdate`): single-use, expiry-checked, transaction-safe.
final class PromoCodeService {

    private let db = Firestore.firestore()

    enum RedemptionOutcome: Equatable {
        case success(days: Int)
        case alreadyUsed
        case expired
        case invalidCode
        case alreadyPro
    }

    /// Pure code validation (tested): shape + expiry predicate helpers.
    static func isValidCodeFormat(_ code: String) -> Bool {
        let trimmed = code.trimmed.uppercased()
        return trimmed.count >= 4 && trimmed.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil
    }

    static func isExpired(expiresAt: Date?, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now > expiresAt
    }

    func redeem(code: String, uid: String) async throws -> RedemptionOutcome {
        let normalized = code.trimmed.uppercased()
        guard Self.isValidCodeFormat(normalized) else { return .invalidCode }

        let codeRef = db.collection("premium_codes").document(normalized)
        let userRef = db.collection("users").document(uid)

        let result: Any? = try await db.runTransaction { transaction, errorPointer in
            guard let codeSnapshot = try? transaction.getDocument(codeRef) else {
                errorPointer?.pointee = NSError(domain: "Promo", code: 404,
                                                userInfo: [NSLocalizedDescriptionKey: "invalid"])
                return nil
            }
            guard let codeData = codeSnapshot.data() else {
                errorPointer?.pointee = NSError(domain: "Promo", code: 404,
                                                userInfo: [NSLocalizedDescriptionKey: "invalid"])
                return nil
            }

            // Single-use + status checks.
            let used = codeData["used"] as? Bool ?? false
            let status = codeData["status"] as? String ?? ""
            if used || status == "USED" {
                errorPointer?.pointee = NSError(domain: "Promo", code: 409,
                                                userInfo: [NSLocalizedDescriptionKey: "alreadyUsed"])
                return nil
            }
            let expiresAt = (codeData["expiresAt"] as? Timestamp)?.dateValue()
            if Self.isExpired(expiresAt: expiresAt) {
                errorPointer?.pointee = NSError(domain: "Promo", code: 410,
                                                userInfo: [NSLocalizedDescriptionKey: "expired"])
                return nil
            }

            guard let userSnapshot = try? transaction.getDocument(userRef),
                  let userData = userSnapshot.data() else {
                errorPointer?.pointee = NSError(domain: "Promo", code: 401,
                                                userInfo: [NSLocalizedDescriptionKey: "auth"])
                return nil
            }

            // Already lifetime-pro users can't redeem again.
            let expiry = (userData["premiumExpiry"] as? Timestamp)?.dateValue()
            if let expiry, expiry > Date(timeIntervalSince1970: 32503680000 - 86400) {
                errorPointer?.pointee = NSError(domain: "Promo", code: 409,
                                                userInfo: [NSLocalizedDescriptionKey: "alreadyPro"])
                return nil
            }

            let durationDays = (codeData["durationDays"] as? Int) ?? 30
            let baseExpiry = expiry ?? Date()
            let newExpiry = baseExpiry > Date() ? baseExpiry.addingTimeInterval(TimeInterval(durationDays) * 86400)
                                                : Date().addingTimeInterval(TimeInterval(durationDays) * 86400)

            // CODE-path fields — exactly the rules whitelist for isRedeemCodeUpdate.
            transaction.updateData([
                "status": "USED",
                "used": true,
                "redeemedBy": uid,
            ], forDocument: codeRef)

            transaction.updateData([
                "plan": "pro",
                "premiumSource": "CODE",
                "premiumExpiry": Timestamp(date: newExpiry),
                "lastRedeemedCode": normalized,
                "lastPremiumUpdate": FieldValue.serverTimestamp(),
            ], forDocument: userRef)

            return "success"
        }

        return (result as? String) == "success" ? .success(days: 0) : .invalidCode
    }

    /// Maps transaction error keys to outcomes (tested).
    static func outcome(forErrorDescription description: String?) -> RedemptionOutcome {
        switch description {
        case "alreadyUsed": return .alreadyUsed
        case "expired": return .expired
        case "alreadyPro": return .alreadyPro
        default: return .invalidCode
        }
    }
}
