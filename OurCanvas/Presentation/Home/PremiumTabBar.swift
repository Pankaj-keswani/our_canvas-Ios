import SwiftUI
import UIKit

// MARK: - Premium Tab Bar (Android `MainActivity.PremiumBottomBar` parity)

/// Motion + geometry constants mirroring the Android `PremiumBottomBar` update
/// (source of truth: Android repo, MainActivity.kt, 2026-09-24).
enum PremiumTabBarLayout {
    static let barHeight: CGFloat = 74
    static let barCornerRadius: CGFloat = 37                    // fully-rounded pill
    static let barHorizontalPadding: CGFloat = 20
    static let barBottomGap: CGFloat = 12
    /// Width cap so the pill centers (not stretches) on iPad — no layout jump either way.
    static let pillMaxWidth: CGFloat = 560

    static let createDiscSize: CGFloat = 58
    static let createDiscRaise: CGFloat = 16                    // top edge pokes above the pill
    static let createSlotWidth: CGFloat = 72                    // dedicated slot; never crowds neighbors

    static let capsuleWidth: CGFloat = 44
    static let capsuleHeight: CGFloat = 32
    static let capsuleCornerRadius: CGFloat = 16
    static let capsuleOpacity: Double = 0.15                    // brand primary at 15%

    static let iconPointSize: CGFloat = 22
    static let pressSquashX: CGFloat = 0.85
    static let pressStretchY: CGFloat = 1.08
    static let pressSquashDuration: TimeInterval = 0.09         // 90ms touch-down ease
    static let selectionPopScale: CGFloat = 1.15                // spring pop with bounce
    static let entranceFromScale: CGFloat = 0.92

    static let haloDiameter: CGFloat = 78                       // soft breathing glow behind the disc
    static let haloAlphaMin: Double = 0.25
    static let haloAlphaMax: Double = 0.55
    static let haloCycleDuration: TimeInterval = 1.4            // one ease loop, repeats forever

    /// Layout space reserved below content so nothing hides behind the floating pill.
    static var chromeReservedHeight: CGFloat { barHeight + barBottomGap }
}

// MARK: - Breathing halo (Core Animation, 60fps, touch-transparent)

/// The UIKit glow behind the Create disc: a radial cyan gradient that pulses
/// `alpha 0.25 ↔ 0.55` on a 1.4s ease loop, forever. Driven by an autoreversing
/// `CABasicAnimation` on the layer (no Timer, no SwiftUI state churn), and it can
/// never intercept touches.
final class BreathingHaloView: UIView {
    private let glow = CAGradientLayer()
    private var configured = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        guard !configured else { return }
        configured = true
        isUserInteractionEnabled = false
        backgroundColor = .clear

        glow.type = .radial
        glow.colors = [
            UIColor(BrandColor.primary).cgColor,
            UIColor(BrandColor.primary).withAlphaComponent(0.55).cgColor,
            UIColor(BrandColor.primary).withAlphaComponent(0).cgColor,
        ]
        glow.locations = [0, 0.55, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.opacity = Float(PremiumTabBarLayout.haloAlphaMin)
        glow.isOpaque = false
        layer.addSublayer(glow)
        startBreathing()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glow.frame = bounds
    }

    private func startBreathing() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = PremiumTabBarLayout.haloAlphaMin
        pulse.toValue = PremiumTabBarLayout.haloAlphaMax
        pulse.duration = PremiumTabBarLayout.haloCycleDuration / 2
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.isRemovedOnCompletion = false
        pulse.fillMode = .forwards
        glow.add(pulse, forKey: "breathingHalo")
    }

    /// The halo must never swallow touches aimed at overlapping views.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}

/// SwiftUI bridge for the Core Animation halo.
struct BreathingHalo: UIViewRepresentable {
    func makeUIView(context: Context) -> BreathingHaloView {
        BreathingHaloView(frame: .zero)
    }

    func updateUIView(_ uiView: BreathingHaloView, context: Context) {}
}

// MARK: - Press feedback (squash-and-stretch)

/// Squash-and-stretch for tab presses: on touch-down, X compresses to 0.85 while Y
/// compensates to ~1.08 over a fast 90ms ease; on release, a bouncy spring with
/// slight overshoot restores the shape.
struct SquashStretchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                x: configuration.isPressed ? PremiumTabBarLayout.pressSquashX : 1,
                y: configuration.isPressed ? PremiumTabBarLayout.pressStretchY : 1
            )
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: PremiumTabBarLayout.pressSquashDuration)
                    : .spring(response: 0.32, dampingFraction: 0.55),
                value: configuration.isPressed
            )
    }
}

// MARK: - Tab model

struct PremiumTab: Identifiable {
    let id: Int
    let label: String
    let icon: String
    let activeIcon: String
    let showUnreadDot: Bool
    let badgeCount: Int?

    init(id: Int, label: String, icon: String, activeIcon: String? = nil,
         showUnreadDot: Bool = false, badgeCount: Int? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.activeIcon = activeIcon ?? icon
        self.showUnreadDot = showUnreadDot
        self.badgeCount = badgeCount
    }
}

// MARK: - Individual tab cell

private struct PremiumTabCell: View {
    let tab: PremiumTab
    let isSelected: Bool
    let action: () -> Void

    @State private var popScale: CGFloat = 1

    private var tintColor: Color {
        isSelected ? BrandColor.primary : BrandColor.textSecondary.opacity(0.55)
    }

