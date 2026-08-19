import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import CryptoKit

class PremiumManager: ObservableObject {
    @Published var premiumState = PremiumState()
    private let db = Firestore.firestore()
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func redeemWelcomePromoCode(code: String) async throws -> (Int, Date) {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Couldn't verify the promo right now. Please try again."])
        }
        
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let campaign = PromoCampaign.findCampaign(code: trimmedCode) else {
            throw NSError(domain: "Promo", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid promo code."])
        }
        
        if !campaign.enabled {
            throw NSError(domain: "Promo", code: 400, userInfo: [NSLocalizedDescriptionKey: "Welcome offers are available to new users only."])
        }
        
        let userEmail = currentUser.email ?? ""
        if userEmail.isEmpty {
            throw NSError(domain: "Promo", code: 400, userInfo: [NSLocalizedDescriptionKey: "A valid email address is required to redeem welcome promo."])
        }
        
        DispatchQueue.main.async {
            self.premiumState.isLoading = true
        }
        
        let identityHash = sha256(userEmail.lowercased())
        let redemptionId = "\(trimmedCode)_\(identityHash)"
        
        // 1. Cloud Function Attempt
        do {
            let functions = Functions.functions()
            let result = try await functions.httpsCallable("redeemWelcomePromo").call(["promoCode": trimmedCode])
            if let data = result.data as? [String: Any], data["success"] as? Bool == true {
                let durationDays = data["durationDays"] as? Int ?? campaign.durationDays
                let newExpirySeconds = data["newExpirySeconds"] as? TimeInterval ?? Date().timeIntervalSince1970
                DispatchQueue.main.async { self.premiumState.isLoading = false }
                return (durationDays, Date(timeIntervalSince1970: newExpirySeconds))
            }
        } catch {
            print("Cloud Function failed: \(error), falling back to transaction")
        }
        
        // 2. Fallback: Atomic Transaction
        let redemptionRef = db.collection("promo_redemptions").document(redemptionId)
        let userRef = db.collection("users").document(currentUser.uid)
        
        do {
            let result = try await db.runTransaction { (transaction, errorPointer) -> Any? in
                let redemptionSnapshot: DocumentSnapshot
                let userSnapshot: DocumentSnapshot
                
                do {
                    redemptionSnapshot = try transaction.getDocument(redemptionRef)
                    userSnapshot = try transaction.getDocument(userRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                if redemptionSnapshot.exists {
                    errorPointer?.pointee = NSError(domain: "Promo", code: 400, userInfo: [NSLocalizedDescriptionKey: "ALREADY_CLAIMED: You've already claimed this welcome offer."])
                    return nil
                }
                
                let currentExpiry = userSnapshot.data()?["premiumExpiry"] as? Timestamp
                let lifetimeThreshold = Timestamp(date: Date(timeIntervalSince1970: 32503680000 - 86400))
                
                if let expiry = currentExpiry, expiry.seconds >= lifetimeThreshold.seconds {
                    errorPointer?.pointee = NSError(domain: "Promo", code: 400, userInfo: [NSLocalizedDescriptionKey: "You already have Lifetime Premium."])
                    return nil
                }
                
                let additionSeconds = TimeInterval(campaign.durationDays * 86400)
                let calculatedExpiry: Timestamp
                if let expiry = currentExpiry, expiry.dateValue() > Date() {
                    calculatedExpiry = Timestamp(date: expiry.dateValue().addingTimeInterval(additionSeconds))
                } else {
                    calculatedExpiry = Timestamp(date: Date().addingTimeInterval(additionSeconds))
                }
                
                transaction.setData([
                    "promoCode": trimmedCode,
                    "identityHash": identityHash,
                    "originalUid": currentUser.uid,
                    "redeemedAt": FieldValue.serverTimestamp(),
                    "durationGrantedDays": campaign.durationDays
                ], forDocument: redemptionRef)
                
                transaction.updateData([
                    "plan": "pro",
                    "premiumSource": "WELCOME_PROMO",
                    "premiumExpiry": calculatedExpiry,
                    "lastRedeemedPromo": trimmedCode,
                    "lastPremiumUpdate": FieldValue.serverTimestamp()
                ], forDocument: userRef)
                
                return [calculatedExpiry, campaign.durationDays]
            }
            
            DispatchQueue.main.async { self.premiumState.isLoading = false }
            if let resArr = result as? [Any], let expiry = resArr[0] as? Timestamp, let days = resArr[1] as? Int {
                return (days, expiry.dateValue())
            }
            throw NSError(domain: "Promo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
        } catch {
            DispatchQueue.main.async {
                self.premiumState.isLoading = false
                self.premiumState.lastError = error.localizedDescription
            }
            throw error
        }
    }
}
