import SwiftUI
import FirebaseAuth

/// Subscription / upgrade screen (Android A7.1): comparison table, limited-time
/// offer presentation, live StoreKit price, Restore Purchases, Pro member card and
/// promo-code redemption. No fake purchase success — the grant state is honest.
struct SubscriptionView: View {
    @StateObject private var store = StoreManager()
    @StateObject private var profileModel = ProfileViewModel()

    @State private var promoCode = ""
    @State private var promoMessage: String?
    @State private var isRedeeming = false

    private var isPro: Bool {
        UserRepository.shared.currentUserProfile?.isPro ?? false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isPro {
                    proMemberCard
                } else {
                    offerCard
                    purchaseSection
                }
                comparisonTable
                promoSection
                proStatusCard
            }
            .padding()
        }
        .background(BrandBackground())
        .navigationTitle("Lifetime Pro")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Limited-time offer

    private var offerCard: some View {
        VStack(spacing: 8) {
            Text("💎")
                .font(.system(size: 40))
            Text("LIMITED TIME OFFER")
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundColor(BrandColor.warning)
            Text("₹299 → ₹99")
                .font(BrandFont.rounded(34, .black))
                .foregroundStyle(BrandGradient.premium)
            Text("One payment. Pro forever.")
                .font(.subheadline)
                .foregroundColor(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(BrandGradient.premium.opacity(0.12))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .strokeBorder(BrandColor.warning.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            switch store.productState {
            case .loading:
                ProgressView("Loading from the App Store…")
                    .foregroundColor(BrandColor.textSecondary)
            case .unavailable:
                Text("Product loading from the App Store. Try again in a moment.")
                    .font(.caption)
                    .foregroundColor(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await store.loadProducts() }
                }
                .font(.caption)
                .foregroundColor(BrandColor.primary)
            case .loaded(let price):
                PrimaryGradientButton(title: store.isPurchasing ? "Purchasing…" : "Unlock Lifetime Pro · \(price)") {
                    Task { await store.purchase() }
                }
                .disabled(store.isPurchasing)
            }

            Button("Restore Purchases") {
                Task { await store.restore() }
            }
            .font(.caption)
            .foregroundColor(BrandColor.primary)

            grantStateText
        }
        .padding(16)
        .background(BrandColor.surface.opacity(0.6))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var grantStateText: some View {
        switch store.grantState {
        case .granted:
            Label("Lifetime Pro activated. Thank you! 💎", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .pendingServerActivation:
            Text("Your purchase is verified on your Apple ID and will activate automatically once the server completes activation. Nothing was lost — Restoring retries it anytime.")
                .font(.caption)
                .foregroundColor(BrandColor.warning)
                .multilineTextAlignment(.center)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Comparison table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            tableRow(feature: "Active circles", free: "Max 2", pro: "Unlimited", first: true)
            Divider().overlay(Color.white.opacity(0.06))
            tableRow(feature: "Recent feed visible", free: "3 doodles", pro: "5 doodles")
            Divider().overlay(Color.white.opacity(0.06))
            tableRow(feature: "Special brushes", free: "None", pro: "Neon · Glow · Rainbow")
            Divider().overlay(Color.white.opacity(0.06))
            tableRow(feature: "Premium colors", free: "None", pro: "Gold + Pastels")
            Divider().overlay(Color.white.opacity(0.06))
            tableRow(feature: "Save to device", free: "—", pro: "✓")
            Divider().overlay(Color.white.opacity(0.06))
            tableRow(feature: "Pro badges", free: "—", pro: "✓")
        }
        .background(BrandColor.surface.opacity(0.6))
        .cornerRadius(16)
    }

    private func tableRow(feature: String, free: String, pro: String, first: Bool = false) -> some View {
        HStack {
            Text(feature)
                .font(.caption)
                .foregroundColor(BrandColor.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("FREE")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(BrandColor.textSecondary)
                Text(free)
                    .font(.caption2)
                    .foregroundColor(BrandColor.textSecondary)
            }
            .frame(width: 90, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text("PRO")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(BrandColor.warning)
                Text(pro)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(BrandColor.textPrimary)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, first ? 14 : 10)
    }

    // MARK: - Pro member card

    private var proMemberCard: some View {
        VStack(spacing: 8) {
            Text("👑")
                .font(.system(size: 36))
            Text("PRO MEMBER")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(BrandColor.warning)
            if let profile = profileModel.currentUserProfile {
                Text("Streak \(profile.currentStreak)🔥 · \(profile.drawingCount) doodles sent")
                    .font(.caption)
                    .foregroundColor(BrandColor.textSecondary)
                Text("Source: \(profile.premiumSource?.uppercased() ?? "PRO")")
                    .font(.caption2)
                    .foregroundColor(BrandColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(BrandGradient.premium.opacity(0.12))
        .cornerRadius(20)
    }

    private var proStatusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.caption)
                .foregroundColor(BrandColor.textSecondary)
            Text(isPro ? "Pro — Lifetime" : "Free plan")
                .font(.headline)
                .foregroundColor(BrandColor.textPrimary)
            Text("Server plan: \(isPro ? "pro" : "free") · StoreKit entitlement: \(store.hasLocalEntitlement ? "verified" : "none")")
                .font(.caption2)
                .foregroundColor(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(BrandColor.surface.opacity(0.6))
        .cornerRadius(16)
    }

    // MARK: - Promo codes

    private var promoSection: some View {
        VStack(spacing: 10) {
            Text("Have a promo code?")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(BrandColor.textPrimary)
            HStack {
                TextField("PROMO CODE", text: $promoCode)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button("Redeem") {
                    redeemPromo()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRedeeming || promoCode.trimmed.isEmpty)
            }
            if isRedeeming {
                ProgressView()
            }
            if let promoMessage {
                Text(promoMessage)
                    .font(.caption)
                    .foregroundColor(promoMessage.contains("🎉") ? .green : .red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(BrandColor.surface.opacity(0.6))
        .cornerRadius(16)
    }

    private func redeemPromo() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isRedeeming = true
        promoMessage = nil
        let code = promoCode
        Task {
            do {
                let outcome = try await PromoCodeService().redeem(code: code, uid: uid)
                if case .success = outcome {
                    _ = try? await UserRepository.shared.getUser(uid: uid, ignoreCache: true)
                }
                let message = Self.message(for: outcome)
                await MainActor.run {
                    isRedeeming = false
                    promoMessage = message
                    if case .success = outcome {
                        promoCode = ""
                    }
                }
            } catch {
                let message = Self.message(for: PromoCodeService.outcome(forErrorDescription: (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String))
                await MainActor.run {
                    isRedeeming = false
                    promoMessage = message
                }
            }
        }
    }

    static func message(for outcome: PromoCodeService.RedemptionOutcome) -> String {
        switch outcome {
        case .success: return "🎉 Promo applied — enjoy Pro!"
        case .alreadyUsed: return "This code has already been redeemed."
        case .expired: return "This code has expired."
        case .alreadyPro: return "You already have Lifetime Pro."
        case .invalidCode: return "That code doesn't look right. Double-check and try again."
        }
    }
}
