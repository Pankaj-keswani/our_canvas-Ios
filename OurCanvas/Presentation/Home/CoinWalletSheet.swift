import SwiftUI
import FirebaseAuth

/// Bottom sheet displaying coin balance, economy details, and rewarded ad trigger.
struct CoinWalletSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userRepo = UserRepository.shared
    @StateObject private var adManager = RewardedAdManager.shared

    var coins: Int {
        userRepo.currentUserProfile?.coins ?? 3
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Coin Balance Card
                        VStack(spacing: 10) {
                            Text("🪙")
                                .font(.system(size: 56))

                            Text("\(coins)")
                                .font(.system(size: 44, weight: .black, design: .rounded))
                                .foregroundColor(.primary)

                            Text("Your Coin Balance")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.yellow.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(Color.yellow.opacity(0.5), lineWidth: 1.5)
                                )
                        )
                        .padding(.horizontal)

                        // Info cards
                        VStack(spacing: 12) {
                            // 7-Day Streak Progress Card
                            streakProgressCard

                            HStack(alignment: .top, spacing: 14) {
                                Text("✨")
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Progressive Letter Hints")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Stuck on a doodle? Spend coins to reveal letters slot by slot.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(14)

                            HStack(alignment: .top, spacing: 14) {
                                Text("🎁")
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Free Welcome Coins")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Every new artist starts with 3 free coins to try hints right away.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(14)
                        }
                        .padding(.horizontal)

                        // Rewarded Ad action
                        VStack(spacing: 12) {
                            if let msg = adManager.rewardEarnedMessage {
                                Text(msg)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }

                            Button {
                                adManager.watchAd()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.rectangle.fill")
                                    Text("Watch Ad (+1 🪙) 🎬")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(BrandGradient.primary))
                                .foregroundColor(.black)
                            }
                            .disabled(adManager.isPresentingAd)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                    }
                    .padding(.vertical)
                }

                if adManager.isPresentingAd {
                    Color.black.opacity(0.85).ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)

                        Text("Sponsored Ad Playing 🎬")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Reward in \(adManager.adCountdown)s…")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(32)
                    .background(Color(.systemGray6).opacity(0.2))
                    .cornerRadius(20)
                }
            }
            .navigationTitle("Coin Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - 7-Day Streak Progress Card

    /// The user's current position in the 7-day cycle (1–7).
    private var currentCycleDay: Int {
        let streak = userRepo.currentUserProfile?.coinLoginStreak ?? 0
        return max(1, min(streak == 0 ? 7 : streak, 7))
    }

    private var streakProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("7-Day Daily Streak 🔥")
                        .font(.subheadline.weight(.bold))
                    Text("Day \(currentCycleDay) of 7")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Day 7 = +5 🪙")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange))
            }

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    streakDayBlock(day: day)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    @ViewBuilder
    private func streakDayBlock(day: Int) -> some View {
        let isCompleted = day < currentCycleDay
        let isToday     = day == currentCycleDay
        let isJackpot   = day == 7

        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCompleted ? Color.green.opacity(0.2)
                          : isToday    ? Color.yellow.opacity(0.3)
                          : Color(.tertiarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isCompleted ? Color.green.opacity(0.5)
                                : isToday    ? Color.yellow
                                : isJackpot  ? Color.orange.opacity(0.6)
                                : Color.clear,
                                lineWidth: isToday ? 2 : 1
                            )
                    )
                    .frame(width: 36, height: 36)

                if isCompleted {
                    Text("✅").font(.caption)
                } else if isJackpot {
                    Text("🎁").font(.caption)
                } else {
                    Text("+1")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isToday ? BrandColor.primary : .secondary)
                }
            }
            Text("D\(day)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isToday ? BrandColor.primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
