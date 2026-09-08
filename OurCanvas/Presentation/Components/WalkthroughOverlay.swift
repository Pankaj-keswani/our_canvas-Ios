import SwiftUI
import FirebaseAuth

/// First-run walkthrough (Android A2.3). Steps persisted in user-scoped storage;
/// notification step uses the updated "Fresh & New" copy. The overlay is a centered
/// spotlight card over a dimmed background — size-safe on every iPhone.
struct WalkthroughOverlay: View {
    @Binding var isPresented: Bool

    struct Step: Identifiable {
        let title: String
        let message: String
        let icon: String
        var id: String { title }
    }

    static let steps: [Step] = [
        Step(title: "Home", message: "Your streaks, circles and fresh doodles — all in one cozy place.", icon: "house.fill"),
        Step(title: "Circles", message: "Create circles and invite your favorite people with a single tap.", icon: "person.2.fill"),
        Step(title: "Create", message: "The big + in the middle starts a brand-new doodle anytime.", icon: "plus.circle.fill"),
        Step(title: "What's New", message: "Fresh & New — catch every update and feature right here.", icon: "sparkles"),
        Step(title: "Profile", message: "Your stats, privacy controls and Lifetime Pro live here.", icon: "person.crop.circle.fill"),
    ]

    static var totalSteps: Int { steps.count }

    @State private var currentIndex = 0

    private var store: UserScopedStore? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return UserScopedStore(uid: uid)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { advance() }

            VStack(spacing: 18) {
                Image(systemName: WalkthroughOverlay.steps[currentIndex].icon)
                    .font(.system(size: 44))
                    .foregroundStyle(BrandGradient.primary)

                Text(WalkthroughOverlay.steps[currentIndex].title)
                    .font(BrandFont.title())
                    .foregroundColor(BrandColor.textPrimary)

                Text(WalkthroughOverlay.steps[currentIndex].message)
                    .font(BrandFont.body())
                    .foregroundColor(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    ForEach(0..<WalkthroughOverlay.steps.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentIndex ? BrandColor.primary : Color.white.opacity(0.25))
                            .frame(width: index == currentIndex ? 22 : 8, height: 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
                    }
                }

                HStack(spacing: 12) {
                    Button("Skip") { finish() }
                        .font(BrandFont.caption())
                        .foregroundColor(BrandColor.textSecondary)

                    PrimaryGradientButton(title: currentIndex == WalkthroughOverlay.steps.count - 1 ? "Got it!" : "Next") {
                        advance()
                    }
                    .frame(maxWidth: 180)
                }
            }
            .padding(28)
            .background(BrandColor.surface.opacity(0.98))
            .cornerRadius(24)
            .padding(.horizontal, 32)
        }
        .onAppear {
            // Resume where the user left off.
            currentIndex = min(store?.walkthroughStep ?? 0, WalkthroughOverlay.steps.count - 1)
        }
    }

    private func advance() {
        store?.walkthroughStep = currentIndex + 1
        if currentIndex >= WalkthroughOverlay.steps.count - 1 {
            finish()
        } else {
            currentIndex += 1
        }
    }

    private func finish() {
        store?.walkthroughStep = WalkthroughOverlay.steps.count
        isPresented = false
    }
}