    var body: some View {
        Button {
            // Light tick on every tab tap (Android haptic parity).
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 2) {
                iconArea
                Text(tab.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(tintColor)
                    .animation(.easeInOut(duration: 0.2), value: tintColor)
            }
        }
        .buttonStyle(SquashStretchButtonStyle())
        .onChange(of: isSelected) { selected in
            if selected {
                // Icon spring-pops to 1.15× with bounce, then settles back.
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
                    popScale = PremiumTabBarLayout.selectionPopScale
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                        popScale = 1
                    }
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    popScale = 1
                }
            }
        }
    }

    private var iconArea: some View {
        ZStack {
            // Rounded-capsule highlight (44×32, 16pt radius, 15% primary) behind the
            // icon — scale+fade in with the same bouncy spring as the icon pop.
            RoundedRectangle(cornerRadius: PremiumTabBarLayout.capsuleCornerRadius, style: .continuous)
                .fill(BrandColor.primary.opacity(PremiumTabBarLayout.capsuleOpacity))
                .frame(width: PremiumTabBarLayout.capsuleWidth, height: PremiumTabBarLayout.capsuleHeight)
                .scaleEffect(isSelected ? 1 : 0.6)
                .opacity(isSelected ? 1 : 0)
                .animation(
                    isSelected ? .spring(response: 0.35, dampingFraction: 0.55) : .linear(duration: 0.12),
                    value: isSelected
                )

            Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                .font(.system(size: PremiumTabBarLayout.iconPointSize, weight: isSelected ? .semibold : .medium))
                .scaleEffect(popScale)
                .foregroundColor(tintColor)
                .animation(.easeInOut(duration: 0.2), value: tintColor)
        }
        .frame(width: PremiumTabBarLayout.capsuleWidth, height: PremiumTabBarLayout.capsuleHeight)
        .overlay(alignment: .topTrailing) {
            badgeOverlay
        }
    }

    @ViewBuilder
    private var badgeOverlay: some View {
        if let count = tab.badgeCount, count > 0 {
            // Counter badge (top-trailing of the icon).
            Text("\(count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.red))
                .offset(x: 10, y: -4)
                .allowsHitTesting(false)
        } else if tab.showUnreadDot {
            // What's New red unread dot, preserved from the previous tab bar.
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .offset(x: 6, y: -2)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Center Create disc

private struct PremiumCreateDisc: View {
    let action: () -> Void

    @State private var appeared = false

    var body: some View {
        Button {
            // Stronger haptic on the Create button.
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .frame(width: PremiumTabBarLayout.createDiscSize, height: PremiumTabBarLayout.createDiscSize)
                .background(BrandGradient.create)
                .clipShape(Circle())
                // Cyan-tinted glow shadow so the disc visibly floats.
                .shadow(color: BrandColor.primary.opacity(0.45), radius: 12, x: 0, y: 6)
                // Hit target is exactly the 58pt disc — the halo sits OUTSIDE the
                // button label below so it can never enlarge the tappable area.
                .contentShape(Circle())
        }
        .buttonStyle(SquashStretchButtonStyle())
        .accessibilityLabel("Create")
        .background(
            BreathingHalo()
                .frame(width: PremiumTabBarLayout.haloDiameter, height: PremiumTabBarLayout.haloDiameter)
                .allowsHitTesting(false)
        )
        .scaleEffect(appeared ? 1 : PremiumTabBarLayout.entranceFromScale)
        .opacity(appeared ? 1 : 0)
        // The Create button enters a beat later than the pill itself.
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: appeared)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                appeared = true
            }
        }
    }
}

// MARK: - Bar container

struct PremiumTabBar: View {
    let tabs: [PremiumTab]
    @Binding var selection: Int
    var onCreate: () -> Void

    // Entrance: pill springs in (0.92 → 1.0 with overshoot).
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            tabCell(0)
            tabCell(1)

            // Dedicated 72pt slot so the raised disc never crowds its neighbors.
            PremiumCreateDisc(action: onCreate)
                .frame(width: PremiumTabBarLayout.createSlotWidth)
                .offset(y: -PremiumTabBarLayout.createDiscRaise)

            tabCell(2)
            tabCell(3)
        }
        .padding(.horizontal, 6)
        .frame(height: PremiumTabBarLayout.barHeight)
        // Cap the pill width: on iPad it centers instead of stretching edge-to-edge.
        .frame(maxWidth: PremiumTabBarLayout.pillMaxWidth)
        .background(
            RoundedRectangle(cornerRadius: PremiumTabBarLayout.barCornerRadius, style: .continuous)
                .fill(BrandColor.surface.opacity(0.97))
                // Stronger elevation + tighter black spot shadow so the pill visibly floats.
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PremiumTabBarLayout.barCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, PremiumTabBarLayout.barHorizontalPadding)
        .frame(maxWidth: .infinity) // center within the bottom inset region
        .scaleEffect(appeared ? 1 : PremiumTabBarLayout.entranceFromScale)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: appeared)
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private func tabCell(_ index: Int) -> some View {
        if tabs.indices.contains(index) {
            let tab = tabs[index]
            PremiumTabCell(tab: tab, isSelected: selection == tab.id) {
                select(tab.id)
            }
        }
    }

    private func select(_ id: Int) {
        guard id != selection else { return }
        selection = id
    }
}

// MARK: - Chrome helper

extension View {
    /// Mounts the Android-parity floating pill bar and reserves bottom layout space so
    /// scrollable content never hides behind it (safe-area handling preserved: the bar
    /// sits inside the bottom safe-area inset, above the home indicator).
    @ViewBuilder
    func premiumTabBarChrome(tabs: [PremiumTab],
                             selection: Binding<Int>,
                             onCreate: @escaping () -> Void,
                             isVisible: Bool = true) -> some View {
        if isVisible {
            safeAreaInset(edge: .bottom, spacing: 0) {
                PremiumTabBar(tabs: tabs, selection: selection, onCreate: onCreate)
                    .padding(.bottom, PremiumTabBarLayout.barBottomGap)
            }
        } else {
            self
        }
    }
}
