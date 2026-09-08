import SwiftUI
import FirebaseAuth

/// Android-compatible onboarding redesign (A11): exactly 4 pages, each with a
/// self-drawing animated doodle (trim-reveal + glow/aura), drifting emoji
/// background, eyebrow label, gradient-accent headline, page counter chip,
/// Skip, animated progress dots and per-page gradient CTAs.
struct OnboardingView: View {
    @EnvironmentObject private var router: AppRouter

    struct Page: Identifiable {
        let eyebrow: String
        let headline: String
        let cta: String
        let doodle: DoodleKind
        let backgroundEmojis: [String]
        var id: String { headline }
    }

    enum DoodleKind: String, CaseIterable {
        case heart, star, rainbow, smiley
    }

    static let pages: [Page] = [
        Page(eyebrow: "Welcome to Our Canvas",
             headline: "Draw a little love",
             cta: "Show me more",
             doodle: .heart,
             backgroundEmojis: ["❤️", "💕", "💖", "✨"]),
        Page(eyebrow: "Every doodle counts",
             headline: "Sketch your way to streaks",
             cta: "That's cute",
             doodle: .star,
             backgroundEmojis: ["⭐️", "🌟", "✨", "💫"]),
        Page(eyebrow: "Together is better",
             headline: "Play, guess & co-draw",
             cta: "I'm in",
             doodle: .rainbow,
             backgroundEmojis: ["🌈", "🎨", "🖌️", "☁️"]),
        Page(eyebrow: "Ready when you are",
             headline: "Your canvas awaits",
             cta: "Start drawing",
             doodle: .smiley,
             backgroundEmojis: ["😊", "🎨", "🎉", "✏️"]),
    ]

    @State private var currentPage = 0
    @State private var revealProgress: CGFloat = 0
    @State private var driftPhase: CGFloat = 0

    var body: some View {
        ZStack {
            DriftingEmojiBackground(emojis: OnboardingView.pages[currentPage].backgroundEmojis,
                                    phase: driftPhase)

            VStack(spacing: 0) {
                Spacer()

                SelfDrawingDoodle(kind: OnboardingView.pages[currentPage].doodle,
                                  progress: revealProgress)
                    .frame(height: 240)

                Spacer()

                VStack(spacing: 10) {
                    Text(OnboardingView.pages[currentPage].eyebrow)
                        .font(BrandFont.caption())
                        .textCase(.uppercase)
                        .foregroundColor(BrandColor.primary)
                        .tracking(1.5)

                    Text(OnboardingView.pages[currentPage].headline)
                        .font(BrandFont.title())
                        .foregroundStyle(BrandGradient.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 28)

                HStack(spacing: 8) {
                    ForEach(0..<OnboardingView.pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? BrandColor.primary : Color.white.opacity(0.25))
                            .frame(width: index == currentPage ? 26 : 8, height: 8)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
                    }
                }

                Spacer().frame(height: 24)

                PrimaryGradientButton(title: OnboardingView.pages[currentPage].cta) {
                    advance()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                if currentPage < OnboardingView.pages.count - 1 {
                    Button("Skip") { complete() }
                        .font(BrandFont.caption())
                        .foregroundColor(BrandColor.textSecondary)
                        .padding(.bottom, 24)
                } else {
                    Spacer().frame(height: 24)
                }
            }

            // Page counter chip.
            VStack {
                HStack {
                    Spacer()
                    Text("\(currentPage + 1) / \(OnboardingView.pages.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(BrandColor.surface.opacity(0.8)))
                        .foregroundColor(BrandColor.textPrimary)
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                }
                Spacer()
            }
        }
        .background(BrandBackground())
        .onAppear { startAnimations() }
        .onChange(of: currentPage) { _ in restartReveal() }
    }

    private func startAnimations() {
        restartReveal()
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: true)) {
            driftPhase = 1
        }
    }

    private func restartReveal() {
        revealProgress = 0
        withAnimation(.easeInOut(duration: 2.2)) {
            revealProgress = 1
        }
    }

    private func advance() {
        if currentPage >= OnboardingView.pages.count - 1 {
            complete()
        } else {
            currentPage += 1
        }
    }

