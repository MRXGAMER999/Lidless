import LidlessCore
import SwiftUI

/// The Brightness tab's Boost ceiling slider (design-spec §7.3, Settings2-Brightness),
/// drawn on the dark hero in both appearances.
///
///     CeilingSlider(ceilingNits: $preferences.boost.ceilingNits, normalMaxNits: scale.normalMaxNits)
///         .disabled(!preferences.boost.allowed)
///
/// - `ceilingNits`: the stored ceiling (`BoostSettings.ceilingNits`), written in
///   steps of 50 inside `selectableRange(normalMaxNits:)`.
/// - `normalMaxNits`: the panel's real normal (SDR) maximum
///   (`BrightnessScale.normalMaxNits`). The "Normal max" mark and label sit
///   there, and the handle can't go below it (design-spec V1).
/// - Disable it with `.disabled(_:)` when Boost isn't allowed; it then greys
///   out (not designed) and ignores the pointer and arrow keys.
///
/// The track is a linear 0…1,600 nit scale: normal range up to the normal max,
/// the available Boost range up to the 1,000 nit full-screen limit, hatched
/// "small highlights only" range above it. Arrow keys move 50 nits; VoiceOver
/// gets a real `Slider` ("Boost ceiling in nits").
struct CeilingSlider: View {
    @Binding var ceilingNits: Double
    let normalMaxNits: Double

    /// Right end of the scale: small HDR highlights only.
    static let scaleMaxNits = 1600.0
    /// Brightest the whole screen can go; the top of the handle's range.
    static let fullScreenLimitNits = BoostSettings.ceilingRange.upperBound
    static let step = BoostSettings.ceilingStep

    /// Where the handle can go: from one step above the normal maximum (rounded
    /// up to the step, 550 for a 500 nit panel as designed, 650 for 600) to the
    /// full-screen limit. Nil when the panel's normal maximum leaves no room to boost.
    /// The live Boost range uses the same rule (`BoostSettings.ceilingRange(normalMaxNits:)`).
    static func selectableRange(normalMaxNits: Double) -> ClosedRange<Double>? {
        BoostSettings.ceilingRange(normalMaxNits: normalMaxNits)
    }

    /// The ceiling the handle shows for a stored value: the ceiling Boost really
    /// uses on this panel (`BoostSettings.effectiveCeiling`), so Settings, the
    /// popover, the keys and the intents agree. Use it for the hero's
    /// "≈ N nits max" too. The full-screen limit when there is no room to boost.
    static func displayedCeiling(_ ceilingNits: Double, normalMaxNits: Double) -> Double {
        BoostSettings.effectiveCeiling(ceilingNits, normalMaxNits: normalMaxNits) ?? fullScreenLimitNits
    }

    @Environment(\.isEnabled) private var isEnabled

    private var range: ClosedRange<Double>? { Self.selectableRange(normalMaxNits: normalMaxNits) }
    private var shownCeiling: Double { Self.displayedCeiling(ceilingNits, normalMaxNits: normalMaxNits) }
    private var canChange: Bool { isEnabled && range != nil }

    var body: some View {
        VStack(spacing: 10) {
            CeilingTrack(
                ceilingNits: shownCeiling,
                normalMaxNits: normalMaxNits,
                range: range,
                isEnabled: canChange,
                onChange: { nits in set(nits) }
            )
            CeilingLabels(normalMaxNits: normalMaxNits)
        }
        // Nits grow to the right in every language, like the track's scale.
        .environment(\.layoutDirection, .leftToRight)
        .modifier(KeyboardOnlyFocusable())
        .onMoveCommand { direction in
            switch direction {
            case .left, .down: nudge(by: -Self.step)
            case .right, .up: nudge(by: Self.step)
            @unknown default: break
            }
        }
        .accessibilityRepresentation { accessibilitySlider }
    }

    /// What VoiceOver sees: a real slider over the handle's travel.
    private var accessibilitySlider: some View {
        let value = Binding<Double>(
            get: { shownCeiling },
            set: { newValue in set(newValue) }
        )
        let bounds = range ?? (Self.fullScreenLimitNits - Self.step)...Self.fullScreenLimitNits
        let nits = Int(shownCeiling.rounded())
        return Slider(value: value, in: bounds, step: Self.step) {
            Text("Boost ceiling in nits", comment: "VoiceOver label of the Boost ceiling slider in Settings › Brightness")
        }
        // A plain Int makes the key "%lld nits", so translators can pluralize it.
        .accessibilityValue(Text("\(nits) nits", comment: "VoiceOver value of the Boost ceiling slider; the variable is the ceiling in nits, e.g. \"1000 nits\""))
        .disabled(!canChange)
    }

