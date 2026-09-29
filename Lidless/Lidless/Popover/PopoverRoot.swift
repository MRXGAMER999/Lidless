import SwiftUI

/// The menu bar popover's SwiftUI content, hosted by `StatusItemController`
/// in a transparent panel.
///
/// Contract with the panel:
/// - The app delegate owns `model` and `actions`; this view never creates stores.
/// - The visible panel is `PopoverMetrics.width` wide and `designHeight` tall,
///   or taller when the content needs it, but never taller than `maxHeight`:
///   there the displays list scrolls. It is padded by
///   `PopoverMetrics.shadowPadding`; the drop shadow is drawn in that margin.
///   The window follows this view's ideal size.
/// - Material: drawn here on macOS 26+ (a blur material under Liquid Glass);
///   on 12–25 AppKit puts a `.popover` material behind the panel rect and this
///   view adds the wash. With Reduce Transparency this view draws an opaque
///   fill instead, on every version.
struct PopoverRoot: View {
    let model: AppModel
    let actions: PopoverActions
    /// The tallest the visible panel may be; nil when nothing limits it.
    let maxHeight: CGFloat?

    init(model: AppModel, actions: PopoverActions, maxHeight: CGFloat? = nil) {
        self.model = model
        self.actions = actions
        self.maxHeight = maxHeight
    }

    var body: some View {
        PopoverView(model: model, actions: actions, maxHeight: maxHeight)
            .modifier(PopoverChrome())
            .padding(PopoverMetrics.shadowPadding)
    }
}

/// The panel's look (design-spec §1.6 `shadowPopover`, §1.7): frosted
/// material, 1 pt border, 1 pt outer ring, top and bottom inset highlights,
/// and the drop shadow drawn only outside the shape.
private struct PopoverChrome: ViewModifier {
    func body(content: Content) -> some View {
        let radius = PopoverMetrics.cornerRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        // The content isn't clipped: the design's panel has no `overflow: hidden`.
        content
            .background { PopoverMaterial(shape: shape) }
            .overlay {
                ZStack {
                    InsetHighlight(cornerRadius: radius - 1, color: Palette.popoverInsetTop, dy: 1.5, blur: 1)
                        .padding(Spacing.hairline)
                    InsetHighlight(cornerRadius: radius - 1, color: Palette.popoverInsetBottom, dy: -1, blur: 1)
                        .padding(Spacing.hairline)
                    shape.strokeBorder(Palette.popoverBorder, lineWidth: 1)
                    // CSS `0 0 0 1px`: a ring just outside the border box.
                    RoundedRectangle(cornerRadius: radius + 1, style: .circular)
                        .strokeBorder(Palette.popoverRing, lineWidth: 1)
                        .padding(-1)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .background {
                OuterShadow(
                    cornerRadius: radius,
                    far: .css(y: 20, blur: 50, color: Palette.popoverShadowFar),
                    near: .css(y: 2, blur: 8, color: Palette.popoverShadowNear)
                )
            }
    }
}

/// The design's `backdrop-filter: blur(40px) saturate(170%)` under a wash, or
/// an opaque fill with Reduce Transparency.
private struct PopoverMaterial: View {
    let shape: RoundedRectangle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            // Covers the AppKit material on 12–25 too (which turns opaque by
            // itself), so the panel looks the same on every version.
            shape.fill(Palette.popoverSolid)
        } else if #available(macOS 26, *) {
            ZStack {
                // Liquid Glass alone blurs far less than the design, so blob
                // edges showed through. This material (blur 60, saturate 160%)
                // spreads the backdrop first; the glass over it keeps the
                // system's look and settings. Full-strength glass also greys
                // the panel, most in dark, hence the partial opacity (tuned
                // against design/renders at 2x).
                shape.fill(.ultraThinMaterial)
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .opacity(colorScheme == .dark ? 0.3 : 0.6)
                shape.fill(Palette.popoverGlassWash)
            }
            // Also trims the glass's own rim and shadow, which sit just outside
            // the shape and would darken the design's ring and shadow.
            .clipShape(shape)
        } else {
            // StatusPanelContentView already draws the `.popover` material behind this rect.
            shape.fill(Palette.popoverWash)
        }
    }
}
