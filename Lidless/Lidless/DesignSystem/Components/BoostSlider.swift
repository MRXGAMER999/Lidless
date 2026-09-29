import AppKit
import Combine
import LidlessCore
import SwiftUI

/// The built-in display slider (design-spec §5.3): a navy normal range, a
/// Boost line at two thirds, and a gold Boost range after it.
///
/// Drawn by hand because the design's track, line and thumb can't be made
/// from `Slider`; VoiceOver still gets a real `Slider`.
struct BoostSlider: View {
    @Binding var position: Double
    let scale: BrightnessScale
    let label: Text
    /// Called with true when the pointer presses the track and false when it
    /// lets go, like `Slider`'s. Arrow keys and VoiceOver don't call it.
    var onEditingChanged: (Bool) -> Void = { _ in }

    /// Arrow keys move this many positions (about 3% of the track).
    private let keyboardStep = 5.0

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                GlyphView(glyph: .sunSmall, size: 14, lineWidth: 2)
                    .foregroundStyle(Palette.text4)
                BoostTrack(position: $position, scale: scale, onEditingChanged: onEditingChanged)
                GlyphView(glyph: .sun, size: 18, lineWidth: 1.8)
                    .foregroundStyle(Palette.text4)
            }
            BoostSliderLabels(boostLineFraction: scale.boostLineTrackFraction)
                .padding(.leading, 14 + 10)
                .padding(.trailing, 18 + 10)
        }
        // Brightness grows to the right in every language, like the keys that change it.
        .environment(\.layoutDirection, .leftToRight)
        .modifier(KeyboardNavigationFocusable())
        .onMoveCommand { direction in
            switch direction {
            case .left, .down: position = scale.position(position, nudgedBy: -keyboardStep)
            case .right, .up: position = scale.position(position, nudgedBy: keyboardStep)
            @unknown default: break
            }
        }
        .accessibilityRepresentation {
            // Without a step VoiceOver moves 10% of the travel (15), which can jump past the Boost line.
            // 5 positions are 5% below the line, which a step lands on exactly.
            Slider(value: $position, in: scale.travel, step: keyboardStep, label: { label })
                .accessibilityValue(Text(verbatim: BrightnessAccessibility.sliderValue(position: position, scale: scale, locale: locale)))
                .accessibilityHint(accessibilityHint)
        }
    }

    /// Where Boost starts, which the track shows only by its line and colour.
    private var accessibilityHint: Text {
        scale.canBoost
            ? Text("Above 100%, Boost makes the screen brighter than normal.", comment: "VoiceOver hint of the built-in brightness slider when Boost can be used")
            : Text(verbatim: "")
    }
}

private struct BoostTrack: View {
    @Binding var position: Double
    let scale: BrightnessScale
    let onEditingChanged: (Bool) -> Void
    /// The pointer holds the track. SwiftUI resets it when the drag ends or is
    /// cancelled, so a release is never missed. A thumb held still writes no
    /// position, so this is the only sign the user still has it.
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let thumbX = width * scale.trackFraction(position)
            let lineX = scale.boostLineTrackFraction.map { CGFloat($0) * width }
            ZStack(alignment: .topLeading) {
                BoostTrackBar(width: width, thumbX: thumbX, lineX: lineX)
                    .offset(y: 8)
                if let lineX {
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(Palette.boostMarker)
                        .frame(width: 2, height: 18)
                        .offset(x: lineX - 1, y: 3)
                }
                BoostThumb(isBoosted: scale.isBoosted(position))
                    .offset(x: thumbX - BoostThumb.size.width / 2, y: 2)
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, isDragging, _ in isDragging = true }
                    .onChanged { value in
                        guard width > 0 else { return }
                        let newPosition = scale.position(atTrackFraction: value.location.x / width)
                        // @Published fires on every set; skip drags within the same step.
                        if newPosition != position { position = newPosition }
                    }
            )
        }
        .frame(height: 24)
        .modifier(ChangeReporter(value: isDragging, action: onEditingChanged))
        // Replaced mid-drag (Desk Mode turning on), the track gets no release.
        .onDisappear { if isDragging { onEditingChanged(false) } }
    }
}

/// Calls `action` with each new value, not the first. The two-parameter
/// `onChange(of:)` is macOS 14+; the one-parameter form covers 12–13.
private struct ChangeReporter<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.onChange(of: value) { _, newValue in action(newValue) }
        } else {
            content.onChange(of: value) { newValue in action(newValue) }
        }
    }
}