    private func nudge(by delta: Double) {
        guard canChange, let range else { return }
        set(SliderMath.nudge(shownCeiling, by: delta, in: range, step: Self.step))
    }

    private func set(_ nits: Double) {
        guard canChange, let range else { return }
        let snapped = SliderMath.nudge(nits, by: 0, in: range, step: Self.step)
        // The binding writes preferences; skip drags within the same step.
        if snapped != ceilingNits { ceilingNits = snapped }
    }
}

/// Track area, 34 pt tall: the 16 pt bar at y 9, two 28 pt marks at y 3 and
/// the 22×34 handle.
private struct CeilingTrack: View {
    let ceilingNits: Double
    let normalMaxNits: Double
    let range: ClosedRange<Double>?
    let isEnabled: Bool
    let onChange: (Double) -> Void

    private static let handleSize = CGSize(width: 22, height: 34)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = { (nits: Double) in CGFloat(SliderMath.fraction(of: nits, in: 0...CeilingSlider.scaleMaxNits)) * width }
            let normalX = x(normalMaxNits)
            let limitX = x(CeilingSlider.fullScreenLimitNits)
            let handleX = x(ceilingNits)
            ZStack(alignment: .topLeading) {
                CeilingBar(width: width, normalX: normalX, limitX: limitX, fillX: handleX, isEnabled: isEnabled)
                    .offset(y: 9)
                ForEach([normalX, limitX], id: \.self) { markX in
                    Rectangle()
                        .fill(Palette.ceilingMarker)
                        .frame(width: 2, height: 28)
                        .offset(x: markX - 1, y: 3)
                }
                CeilingHandle(isEnabled: isEnabled)
                    .offset(x: handleX - Self.handleSize.width / 2)
                if let range {
                    // Like the canvas's range input, only the handle's travel
                    // takes the pointer (widened by half a handle at each end).
                    let start = x(range.lowerBound) - Self.handleSize.width / 2
                    let end = x(range.upperBound) + Self.handleSize.width / 2
                    Color.clear
                        .frame(width: max(0, end - start), height: Self.handleSize.height)
                        .contentShape(Rectangle())
                        .offset(x: start)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                                .onChanged { value in
                                    guard isEnabled, width > 0 else { return }
                                    onChange(Double(value.location.x / width) * CeilingSlider.scaleMaxNits)
                                }
                        )
                        .allowsHitTesting(isEnabled)
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
            .coordinateSpace(name: Self.space)
        }
        .frame(height: Self.handleSize.height)
    }

    private static let space = "CeilingTrack"
}

private struct CeilingBar: View {
    let width: CGFloat
    let normalX: CGFloat
    let limitX: CGFloat
    let fillX: CGFloat
    let isEnabled: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Palette.ceilingTrackBg)
            HatchStripes()
                .fill(Palette.ceilingHatch)
                .frame(width: max(0, width - limitX))
                .clipped()
                .offset(x: limitX)
            Rectangle()
                .fill(Palette.boostAvailable)
                .frame(width: max(0, limitX - normalX))
                .offset(x: normalX)
            Rectangle()
                .fill(Palette.gold)
                .frame(width: max(0, fillX - normalX))
                .offset(x: normalX)
            Rectangle()
                .fill(Palette.trackNormalOnDark)
                .frame(width: max(0, normalX))
        }
        .frame(width: width, height: 16, alignment: .leading)
        // One clip rounds the normal range's left end and the hatch's right end (r8).
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .circular))
        // Not designed: Boost not allowed greys the Boost colours out.
        .saturation(isEnabled ? 1 : 0)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// CSS `repeating-linear-gradient(135deg, stripe 0 4px, transparent 4px 9px)`:
/// "/" stripes 4 pt thick every 9 pt, measured across the stripes, counted
/// from the box's top-left corner.
private struct HatchStripes: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let root2 = CGFloat(2).squareRoot()
        let period: CGFloat = 9 * root2
        let thickness: CGFloat = 4 * root2
        var path = Path()
        var s: CGFloat = 0
        // Each band covers minX + minY + [s, s + thickness] in x + y.
        while s < rect.width + rect.height {
            let a = s, b = s + thickness
            path.move(to: CGPoint(x: rect.minX + a, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + b, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + b - rect.height, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + a - rect.height, y: rect.maxY))
            path.closeSubpath()
            s += period
        }
        return path
    }
}

