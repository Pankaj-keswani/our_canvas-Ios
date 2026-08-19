import Foundation
import FirebaseFirestore

struct PromoCampaign: Codable {
    var code: String
    var durationDays: Int
    var isWelcomePromo: Bool = false
    var enabled: Bool = true
    
    static let welcomeCampaigns: [String: PromoCampaign] = [
        "WELCOME3": PromoCampaign(code: "WELCOME3", durationDays: 3, isWelcomePromo: true, enabled: true),
        "WELCOME7": PromoCampaign(code: "WELCOME7", durationDays: 7, isWelcomePromo: true, enabled: true),
        "WELCOME15": PromoCampaign(code: "WELCOME15", durationDays: 15, isWelcomePromo: true, enabled: true)
    ]
    
    static func findCampaign(code: String) -> PromoCampaign? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return welcomeCampaigns[normalized]
    }
}
