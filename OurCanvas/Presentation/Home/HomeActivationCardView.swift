import SwiftUI

/// 3-step visual activation guide card shown on the Home Screen when the user has 0 circles.
/// Matches Android commit 0654258 parity.
struct HomeActivationCardView: View {
    let onCreateOrJoinCircle: () -> Void
    let onPracticeCanvas: () -> Void
    let onHowItWorks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header: Badge + Title + Subtitle
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text("✨ GET STARTED")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(BrandColor.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(BrandColor.primary.opacity(0.15)))
                }

                Text("Welcome to Our Canvas!")
                    .font(.title2.weight(.bold))
                    .foregroundColor(BrandColor.textPrimary)

                Text("Doodle with your favorite person and have drawings show up live on each other's home screens.")
                    .font(.subheadline)
                    .foregroundColor(BrandColor.textSecondary)
                    .lineSpacing(2)
            }

            Divider()
                .opacity(0.5)

            // 3-step visual guide
            VStack(spacing: 14) {
                stepRow(
                    number: "1",
                    icon: "⭕",
                    title: "Create or Join a Circle",
                    description: "A private room for you and your partner or friend."
                )

                stepRow(
                    number: "2",
                    icon: "🎨",
                    title: "Draw & Send",
                    description: "Send neon doodles, notes, or guess challenges."
                )

                stepRow(
                    number: "3",
                    icon: "📱",
                    title: "Add the Home Widget",
                    description: "Pin Our Canvas widget to see drawings instantly."
                )
            }

            Divider()
                .opacity(0.5)

            // Action Buttons
            VStack(spacing: 10) {
                Button(action: onCreateOrJoinCircle) {
                    HStack(spacing: 8) {
                        Text("⭕")
                        Text("Create or Join a Circle")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BrandGradient.primary)
                    .foregroundColor(.black)
                    .cornerRadius(12)
                    .shadow(color: BrandColor.primary.opacity(0.3), radius: 6, x: 0, y: 3)
                }

                Button(action: onPracticeCanvas) {
                    HStack(spacing: 8) {
                        Text("🎨")
                        Text("Practice Canvas / Try Drawing")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(BrandColor.textPrimary)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }

                Button(action: onHowItWorks) {
                    HStack(spacing: 8) {
                        Text("📖")
                        Text("How Our Canvas Works (Visual Guide)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(BrandColor.textPrimary)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }

                Text("💡 Practice canvas lets you test all brushes and save sketches to your Photos!")
                    .font(.caption2)
                    .foregroundColor(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .background(BrandColor.surface.opacity(0.85))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [BrandColor.primary.opacity(0.35), BrandColor.secondary.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    private func stepRow(number: String, icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(BrandColor.primary.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(icon)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(number).")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(BrandColor.primary)
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(BrandColor.textPrimary)
                }

                Text(description)
                    .font(.caption)
                    .foregroundColor(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
