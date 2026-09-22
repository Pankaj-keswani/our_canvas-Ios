import SwiftUI
import FirebaseAuth

/// Bottom sheet for gifting coins to another user's drawing.
/// Tip amounts: 1 🪙 "Nice!", 2 🪙 "Awesome!", 5 🪙 "Masterpiece!"
/// Uses the Cloudflare Worker for the atomic deduct+credit — never writes another user's doc directly.
struct CoinTipSheet: View {
    let drawing: Drawing
    let group: Group
    let recipientName: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userRepo = UserRepository.shared

    @State private var selectedAmount: Int = 1
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false

    private var currentCoins: Int {
        userRepo.currentUserProfile?.coins ?? 0
    }

    private var hasSufficientCoins: Bool {
        currentCoins >= selectedAmount
    }

    private let tipOptions: [(amount: Int, label: String, emoji: String)] = [
        (1, "Nice!", "😊"),
        (2, "Awesome!", "🤩"),
        (5, "Masterpiece!", "🎨"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Recipient heading
                VStack(spacing: 6) {
                    Text("Gift Coins to \(recipientName) 🎁")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("🪙 \(currentCoins) Coins available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // Amount chips
                HStack(spacing: 12) {
                    ForEach(tipOptions, id: \.amount) { option in
                        Button {
                            selectedAmount = option.amount
                        } label: {
                            VStack(spacing: 6) {
                                Text(option.emoji)
                                    .font(.title2)
                                Text("\(option.amount) 🪙")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(selectedAmount == option.amount ? .black : .primary)
                                Text(option.label)
                                    .font(.caption2)
                                    .foregroundColor(selectedAmount == option.amount ? .black.opacity(0.7) : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selectedAmount == option.amount
                                          ? Color.yellow.opacity(0.85)
                                          : Color(.secondarySystemGroupedBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(selectedAmount == option.amount
                                                          ? Color.yellow : Color.clear,
                                                          lineWidth: 2)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(option.amount > currentCoins)
                        .opacity(option.amount > currentCoins ? 0.4 : 1.0)
                    }
                }
                .padding(.horizontal)

                // Insufficient coins warning
                if !hasSufficientCoins {
                    Label("Not enough coins — watch an ad to earn more!", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Success
                if didSend {
                    Label("Tip sent! 🎉", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        sendTip()
                    } label: {
                        Group {
                            if isSending {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Send \(selectedAmount) 🪙")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(BrandGradient.primary))
                        .foregroundColor(.black)
                    }
                    .disabled(!hasSufficientCoins || isSending || didSend)
                    .opacity(hasSufficientCoins && !isSending && !didSend ? 1.0 : 0.5)

                    Button("Cancel") { dismiss() }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("Gift Coins 🎁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func sendTip() {
        guard hasSufficientCoins, !isSending, !didSend else { return }
        guard let senderId = Auth.auth().currentUser?.uid else { return }
        let senderName = userRepo.currentUserProfile?.displayName ?? "Someone"

        isSending = true
        errorMessage = nil

        Task {
            do {
                try await CoinManager.shared.sendCoinTip(
                    senderId: senderId,
                    recipientId: drawing.senderId,
                    amount: selectedAmount,
                    drawingId: drawing.drawingId,
                    groupId: group.groupId,
                    groupName: group.groupName,
                    senderName: senderName
                )
                await MainActor.run {
                    isSending = false
                    didSend = true
                }
                // Auto-close after showing success.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isSending = false
                    let appErr = AppError.from(error)
                    errorMessage = appErr.message
                }
            }
        }
    }
}