    /// Completion: user-scoped storage marks onboarding done (version maintained by
    /// the router) and `action_create` drops the user into the create flow.
    private func complete() {
        if let uid = router.currentUID ?? Auth.auth().currentUser?.uid {
            var store = UserScopedStore(uid: uid)
            store.postOnboardingCreate = true
        }
        router.completeOnboarding()
    }
}

// MARK: - Self-drawing doodle (trim reveal + glow/aura)

struct SelfDrawingDoodle: View {
    let kind: OnboardingView.DoodleKind
    let progress: CGFloat

    var body: some View {
        ZStack {
            // Aura pass.
            doodleShape
                .stroke(BrandColor.primary.opacity(0.18), lineWidth: 26)
                .blur(radius: 14)
                .trim(from: 0, to: progress)

            // Neon glow pass.
            doodleShape
                .stroke(BrandColor.primary.opacity(0.5), lineWidth: 12)
                .blur(radius: 5)
                .trim(from: 0, to: progress)

            // Core stroke.
            doodleShape
                .stroke(style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .foregroundStyle(BrandGradient.primary)
                .trim(from: 0, to: progress)
        }
        .padding(28)
    }

    @ViewBuilder
    private var doodleShape: some Shape {
        switch kind {
        case .heart: HeartDoodle()
        case .star: StarDoodle()
        case .rainbow: RainbowDoodle()
        case .smiley: SmileyDoodle()
        }
    }
}

struct HeartDoodle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w / 2, y: h * 0.88))
        path.addCurve(to: CGPoint(x: w * 0.08, y: h * 0.34),
                      control1: CGPoint(x: w * 0.02, y: h * 0.66),
                      control2: CGPoint(x: w * 0.08, y: h * 0.18))
        path.addArc(center: CGPoint(x: w * 0.30, y: h * 0.26),
                    radius: w * 0.22,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: false)
        path.addArc(center: CGPoint(x: w * 0.70, y: h * 0.26),
                    radius: w * 0.22,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: false)
        path.addCurve(to: CGPoint(x: w / 2, y: h * 0.88),
                      control1: CGPoint(x: w * 0.92, y: h * 0.18),
                      control2: CGPoint(x: w * 0.98, y: h * 0.66))
        return path
    }
}

struct StarDoodle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.42
        for index in 0..<10 {
            let angle = .pi / 2 + CGFloat(index) * .pi / 5
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + cos(angle) * radius,
                                y: center.y - sin(angle) * radius)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct RainbowDoodle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radii: [CGFloat] = [0.44, 0.35, 0.26]
        for (index, radiusFactor) in radii.enumerated() {
            let radius = min(rect.width, rect.height) / 2 * radiusFactor
            let centerY = rect.height * 0.82
            var arc = Path()
            arc.addArc(center: CGPoint(x: rect.midX, y: centerY),
                       radius: radius,
                       startAngle: .degrees(180),
                       endAngle: .degrees(0),
                       clockwise: false)
            path.addPath(arc.strokedPath(StrokeStyle(lineWidth: 8, lineCap: .round)))
            _ = index
        }
        return path
    }
}

struct SmileyDoodle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2 * 0.82
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        return path
    }
}

// MARK: - Drifting emoji background

struct DriftingEmojiBackground: View {
    let emojis: [String]
    let phase: CGFloat

    private let layout: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.12, 44), (0.85, 0.08, 36), (0.16, 0.74, 38), (0.9, 0.68, 46),
        (0.45, 0.05, 30), (0.7, 0.9, 34), (0.05, 0.45, 28), (0.55, 0.88, 26),
    ]

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(layout.enumerated()), id: \.offset) { index, item in
                Text(emojis[index % emojis.count])
                    .font(.system(size: item.2))
                    .opacity(0.16)
                    .position(x: geometry.size.width * item.0,
                              y: geometry.size.height * item.1 + phase * 24 * CGFloat(index.isMultiple(of: 2) ? 1 : -1))
            }
        }
        .allowsHitTesting(false)
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(AppRouter())
    }
}
