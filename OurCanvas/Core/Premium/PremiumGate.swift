import Foundation
import SwiftUI

/// Reusable premium gating for drawing features. Construct once per view from the
/// current plan; never scatter raw plan checks across views.
///
/// Phase 1 note: `isPro` comes from `users/{uid}.plan` via `UserRepository.currentUserProfile`
/// (including the Android test-email override). The StoreKit/backend binding hardening
/// arrives in the Premium phase — the gate API will not change.
struct PremiumGate {
    let isPro: Bool

    static let premiumBrushes: Set<BrushType> = [.neon, .rainbow, .glow]

    /// Gold + pastel colors are Pro (Android A4.2).
    static let premiumHexes: Set<String> = ["#FACC15", "#FDE68A", "#F9A8D4", "#A7F3D0", "#C4B5FD"]

    var canUseBrush: (BrushType) -> Bool { { brush in
        isPro || !Self.premiumBrushes.contains(brush)
    } }

    var canUseColor: (String) -> Bool { { hex in
        isPro || !Self.premiumHexes.contains(hex.uppercased())
    } }

    var canSaveToDevice: Bool { isPro }

    static func isPremiumBrush(_ brush: BrushType) -> Bool {
        premiumBrushes.contains(brush)
    }
}

/// Shared drawing color palette. Free + Pro (locked) entries, matching the Android
/// premium color concept.
enum DrawingPalette {
    struct Entry: Identifiable, Equatable {
        let hex: String
        let name: String
        let isPremium: Bool
        var id: String { hex }
    }

    static let entries: [Entry] = [
        Entry(hex: "#000000", name: "Black", isPremium: false),
        Entry(hex: "#FFFFFF", name: "White", isPremium: false),
        Entry(hex: "#EF4444", name: "Red", isPremium: false),
        Entry(hex: "#F97316", name: "Orange", isPremium: false),
        Entry(hex: "#FACC15", name: "Gold", isPremium: true),
        Entry(hex: "#22C55E", name: "Green", isPremium: false),
        Entry(hex: "#3B82F6", name: "Blue", isPremium: false),
        Entry(hex: "#8B5CF6", name: "Purple", isPremium: false),
        Entry(hex: "#F9A8D4", name: "Pastel Pink", isPremium: true),
        Entry(hex: "#FDE68A", name: "Pastel Yellow", isPremium: true),
        Entry(hex: "#A7F3D0", name: "Pastel Mint", isPremium: true),
        Entry(hex: "#C4B5FD", name: "Pastel Lilac", isPremium: true),
    ]

    static let backgroundHexes: [Entry] = [
        Entry(hex: "#FFFFFF", name: "White", isPremium: false),
        Entry(hex: "#FDF6E3", name: "Cream", isPremium: false),
        Entry(hex: "#E5E7EB", name: "Gray", isPremium: false),
        Entry(hex: "#1A2035", name: "Navy", isPremium: false),
        Entry(hex: "#101426", name: "Ink", isPremium: false),
        Entry(hex: "#F9A8D4", name: "Pastel Pink", isPremium: true),
    ]

    static let stickerEmojis: [String] = [
        "⭐️", "❤️", "😂", "😮", "😢", "🔥", "🎉", "✨",
        "🌈", "☀️", "🌙", "⚡️", "🌸", "🍀", "🎈", "🎁",
        "😍", "🤩", "😎", "🥳", "🤗", "😭", "👍", "🙌",
        "🐶", "🐱", "🐼", "🦄", "🍕", "🍩", "⚽️", "🎨",
    ]
}

extension Color {
    init(hexString: String) {
        let argb = StrokeColor.argbInt(fromHex: hexString)
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Deterministic avatar URL — same identity approach as Android (dicebear seeded by uid).
enum AvatarIdentity {
    static func url(forUid uid: String) -> URL? {
        URL(string: "https://api.dicebear.com/7.x/adventurer/png?seed=\(uid)")
    }
}
