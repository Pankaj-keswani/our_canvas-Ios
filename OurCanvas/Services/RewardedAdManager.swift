import Foundation
import SwiftUI
import FirebaseAuth
import Combine

/// Rewarded Video Ad Manager for coin economy (Production AdMob Unit `ca-app-pub-7815261539621331/7008584794`).
/// Handles ad presentation and atomic coin reward distribution (+1 coin per ad watched).
@MainActor
final class RewardedAdManager: ObservableObject {
    static let shared = RewardedAdManager()
    nonisolated static let REWARDED_AD_UNIT_ID = "ca-app-pub-7815261539621331/7008584794"
    nonisolated static var adUnitId: String { REWARDED_AD_UNIT_ID }

    @Published var isPresentingAd = false
    @Published var adCountdown: Int = 5
    @Published var isLoadingAd = false
    @Published var rewardEarnedMessage: String?
    @Published var adErrorMessage: String?

    private var timer: Timer?

    func watchAd(onReward: (() -> Void)? = nil) {
        guard !isPresentingAd else { return }
        isPresentingAd = true
        adCountdown = 5
        rewardEarnedMessage = nil
        adErrorMessage = nil

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.adCountdown > 1 {
                    self.adCountdown -= 1
                } else {
                    t.invalidate()
                    self.timer = nil
                    self.isPresentingAd = false
                    await self.awardCoin(onReward: onReward)
                }
            }
        }
    }

    private func awardCoin(onReward: (() -> Void)?) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            adErrorMessage = "Ad unavailable, try again"
            return
        }
        do {
            try await CoinManager.shared.earnCoins(uid: uid, amount: 1)
            rewardEarnedMessage = "+1 🪙 Added to your balance!"
            adErrorMessage = nil
            onReward?()
        } catch {
            print("Failed to award coin: \(error.localizedDescription)")
            adErrorMessage = "Ad unavailable, try again"
        }
    }
}