private struct BoostTrackBar: View {
    let width: CGFloat
    let thumbX: CGFloat
    let lineX: CGFloat?

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Palette.track)
            if let lineX {
                Rectangle()
                    .fill(Palette.boostRegion)
                    .frame(width: max(0, width - lineX))
                    .offset(x: lineX)
                Rectangle()
                    .fill(Palette.gold)
                    .frame(width: max(0, thumbX - lineX))
                    .offset(x: lineX)
            }
            Rectangle()
                .fill(Palette.sliderFill)
                .frame(width: max(0, min(thumbX, lineX ?? width)))
        }
        .frame(width: width, height: 8, alignment: .leading)
        // One clip gives the navy fill its round left end and the Boost range its round right end.
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .circular))
    }
}

private struct BoostThumb: View {
    static let size = CGSize(width: 30, height: 20)
    let isBoosted: Bool

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .circular)
        shape.fill(Palette.white)
            .overlay { shape.strokeBorder(isBoosted ? Palette.gold : Palette.thumbRing, lineWidth: 2) }
            // With Differentiate Without Colour a boosted thumb also shows a
            // flame, since its ring only turns gold. Not designed.
            .overlay {
                if differentiateWithoutColor && isBoosted {
                    GlyphView(glyph: .flame, size: 12, lineWidth: 2.2)
                        .foregroundStyle(Palette.goldDeepFixed)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            // One shadow for the whole thumb; otherwise the ring also shadows the white face.
            .compositingGroup()
            .lidlessShadow(.css(y: 2, blur: 6, color: .black.opacity(0.2)))
    }
}

private struct BoostSliderLabels: View {
    let boostLineFraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Text("Normal", comment: "Label under the normal range of the built-in brightness slider")
                    .lidlessStyle(.caption)
                    .foregroundStyle(Palette.text4)
                if let boostLineFraction {
                    Text("Boost", comment: "Label under the Boost range of the built-in brightness slider")
                        .lidlessStyle(.captionStrong)
                        .foregroundStyle(Palette.goldDeep)
                        .fixedSize()
                        .offset(x: proxy.size.width * boostLineFraction + 8)
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// A thin level bar for external displays (design-spec §4 `MiniSlider`): 88×18,
/// 6 pt track, no thumb.
struct MiniSlider: View {
    @Binding var level: Double
    let label: Text

    static let width: CGFloat = 88
    private let keyboardStep = 0.05

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .circular)
        ZStack(alignment: .leading) {
            shape.fill(Palette.track)
                .frame(width: Self.width, height: 6)
            shape.fill(Palette.miniSliderFill)
                .frame(width: Self.width * SliderMath.fraction(of: level, in: 0...1), height: 6)
        }
        .frame(width: Self.width, height: 18, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let newLevel = SliderMath.value(atFraction: value.location.x / Self.width, in: 0...1, step: 0.01)
                    if newLevel != level { level = newLevel }
                }
        )
        .environment(\.layoutDirection, .leftToRight)
        .modifier(KeyboardNavigationFocusable())
        .onMoveCommand { direction in
            switch direction {
            case .left, .down: level = SliderMath.nudge(level, by: -keyboardStep, in: 0...1, step: 0.01)
            case .right, .up: level = SliderMath.nudge(level, by: keyboardStep, in: 0...1, step: 0.01)
            @unknown default: break
            }
        }
        .accessibilityRepresentation {
            Slider(value: $level, in: 0...1, step: keyboardStep, label: { label })
                .accessibilityValue(Text(SliderMath.percent(level: level), format: .percent))
        }
    }
}

/// Custom sliders take keyboard focus only when the user navigates by
/// keyboard, so opening the popover with the mouse never puts a focus ring on
/// them (since macOS 14 a plain `focusable()` view takes focus as soon as its
/// window becomes key). VoiceOver reaches them through their `Slider` representation.
private struct KeyboardNavigationFocusable: ViewModifier {
    @ObservedObject private var keyboardNavigation = KeyboardNavigation.shared

    func body(content: Content) -> some View {
        content.focusable(keyboardNavigation.isEnabled)
    }
}

/// System Settings › Keyboard › Keyboard navigation, as something views can observe.
///
/// AppKit has no public notification for changes to this setting and it can't
/// be observed with KVO, so it is read again whenever one of the app's windows
/// becomes key; the popover panel does each time it opens.
final class KeyboardNavigation: ObservableObject {
    static let shared = KeyboardNavigation()

    @Published private(set) var isEnabled: Bool

    private let readSetting: () -> Bool
    private var windowKeySubscription: AnyCancellable?

    init(
        readSetting: @escaping () -> Bool = { NSApp?.isFullKeyboardAccessEnabled ?? false },
        notificationCenter: NotificationCenter = .default
    ) {
        self.readSetting = readSetting
        isEnabled = readSetting()
        windowKeySubscription = notificationCenter.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let current = readSetting()
        // @Published fires on every set; only a real change should redraw the sliders.
        if current != isEnabled { isEnabled = current }
    }
}
