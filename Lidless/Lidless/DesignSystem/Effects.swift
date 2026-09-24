import SwiftUI

/// One CSS `box-shadow` layer.
struct ShadowLayer {
    var color: Color
    var radius: CGFloat
    var x: CGFloat = 0
    var y: CGFloat = 0

    /// From CSS `x y blur color`. A CSS blur of B looks like a SwiftUI radius of about B/2.
    static func css(x: CGFloat = 0, y: CGFloat, blur: CGFloat, color: Color) -> ShadowLayer {
        ShadowLayer(color: color, radius: blur / 2, x: x, y: y)
    }

    func scaled(opacity factor: Double) -> ShadowLayer {
        ShadowLayer(color: color.opacity(factor), radius: radius, x: x, y: y)
    }
}

extension View {
    /// Applies a shadow layer. Casts from everything the view draws, so use it
    /// on opaque backgrounds; for translucent ones use `OuterShadow`.
    func lidlessShadow(_ layer: ShadowLayer) -> some View {
        shadow(color: layer.color, radius: layer.radius, x: layer.x, y: layer.y)
    }
}

/// CSS outer `box-shadow` for a translucent rounded rectangle: drawn only
/// outside the shape, so it can't darken the see-through fill above it.
struct OuterShadow: View {
    let cornerRadius: CGFloat
    let far: ShadowLayer
    var near: ShadowLayer?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        // The caster sits 1 pt inside the cut-out, so its anti-aliased edge
        // can't survive the mask as a grey hairline.
        let caster = RoundedRectangle(cornerRadius: max(0, cornerRadius - 1), style: .circular)
        ZStack {
            caster.fill(Color.black).padding(Spacing.hairline).lidlessShadow(far)
            caster.fill(Color.black).padding(Spacing.hairline).lidlessShadow(near ?? far.scaled(opacity: 0))
        }
        .mask {
            ZStack {
                Rectangle().padding(-(far.radius * 3 + abs(far.y) + 8))
                shape.blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// CSS `box-shadow: inset 0 dy blur color`: a band of colour along the top
/// (dy > 0) or bottom (dy < 0) inside edge, following the corners.
struct InsetHighlight: View {
    let cornerRadius: CGFloat
    let color: Color
    let dy: CGFloat
    var blur: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        shape.fill(color)
            .mask {
                ZStack {
                    Rectangle()
                    shape.offset(y: dy).blur(radius: blur / 2).blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// CSS `box-shadow: inset 0 dy blur color` on a capsule.
struct CapsuleInsetHighlight: View {
    let color: Color
    let dy: CGFloat

    var body: some View {
        GeometryReader { proxy in
            InsetHighlight(cornerRadius: min(proxy.size.width, proxy.size.height) / 2, color: color, dy: dy)
        }
        .allowsHitTesting(false)
    }
}
