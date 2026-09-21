import SwiftUI
import FirebaseAuth

/// Home screen banner notifying users of eligible streak recovery and providing one-tap recovery.
struct StreakRecoveryBanner: View {
    let user: User
    var onOpenWallet: () -> Void

    @State private var isRecovering = false
    @State private var recoverySuccessMessage: String?
    @State private var errorMessage: String?

    private var info: StreakRecoveryInfo {
        StreakManager.getStreakRecoveryInfo(user: user)
    }

    var body: some View {
        if let msg = recoverySuccessMessage {
            HStack(spacing: 10) {
                Text("🎉")
                    .font(.title2)
                Text(msg)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.green.opacity(0.4), lineWidth: 1.5)
                    )
            )
            .padding(.horizontal)
            .transition(.scale.combined(with: .opacity))
        } else if info.isEligible {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("🔥")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Streak at Risk! Restore your \(info.streakToRecover)-day streak")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)
                        Text("Missed drawing on \(info.missedDate). Recover it now with Coins so you don't lose your streak!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Spacer()
                    if user.coins >= info.costCoins {
                        Button {
                            performRecovery()
                        } label: {
                            HStack(spacing: 6) {
                                if isRecovering {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Image(systemName: "arrow.counterclockwise.circle.fill")
                                }
                                Text("Recover (\(info.costCoins) 🪙)")
                                    .font(.subheadline.weight(.bold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(BrandGradient.primary))
                            .foregroundColor(.black)
                        }
                        .disabled(isRecovering)
                    } else {
                        Button {
                            onOpenWallet()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.rectangle.fill")
                                Text("Get \(info.costCoins) 🪙 (Watch Ad 🎬)")
                                    .font(.subheadline.weight(.bold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.orange))
                            .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.orange.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1.5)
                    )
            )
            .padding(.horizontal)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func performRecovery() {
        guard let uid = Auth.auth().currentUser?.uid, !isRecovering else { return }
        isRecovering = true
        errorMessage = nil

        Task {
            do {
                let result = try await StreakManager.shared.recoverStreak(uid: uid)
                await MainActor.run {
                    isRecovering = false
                    if result.success {
                        withAnimation {
                            recoverySuccessMessage = "🎉 \(result.newStreak)-day streak restored!"
                        }
                    } else {
                        errorMessage = "Could not recover streak. Please check your coin balance."
                    }
                }
            } catch {
                await MainActor.run {
                    isRecovering = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