private struct CeilingHandle: View {
    let isEnabled: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .circular)
        shape.fill(Palette.white)
            .overlay { shape.strokeBorder(Palette.gold, lineWidth: 3) }
            .frame(width: 22, height: 34)
            // One shadow for the whole handle, not one per layer.
            .compositingGroup()
            .lidlessShadow(.css(y: 3, blur: 10, color: .black.opacity(0.45)))
            .saturation(isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Labels row, 32 pt: "0" at the start, the normal max and the full-screen
/// limit centred under their marks, "1,600" at the end. 11 pt on 1.35 lines;
/// the 500, 1,000 and 1,600 numbers bold, the "0" regular.
private struct CeilingLabels: View {
    let normalMaxNits: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let normalX = Self.x(normalMaxNits, width: width)
            let limitX = Self.x(CeilingSlider.fullScreenLimitNits, width: width)
            // Each centred label sits in a full-width frame that lines its
            // centre guide up with the frame's; a guide of w/2 + width/2 − x
            // puts the label's own centre at x.
            ZStack(alignment: .topLeading) {
                label(number: 0, caption: nil, alignment: .leading, numberStyle: .caption)
                    .foregroundStyle(Palette.textOnDark)
                    .frame(width: width, alignment: .topLeading)
                label(
                    number: normalMaxNits,
                    caption: Text("Normal max", comment: "Label under the normal-maximum mark of the Boost ceiling slider"),
                    alignment: .center
                )
                .foregroundStyle(Palette.textOnDark2)
                .fixedSize()
                .alignmentGuide(HorizontalAlignment.center) { $0.width / 2 + width / 2 - normalX }
                .frame(width: width, alignment: .top)
                label(
                    number: CeilingSlider.fullScreenLimitNits,
                    caption: Text("Full-screen limit", comment: "Label under the 1,000 nit mark of the Boost ceiling slider"),
                    alignment: .center
                )
                .foregroundStyle(Palette.gold)
                .fixedSize()
                .alignmentGuide(HorizontalAlignment.center) { $0.width / 2 + width / 2 - limitX }
                .frame(width: width, alignment: .top)
                label(
                    number: CeilingSlider.scaleMaxNits,
                    caption: Text("Small highlights only", comment: "Label at the 1,600 nit end of the Boost ceiling slider"),
                    alignment: .trailing
                )
                .foregroundStyle(Palette.textOnDark)
                .frame(width: width, alignment: .topTrailing)
            }
        }
        .frame(height: 32)
        .accessibilityHidden(true)
    }

    private static func x(_ nits: Double, width: CGFloat) -> CGFloat {
        CGFloat(SliderMath.fraction(of: nits, in: 0...CeilingSlider.scaleMaxNits)) * width
    }

    private func label(number: Double, caption: Text?, alignment: HorizontalAlignment, numberStyle: TypeStyle = .captionStrong) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(Int(number.rounded()), format: .number)
                .lidlessStyle(numberStyle)
                .lineBox(numberStyle, lineHeight: 1.35)
            if let caption {
                caption
                    .lidlessStyle(.caption)
                    .lineBox(.caption, lineHeight: 1.35)
            }
        }
        .multilineTextAlignment(textAlignment(alignment))
        .lineLimit(1)
    }

    private func textAlignment(_ alignment: HorizontalAlignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }
}

#if DEBUG
private struct CeilingSliderPreview: View {
    @State private var ceiling = 1000.0
    let normalMax: Double
    var allowed = true

    var body: some View {
        CeilingSlider(ceilingNits: $ceiling, normalMaxNits: normalMax)
            .disabled(!allowed)
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .frame(width: 842)
            .background { HeroCardSurface(cornerRadius: Radius.heroSettings, elevation: .flat) }
    }
}

#Preview("Ceiling slider") {
    VStack(spacing: 12) {
        CeilingSliderPreview(normalMax: 500)
        CeilingSliderPreview(normalMax: 600)
        CeilingSliderPreview(normalMax: 600, allowed: false)
    }
    .padding(18)
}
#endif
