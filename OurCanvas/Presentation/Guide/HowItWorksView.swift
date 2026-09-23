import SwiftUI

/// Comprehensive visual guide to widgets, circles, brushes, Co-Draw, Guess My Doodle, streaks, and practice mode.
/// Matches Android commit 3e1c0e0 parity.
struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingPracticeDrawing = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header Banner
                headerBanner
                    .padding(.horizontal)
                    .padding(.top, 8)

                // 7 Visual Cards
                VStack(spacing: 16) {
                    widgetGuideCard
                    circlesGuideCard
                    brushesGuideCard
                    coDrawGuideCard
                    guessGameGuideCard
                    streaksAndCoinsCard
                    practiceCanvasCard
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .background(BrandColor.background.ignoresSafeArea())
        .navigationTitle("How Our Canvas Works")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundColor(BrandColor.primary)
            }
        }
        .fullScreenCover(isPresented: $showingPracticeDrawing) {
            NavigationStack {
                DrawingComposerView(group: .practice)
            }
        }
    }

    // MARK: - Header Banner

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("✨ VISUAL GUIDE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(BrandColor.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BrandColor.primary.opacity(0.15)))

                Spacer()
            }

            Text("Everything You Need to Know")
                .font(.title2.weight(.bold))
                .foregroundColor(BrandColor.textPrimary)

            Text("Our Canvas connects you and your favorite people through live doodles, home screen widgets, fun games, and shared creativity.")
                .font(.subheadline)
                .foregroundColor(BrandColor.textSecondary)
                .lineSpacing(2)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(BrandColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(BrandColor.primary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - 1. Home & Lock Screen Widgets

    private var widgetGuideCard: some View {
        guideCard(
            badge: "WIDGETS",
            icon: "📱",
            title: "Home & Lock Screen Widgets",
            subtitle: "Zero-tap delivery right to your screen"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Whenever a friend in your circle sends a doodle, it updates instantly on your iOS Home or Lock Screen widget — no need to open the app!")
                    .font(.subheadline)
                    .foregroundColor(BrandColor.textSecondary)

                // Mockup visual
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Besties Circle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }

                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.4))
                            HeartDoodle()
                                .trim(from: 0, to: 1.0)
                                .stroke(Color(hex: 0xF43F5E), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 44, height: 38)
                        }
                        .frame(height: 54)

                        HStack {
                            Text("From Sarah")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(BrandColor.primary)
                        }
                    }
                    .padding(10)
                    .frame(width: 140)
                    .background(Color(hex: 0x1A2238))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 6) {
                        featureBullet(title: "Zero-Tap Sync", detail: "Drawings arrive on your widget automatically.")
                        featureBullet(title: "Refresh Button", detail: "Tap 🔄 on the widget to force the latest drawing.")
                    }
                }

                // Instructions Box
                VStack(alignment: .leading, spacing: 4) {
                    Text("💡 How to Add the Widget:")
                        .font(.caption.weight(.bold))
                        .foregroundColor(BrandColor.primary)

                    Text("1. Long press any blank area on your Home Screen\n2. Tap the '+' button in the top corner\n3. Search for 'Our Canvas' and select Small or Medium\n4. Tap 'Add Widget' and pick your circle")
                        .font(.caption2)
                        .foregroundColor(BrandColor.textSecondary)
                        .lineSpacing(2)
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - 2. Circles & Invites

    private var circlesGuideCard: some View {
        guideCard(
            badge: "CIRCLES",
            icon: "⭕",
            title: "Private Circles & Invites",
            subtitle: "Intimate rooms for couples and friends"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Circles are private sketchbooks shared strictly between invited members. Create a circle for your partner, family, or friend group.")
                    .font(.subheadline)
                    .foregroundColor(BrandColor.textSecondary)

                HStack(spacing: 12) {
                    // Invite Code Preview
                    VStack(spacing: 4) {
                        Text("INVITE CODE")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(BrandColor.primary)
                        Text("CANVAS")
                            .font(.system(size: 16, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(6)
                        Text("Share with 1 tap")
                            .font(.system(size: 9))
                            .foregroundColor(BrandColor.textSecondary)
                    }
                    .padding(10)
                    .background(Color(hex: 0x1E293B))
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 6) {
                        featureBullet(title: "6-Letter Codes", detail: "Friends join in seconds using your unique circle code.")
                        featureBullet(title: "Active Presence 🟢", detail: "Green dot shows when a circle member is online.")
                    }
                }
            }
        }
    }

    // MARK: - 3. Magical Brushes & Stroke Replay

    private var brushesGuideCard: some View {
        guideCard(
            badge: "CREATIVITY",
            icon: "🎨",
            title: "Magical Brushes & Replay",
            subtitle: "Bring sketches to life with visual flair"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Our Canvas features custom-rendered brushes engineered to look stunning on both dark and light canvases.")
                    .font(.subheadline)
                    .foregroundColor(BrandColor.textSecondary)

                // 4 Brushes Showcase
                VStack(spacing: 8) {
                    brushRow(icon: "✨", name: "Neon Glow", desc: "Electric glowing halo for vivid night doodles", color: Color(hex: 0x3BD8D2))
                    brushRow(icon: "🔥", name: "Fire Spark", desc: "Warm fiery gradient with glowing ember core", color: Color.orange)
                    brushRow(icon: "🌈", name: "Rainbow", desc: "Spectral multi-color strokes that shift dynamically", color: Color.purple)
                    brushRow(icon: "🌸", name: "Pastel Soft", desc: "Velvety chalk diffusion (unlocked with 3-day streak)", color: Color(hex: 0xC4B5FD))
                }

                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(BrandColor.primary)
                        .font(.system(size: 16))
                    Text("Stroke Replay: Every doodle saves its stroke sequence. Tap Replay to watch drawings redraw stroke-by-stroke!")
                        .font(.caption)
                        .foregroundColor(BrandColor.textSecondary)
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - 4. Live Co-Draw (Beta)

    private var coDrawGuideCard: some View {
        guideCard(
            badge: "COLLABORATION",
            icon: "🤝",
            title: "Live Co-Draw (Beta)",
            subtitle: "Two people drawing together in real-time"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Draw together simultaneously on the same canvas! Open Co-Draw inside any circle to sketch side-by-side with your partner or friend.")
                    .font(.subheadline)
                    .foregroundColor(BrandColor.textSecondary)

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: 0x111827))
                        HStack(spacing: 8) {
                            Text("You ✏️")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: 0x3BD8D2))
                            Text("+")
                                .foregroundColor(.white.opacity(0.5))
                            Text("Partner 🎨")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: 0xF43F5E))
                        }
                    }
                    .frame(height: 50)

                    VStack(alignment: .leading, spacing: 4) {
                        featureBullet(title: "Sub-Second Sync", detail: "Lines appear live as they are being drawn.")
                        featureBullet(title: "Shared Canvas", detail: "Combine your art on one collaborative board.")
                    }
                }
            }
        }
    }

    // MARK: - 5. Guess My Doodle

    private var guessGameGuideCard: some View {
        guideCard(
            badge: "PARTY GAME",
            icon: "🎮",
            title: "Guess My Doodle",
            subtitle: "Multiplayer circle word guessing"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Turn drawings into an addictive party game! The drawer gets a secret word to sketch, and circle members race to guess it.")
                    .font(.subheadline)
                    .foregroundColor(BrandColor.textSecondary)

                VStack(spacing: 8) {
                    featureBullet(title: "Interactive Letter Tiles", detail: "Tap letter tiles to solve the mystery word.")
                    featureBullet(title: "Coin Letter Hints", detail: "Use coins to reveal tricky letters slot by slot.")
                    featureBullet(title: "24h Auto-Pass", detail: "If a drawer is inactive for 24h, anyone can claim the pen!")
                }
            }
        }
    }

    // MARK: - 6. Daily Streaks & Coins

    private var streaksAndCoinsCard: some View {
        guideCard(
            badge: "REWARDS",
            icon: "🔥",
            title: "Daily Streaks & Coins",
            subtitle: "Keep your flame alive & earn rewards"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Draw with your circle daily to build your flame. Consecutive days earn coins and exclusive permanent brush unlocks.")
                    .font(.subheadline)
                    .foregroundColor(BrandColor.textSecondary)

                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text("🌸 3-Day Unlock")
                            .font(.caption.weight(.bold))
                            .foregroundColor(BrandColor.primary)
                        Spacer()
                        Text("Pastel Brush & Lavender Mist Background")
                            .font(.caption2)
                            .foregroundColor(BrandColor.textSecondary)
                    }

                    HStack(spacing: 10) {
                        Text("🪙 Day-7 Jackpot")
                            .font(.caption.weight(.bold))
                            .foregroundColor(BrandColor.warning)
                        Spacer()
                        Text("+5 Coins Bonus Jackpot")
                            .font(.caption2)
                            .foregroundColor(BrandColor.textSecondary)
                    }

                    HStack(spacing: 10) {
                        Text("🎁 Doodle Gifts")
                            .font(.caption.weight(.bold))
                            .foregroundColor(Color.pink)
                        Spacer()
                        Text("Tip 1, 2, or 5 Coins on drawings you love")
                            .font(.caption2)
                            .foregroundColor(BrandColor.textSecondary)
                    }

                    HStack(spacing: 10) {
                        Text("⏰ 60-Min Warning")
                            .font(.caption.weight(.bold))
                            .foregroundColor(Color.orange)
                        Spacer()
                        Text("Alert before midnight if streak is about to break")
                            .font(.caption2)
                            .foregroundColor(BrandColor.textSecondary)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - 7. Solo Practice Sketchbook

    private var practiceCanvasCard: some View {
        guideCard(
            badge: "SOLO MODE",
            icon: "🎨",
            title: "Solo Practice Sketchbook",
            subtitle: "Experiment freely & save to Photos"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Want to test out brushes, backgrounds, or colors before creating or joining a circle? Practice Canvas gives you a private drawing pad with full creative tools.")
                    .font(.subheadline)
                    .foregroundColor(BrandColor.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    featureBullet(title: "No Circle Needed", detail: "Draw completely offline without any circles.")
                    featureBullet(title: "Save to Camera Roll", detail: "Exports high-resolution artwork straight to your iOS Photos.")
                }

                Button {
                    showingPracticeDrawing = true
                } label: {
                    HStack(spacing: 8) {
                        Text("🎨")
                        Text("Try Practice Canvas Now")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(BrandGradient.primary)
                    .foregroundColor(.black)
                    .cornerRadius(12)
                    .shadow(color: BrandColor.primary.opacity(0.3), radius: 6, x: 0, y: 3)
                }
            }
        }
    }

    // MARK: - Reusable Card Helpers

    private func guideCard<Content: View>(
        badge: String,
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(BrandColor.primary.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Text(icon)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(badge)
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundColor(BrandColor.primary)
                        Spacer()
                    }
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundColor(BrandColor.textPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(BrandColor.textSecondary)
                }
            }

            Divider()
                .opacity(0.4)

            content()
        }
        .padding(16)
        .background(BrandColor.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    private func featureBullet(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.subheadline.weight(.bold))
                .foregroundColor(BrandColor.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(BrandColor.textPrimary)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func brushRow(icon: String, name: String, desc: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.2))
                    .frame(width: 28, height: 28)
                Text(icon)
                    .font(.system(size: 14))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.weight(.bold))
                    .foregroundColor(BrandColor.textPrimary)
                Text(desc)
                    .font(.caption2)
                    .foregroundColor(BrandColor.textSecondary)
            }
            Spacer()
        }
    }
}
