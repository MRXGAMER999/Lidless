import SwiftUI

/// The popover's frosted card: 0.6 white, 1 pt white border, white top highlight
/// (dark: 0.08 white, 0.1 border, 0.12 highlight).
struct GlassCardSurface: View {
    var cornerRadius: CGFloat = Radius.card

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        shape.fill(Palette.glassCardFill)
            .overlay {
                InsetHighlight(cornerRadius: cornerRadius - 1, color: Palette.glassCardInset, dy: 1)
                    .padding(Spacing.hairline)
            }
            .overlay { shape.strokeBorder(Palette.glassCardBorder, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Wraps content in a `GlassCardSurface`. `padding` is the CSS padding; the
    /// 1 pt border is added on top, as in the design's box model.
    func glassCard(padding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) -> some View {
        self.padding(padding)
            .padding(Spacing.hairline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { GlassCardSurface() }
    }
}

/// Dark hero surface (#141B24), used for the popover's Desk Mode card and the
/// Settings and onboarding heroes. White text on it in both appearances.
struct HeroCardSurface: View {
    enum Elevation {
        /// Settings/onboarding heroes: top highlight only.
        case flat
        /// Popover desk card: `0 4px 12px` drop; in dark, a gold border and glow instead.
        case popover
    }

    var cornerRadius: CGFloat = Radius.card
    var elevation: Elevation = .popover

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        switch elevation {
        case .flat:
            shape.fill(Palette.heroBackground)
                .overlay { InsetHighlight(cornerRadius: cornerRadius, color: Palette.deskCardInset, dy: 1) }
                .accessibilityHidden(true)
        case .popover:
            // CSS draws an inset shadow inside the border, and only dark has one.
            let border: CGFloat = colorScheme == .dark ? Spacing.hairline : 0
            shape.fill(Palette.deskCardFill)
                .lidlessShadow(.css(y: 4, blur: 12, color: Palette.deskCardShadow))
                .lidlessShadow(.css(y: 0, blur: 24, color: Palette.deskCardGlow))
                .overlay {
                    InsetHighlight(cornerRadius: cornerRadius - border, color: Palette.deskCardInset, dy: 1)
                        .padding(border)
                }
                .overlay { shape.strokeBorder(Palette.deskCardBorder, lineWidth: 1) }
                .accessibilityHidden(true)
        }
    }
}
