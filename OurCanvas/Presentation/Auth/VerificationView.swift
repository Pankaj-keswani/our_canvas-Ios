import SwiftUI
import Combine

struct VerificationView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var isChecking = false
    @State private var infoText: String?
    @State private var resendCooldown = 0

    private let cooldownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.open.fill")
                .font(.system(size: 56))
                .foregroundStyle(BrandGradient.primary)

            Text("Check your inbox")
                .font(BrandFont.title())
                .foregroundColor(BrandColor.textPrimary)

            Text(verificationCopy)
                .font(BrandFont.body())
                .foregroundColor(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if let infoText {
                Text(infoText)
                    .font(BrandFont.caption())
                    .foregroundColor(BrandColor.warning)
                    .multilineTextAlignment(.center)
            }

            PrimaryGradientButton(title: "I've Verified — Continue", isLoading: isChecking) {
                checkAgain()
            }
            .padding(.horizontal, 24)

            Button(resendCooldown > 0 ? "Resend email (\(resendCooldown)s)" : "Resend verification email") {
                resend()
            }
            .font(BrandFont.caption())
            .foregroundColor(resendCooldown > 0 ? BrandColor.textSecondary : BrandColor.primary)
            .disabled(resendCooldown > 0)

            Button("Use a different account") {
                router.signOut()
            }
            .font(BrandFont.caption())
            .foregroundColor(BrandColor.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 24)
        .onReceive(cooldownTimer) { _ in
            if resendCooldown > 0 {
                resendCooldown -= 1
            }
        }
    }

    private var verificationCopy: String {
        let email = router.currentEmail ?? "your email address"
        return "We sent a verification link to \(email). Tap it to activate your account — and don't forget to check your spam folder."
    }

    private func checkAgain() {
        isChecking = true
        Task {
            try? await AuthService.reloadCurrentUser()
            await MainActor.run {
                isChecking = false
                router.refreshSession()
            }
        }
    }

    private func resend() {
        infoText = nil
        resendCooldown = 60
        Task {
            do {
                try await AuthService.resendVerificationEmail()
            } catch {
                await MainActor.run {
                    infoText = AuthService.map(error).message
                    resendCooldown = 0
                }
            }
        }
    }
}

struct VerificationView_Previews: PreviewProvider {
    static var previews: some View {
        VerificationView()
            .environmentObject(AppRouter())
    }
}
