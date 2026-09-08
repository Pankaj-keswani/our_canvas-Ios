import SwiftUI

// MARK: - Brand palette (Android spec A11)

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum BrandColor {
    static let primary = Color(hex: 0x3BD8D2)       // neon cyan
    static let secondary = Color(hex: 0xAB5EFA)     // neon purple
    static let warning = Color(hex: 0xFACC15)       // gold
    static let surface = Color(hex: 0x1A2035)
    static let backgroundTop = Color(hex: 0x101426)
    static let backgroundBottom = Color(hex: 0x161D36)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
}

enum BrandGradient {
    static let background = LinearGradient(
        colors: [BrandColor.backgroundTop, BrandColor.backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    static let primary = LinearGradient(
        colors: [BrandColor.primary, BrandColor.secondary],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let premium = LinearGradient(
        colors: [BrandColor.warning, Color(hex: 0xF97316)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Typography (rounded accents; custom handwritten fonts land in the UI polish phase)

enum BrandFont {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func title() -> Font { rounded(28, .bold) }
    static func headline() -> Font { rounded(17, .semibold) }
    static func body() -> Font { rounded(15, .regular) }
    static func caption() -> Font { rounded(12, .medium) }
}

// MARK: - Reusable surfaces

struct BrandBackground: View {
    var body: some View {
        BrandGradient.background.ignoresSafeArea()
    }
}

struct GlassCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(BrandColor.surface.opacity(0.55))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardStyle())
    }
}

struct PrimaryGradientButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                }
                Text(title)
                    .font(BrandFont.headline())
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7) // Dynamic Type XXL tolerance
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(BrandGradient.primary)
            .cornerRadius(14)
        }
        .disabled(isLoading)
    }
}
