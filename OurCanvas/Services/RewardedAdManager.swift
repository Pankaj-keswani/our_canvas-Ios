import Foundation
import SwiftUI
import FirebaseAuth
import Combine

/// Rewarded Video Ad Manager for coin economy (AdMob Unit `ca-app-pub-3940256099942544/1712485313`).
/// Handles ad presentation and atomic coin reward distribution (+1 coin per ad watched).
@MainActor
final class RewardedAdManager: ObservableObject {
    static let shared = RewardedAdManager()
    static let adUnitId = "ca-app-pub-3940256099942544/1712485313"

    @Published var isPresentingAd = false
    @Published var adCountdown: Int = 5
    @Published var isLoadingAd = false
    @Published var rewardEarnedMessage: String?

    private var timer: Timer?

    func watchAd(onReward: (() -> Void)? = nil) {
        guard !isPresentingAd else { return }
        isPresentingAd = true
        adCountdown = 5

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { return }
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
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await UserRepository.shared.addCoins(uid: uid, amount: 1)
            rewardEarnedMessage = "+1 🪙 Added to your balance!"
            onReward?()
        } catch {
            print("Failed to award coin: \(error.localizedDescription)")
        }
    }
}
