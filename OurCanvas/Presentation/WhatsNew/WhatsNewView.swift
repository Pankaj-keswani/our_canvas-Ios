import SwiftUI

/// What's New tab: hero gradient, staggered animated feature cards, NEW badges and
/// tag chips. Opening the tab clears the versioned red dot.
struct WhatsNewView: View {
    @ObservedObject var viewModel: WhatsNewViewModel
    @State private var appeared = false

    init(viewModel: WhatsNewViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero

                LazyVStack(spacing: 12) {
                    ForEach(Array(WhatsNewContent.cards.enumerated()), id: \.element.id) { index, card in
                        FeatureCardView(card: card)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 18)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85)
                                .delay(Double(index) * 0.06),
                                       value: appeared)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background(BrandBackground())
        .onAppear {
            viewModel.markCurrentSeen()
            withAnimation {
                appeared = true
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Text("✨")
                .font(.system(size: 44))
            Text("What's New")
                .font(BrandFont.title())
                .foregroundColor(BrandColor.textPrimary)
            Text("Fresh from the studio, with love")
                .font(BrandFont.body())
                .foregroundColor(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            LinearGradient(colors: [BrandColor.primary.opacity(0.16), BrandColor.secondary.opacity(0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .padding(.horizontal)
    }
}

struct FeatureCardView: View {
    let card: WhatsNewContent.Card

    private var tagColor: Color {
        switch card.tag {
        case .play: return BrandColor.primary
        case .create: return BrandColor.secondary
        case .together: return Color(hex: 0xF97316)
        case .pro: return BrandColor.warning
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tagColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(card.emoji)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(card.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(BrandColor.textPrimary)
                    if card.isNew {
                        Text("NEW")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(BrandGradient.primary))
                            .foregroundColor(.black)
                    }
                }
                Text(card.subtitle)
                    .font(.caption)
                    .foregroundColor(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.tag.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(tagColor.opacity(0.6), lineWidth: 1))
                    .foregroundColor(tagColor)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(BrandColor.surface.opacity(0.6))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}

struct WhatsNewView_Previews: PreviewProvider {
    static var previews: some View {
        WhatsNewView(viewModel: WhatsNewViewModel())
    }
}
