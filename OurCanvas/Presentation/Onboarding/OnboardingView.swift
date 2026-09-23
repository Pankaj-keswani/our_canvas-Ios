import SwiftUI
import FirebaseAuth

/// Interactive 3-slide onboarding experience matching Android commit 0654258.
/// Introduces live lockscreen & widget sync, creative freedom with brush preview and stroke replay,
/// and an embedded live touch drawing pad.
struct OnboardingView: View {
    @EnvironmentObject private var router: AppRouter
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false

    // MARK: - Legacy Page struct & array preserved for Phase 3 unit test parity
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
        Page(eyebrow: "Welcome to Our Canvas", headline: "Draw a little love", cta: "Show me more", doodle: .heart, backgroundEmojis: ["❤️", "💕", "💖", "✨"]),
        Page(eyebrow: "Every doodle counts", headline: "Sketch your way to streaks", cta: "That's cute", doodle: .star, backgroundEmojis: ["⭐️", "🌟", "✨", "💫"]),
        Page(eyebrow: "Together is better", headline: "Play, guess & co-draw", cta: "I'm in", doodle: .rainbow, backgroundEmojis: ["🌈", "🎨", "🖌️", "☁️"]),
        Page(eyebrow: "Ready when you are", headline: "Your canvas awaits", cta: "Start drawing", doodle: .smiley, backgroundEmojis: ["😊", "🎨", "🎉", "✏️"]),
    ]

    // MARK: - Interactive State
    @State private var currentPage = 0

    // Slide 1 State
    @State private var slide1Progress: CGFloat = 0
    @State private var showNotificationBanner = false

    // Slide 2 State
    enum BrushChoice: String, CaseIterable, Identifiable {
        case neon = "Neon Glow"
        case fire = "Fire Spark"
        case rainbow = "Rainbow"
        case pastel = "Pastel Soft"
        var id: String { rawValue }
    }
    @State private var selectedBrush: BrushChoice = .neon
    @State private var slide2Progress: CGFloat = 1.0

    // Slide 3 State
    struct DrawStroke: Identifiable {
        let id = UUID()
        var points: [CGPoint]
        let color: Color
    }
    @State private var strokes: [DrawStroke] = []
    @State private var activeStroke: DrawStroke? = nil
    @State private var selectedColorIndex = 0
    private let miniPadColors: [Color] = [
        Color(hex: 0x3BD8D2), // Neon Cyan
        Color(hex: 0xF43F5E), // Rose Pink
        Color(hex: 0xFBBF24), // Amber Sun
        Color(hex: 0xA855F7), // Purple
        Color.white           // White
    ]

    var body: some View {
        ZStack {
            // Deep obsidian / navy gradient background (#0D111E to #13192B)
            LinearGradient(
                colors: [Color(hex: 0x0D111E), Color(hex: 0x13192B)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Subtle floating particles
            FloatingParticlesView()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // 3 Slides TabView
                TabView(selection: $currentPage) {
                    slide1View
                        .tag(0)

                    slide2View
                        .tag(1)

                    slide3View
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            animateSlide1()
        }
        .onChange(of: currentPage) { newPage in
            if newPage == 0 {
                animateSlide1()
            } else if newPage == 1 {
                animateSlide2()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // "Step X of 3" chip
            Text("Step \(currentPage + 1) of 3")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(BrandColor.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(BrandColor.primary.opacity(0.16)))

            Spacer()

            if currentPage < 2 {
                Button("Skip") {
                    complete()
                }
                .font(BrandFont.caption())
                .foregroundColor(BrandColor.textSecondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Slide 1: Live Lockscreen & Widget Sync

    private var slide1View: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            // iPhone Lockscreen & Widget Mockup
            VStack(spacing: 12) {
                // Mock iPhone Bezel
                VStack(spacing: 8) {
                    // Clock
                    Text("9:41")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 12)

                    // Widget Card
                    VStack(spacing: 6) {
                        HStack {
                            Text("Our Canvas")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            HStack(spacing: 4) {
                                Text("Synced to Widget")
                                    .font(.system(size: 9, weight: .semibold))
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                            }
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.35)))
                        }

                        // Heart Doodle inside Widget
                        ZStack {
                            HeartDoodle()
                                .trim(from: 0, to: slide1Progress)
                                .stroke(
                                    LinearGradient(colors: [Color(hex: 0xF43F5E), Color(hex: 0xFB7185)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                                )
                                .shadow(color: Color(hex: 0xF43F5E).opacity(0.6), radius: 6)
                                .frame(width: 80, height: 65)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 75)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: 0x1A2238).opacity(0.9))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    )
                    .padding(.horizontal, 16)

                    // Animated Notification Banner
                    if showNotificationBanner {
                        HStack(spacing: 8) {
                            Text("💌")
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Sarah just drew you a doodle!")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Tap to view live on your lock screen")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.6))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                        )
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(width: 250, height: 260)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.black.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
                )
                .shadow(color: BrandColor.primary.opacity(0.2), radius: 16, x: 0, y: 8)
            }

            Spacer(minLength: 8)

            // Text section
            VStack(spacing: 6) {
                Text("LIVE LOCKSCREEN & WIDGET SYNC")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(BrandColor.primary)
                    .tracking(1.4)

                Text("Draw it here, it appears there.")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandGradient.primary)
                    .multilineTextAlignment(.center)

                Text("Draw together with your partner or best friend. When you send a doodle, it lights up on their widget instantly.")
                    .font(.system(size: 13))
                    .foregroundColor(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer(minLength: 12)

            PrimaryGradientButton(title: "Continue") {
                withAnimation { currentPage = 1 }
            }
            .padding(.horizontal, 24)
        }
    }

    private func animateSlide1() {
        slide1Progress = 0
        showNotificationBanner = false
        withAnimation(.easeInOut(duration: 1.8)) {
            slide1Progress = 1.0
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(1.2)) {
            showNotificationBanner = true
        }
    }

    // MARK: - Slide 2: Creative Freedom & Stroke Replay

    private var slide2View: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                Spacer(minLength: 4)

                // Preview Canvas Card
                VStack(spacing: 10) {
                    // 2x2 Grid of Brush Chips (equal width)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            brushChip(for: .neon, title: "✨ Neon Glow")
                            brushChip(for: .fire, title: "🔥 Fire Spark")
                        }
                        HStack(spacing: 8) {
                            brushChip(for: .rainbow, title: "🌈 Rainbow")
                            brushChip(for: .pastel, title: "🌸 Pastel Soft")
                        }
                    }
                    .padding(.horizontal, 20)

                    // Rendered Canvas Preview (scaled to ~170pt height)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: 0x11162B))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))

                        brushPreviewDoodle(for: selectedBrush, progress: slide2Progress)

                        // "▶ Replay Stroke" button
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button {
                                    animateSlide2()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 10))
                                        Text("Replay Stroke")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white.opacity(0.18)))
                                    .foregroundColor(.white)
                                }
                                .padding(8)
                            }
                        }
                    }
                    .frame(width: 270, height: 170)
                }

                Spacer(minLength: 6)

                // Text section
                VStack(spacing: 6) {
                    Text("CREATIVE FREEDOM")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(BrandColor.secondary)
                        .tracking(1.4)

                    Text("Magical brushes & Stroke Replay.")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandGradient.primary)
                        .multilineTextAlignment(.center)

                    Text("Unleash your creativity with Neon, Fire, Rainbow and Pastel brushes. Watch your favorite memories re-draw stroke by stroke.")
                        .font(.system(size: 13))
                        .foregroundColor(BrandColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Spacer(minLength: 10)

                PrimaryGradientButton(title: "Try Drawing") {
                    withAnimation { currentPage = 2 }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private func brushChip(for brush: BrushChoice, title: String) -> some View {
        Button {
            selectedBrush = brush
            animateSlide2()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selectedBrush == brush ? BrandColor.primary : Color.white.opacity(0.08))
                .foregroundColor(selectedBrush == brush ? .black : .white)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func animateSlide2() {
        slide2Progress = 0
        withAnimation(.easeInOut(duration: 1.4)) {
            slide2Progress = 1.0
        }
    }

    @ViewBuilder
    private func brushPreviewDoodle(for brush: BrushChoice, progress: CGFloat) -> some View {
        switch brush {
        case .neon:
            RainbowDoodle()
                .trim(from: 0, to: progress)
                .stroke(Color(hex: 0x3BD8D2), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .shadow(color: Color(hex: 0x3BD8D2).opacity(0.8), radius: 8)
                .frame(width: 115, height: 75)

        case .fire:
            HeartDoodle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [Color.orange, Color.red], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .shadow(color: Color.orange.opacity(0.8), radius: 8)
                .frame(width: 100, height: 80)

        case .rainbow:
            StarDoodle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [.red, .yellow, .green, .cyan, .purple], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 105, height: 105)

        case .pastel:
            HeartDoodle()
                .trim(from: 0, to: progress)
                .stroke(Color(hex: 0xC4B5FD), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .shadow(color: Color(hex: 0xF1EBFD).opacity(0.6), radius: 5)
                .frame(width: 100, height: 80)
        }
    }

    // MARK: - Slide 3: Your Turn (Live Mini-Canvas)

    private var slide3View: some View {
        VStack(spacing: 12) {
            // Text Header
            VStack(spacing: 4) {
                Text("YOUR TURN")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(BrandColor.primary)
                    .tracking(1.4)

                Text("Touch & draw right now!")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandGradient.primary)

                Text("Experience our silky stroke engine before you start.")
                    .font(.system(size: 13))
                    .foregroundColor(BrandColor.textSecondary)
            }
            .padding(.top, 4)

            // Live Interactive Mini-Canvas
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(hex: 0x10162B))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(
                                    LinearGradient(colors: [BrandColor.primary.opacity(0.4), BrandColor.secondary.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1.5
                                )
                        )

                    // Render lines
                    Canvas { context, _ in
                        for stroke in strokes {
                            drawStroke(stroke, in: &context)
                        }
                        if let active = activeStroke {
                            drawStroke(active, in: &context)
                        }
                    }

                    // Empty prompt or Instant feedback badge
                    if strokes.isEmpty && activeStroke == nil {
                        VStack(spacing: 6) {
                            Image(systemName: "hand.draw.fill")
                                .font(.system(size: 26))
                                .foregroundColor(BrandColor.primary.opacity(0.6))
                            Text("Draw with your finger ✨")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    } else {
                        VStack {
                            HStack {
                                Text("Awesome! ✨")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(BrandColor.primary))
                                    .shadow(color: BrandColor.primary.opacity(0.4), radius: 4)
                                    .padding(10)
                                Spacer()
                                Button("Clear") {
                                    strokes.removeAll()
                                    activeStroke = nil
                                }
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                                .padding(10)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(height: 220)
                .padding(.horizontal, 16)
                // Touch Interception via DragGesture so drawing doesn't trigger TabView horizontal page swiping
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if activeStroke == nil {
                                activeStroke = DrawStroke(points: [value.location], color: miniPadColors[selectedColorIndex])
                            } else {
                                activeStroke?.points.append(value.location)
                            }
                        }
                        .onEnded { value in
                            if var current = activeStroke {
                                current.points.append(value.location)
                                strokes.append(current)
                                activeStroke = nil
                            }
                        }
                )

                // Color Palette
                HStack(spacing: 14) {
                    ForEach(0..<miniPadColors.count, id: \.self) { index in
                        Button {
                            selectedColorIndex = index
                        } label: {
                            Circle()
                                .fill(miniPadColors[index])
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedColorIndex == index ? 2.5 : 0)
                                )
                                .shadow(color: miniPadColors[index].opacity(selectedColorIndex == index ? 0.6 : 0), radius: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 8)

            // Primary Start button
            PrimaryGradientButton(title: "Start Our Canvas ✨") {
                complete()
            }
            .padding(.horizontal, 24)
        }
    }

    private func drawStroke(_ stroke: DrawStroke, in context: inout GraphicsContext) {
        guard stroke.points.count >= 2 else { return }
        var path = Path()
        path.move(to: stroke.points[0])
        for pt in stroke.points.dropFirst() {
            path.addLine(to: pt)
        }

        // Glow pass
        context.stroke(
            path,
            with: .color(stroke.color.opacity(0.5)),
            style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
        )
        // Core pass
        context.stroke(
            path,
            with: .color(stroke.color),
            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        )
    }

    // MARK: - Bottom Bar (Indicators)

    private var bottomBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? BrandColor.primary : Color.white.opacity(0.2))
                    .frame(width: index == currentPage ? 24 : 8, height: 7)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Completion

    private func complete() {
        if let uid = router.currentUID ?? Auth.auth().currentUser?.uid {
            var store = UserScopedStore(uid: uid)
            store.postOnboardingCreate = true
            store.onboardingCompleted = true
        }
        isOnboardingCompleted = true
        UserDefaults.standard.set(true, forKey: "isOnboardingCompleted")
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        router.completeOnboarding()
    }
}

// MARK: - Floating Particles Background

struct FloatingParticlesView: View {
    @State private var animate = false

    private let particles: [(CGFloat, CGFloat, CGFloat, Color)] = [
        (0.12, 0.18, 4, Color(hex: 0x3BD8D2)),
        (0.85, 0.22, 6, Color(hex: 0xAB5EFA)),
        (0.25, 0.70, 5, Color(hex: 0xFBBF24)),
        (0.78, 0.65, 4, Color(hex: 0xF43F5E)),
        (0.48, 0.12, 3, Color.white),
        (0.90, 0.88, 5, Color(hex: 0x3BD8D2)),
        (0.15, 0.90, 4, Color(hex: 0xAB5EFA)),
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<particles.count, id: \.self) { i in
                let (xFrac, yFrac, size, color) = particles[i]
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: size, height: size)
                    .position(
                        x: proxy.size.width * xFrac,
                        y: proxy.size.height * yFrac + (animate ? 10 : -10)
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Shapes for Onboarding Doodles

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
            path.addPath(arc.strokedPath(StrokeStyle(lineWidth: 6, lineCap: .round)))
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

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(AppRouter())
    }
}
