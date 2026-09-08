import SwiftUI

/// Placeholder for the What's New tab (spec A6.1). The versioned 11-card screen with the
/// red-dot system arrives in the What's New phase; the tab exists now so the navigation
/// shell matches the final 5-destination structure.
struct WhatsNewView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(BrandGradient.primary)
            Text("What's New")
                .font(BrandFont.title())
                .foregroundColor(BrandColor.textPrimary)
            Text("Fresh from the studio — updates are on their way.")
                .font(BrandFont.body())
                .foregroundColor(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandBackground())
    }
}

struct WhatsNewView_Previews: PreviewProvider {
    static var previews: some View {
        WhatsNewView()
    }
}
