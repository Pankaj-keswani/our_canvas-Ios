import SwiftUI

/// Minimal Phase 0 onboarding gate. The 4-page self-drawing-doodle redesign
/// (Android spec A11) lands in the Onboarding phase — this exists so the router's
/// `needsOnboarding` state has a destination and completion is recorded locally +
/// in Firestore (`onboardingVersion`).
struct OnboardingView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 64))
                .foregroundStyle(BrandGradient.primary)

            Text("Welcome to Our Canvas")
                .font(BrandFont.title())
                .foregroundColor(BrandColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Draw, guess and doodle together with your favorite people — one sketch at a time.")
                .font(BrandFont.body())
                .foregroundColor(BrandColor.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            PrimaryGradientButton(title: "Start Drawing") {
                router.completeOnboarding()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 24)
        .background(BrandBackground())
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(AppRouter())
    }
}
