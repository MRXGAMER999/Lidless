import SwiftUI

/// The design's capsule switch with a capsule knob (design-spec §4 `PillToggle`).
///
/// Keeps `Toggle` semantics for VoiceOver through `accessibilityRepresentation`;
/// the label is only used for accessibility.
struct PillToggleStyle: ToggleStyle {
    enum Size {
        /// 42×24, onboarding and settings rows.
        case small
        /// 48×28, popover desk card.
        case medium
        /// 52×30, settings "Boost allowed".
        case large
        /// 72×40, settings Desk Mode hero.
        case extraLarge
    }

    enum Surface {
        case light
        /// On a dark hero card, in both appearances.
        case onDark
    }

    var size: Size = .medium
    var surface: Surface = .light

    func makeBody(configuration: Configuration) -> some View {
        PillToggleSwitch(isOn: configuration.$isOn, size: size, surface: surface)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
    }
}

private struct PillToggleSwitch: View {
    @Binding var isOn: Bool
    let size: PillToggleStyle.Size
    let surface: PillToggleStyle.Surface

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = Metrics(size)
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(trackColor)
                .overlay {
                    CapsuleInsetHighlight(color: Color.white.opacity(isEnabled ? metrics.trackHighlight : 0), dy: 1)
                }
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(knobColor)
                        .frame(width: metrics.knob.width, height: metrics.knob.height)
                        .lidlessShadow(isEnabled ? metrics.knobShadow(isOn: isOn) : metrics.knobShadow(isOn: isOn).scaled(opacity: 0))
                        .padding(metrics.padding)
                }
                .frame(width: metrics.track.width, height: metrics.track.height)
                .contentShape(Capsule())
        }
        .buttonStyle(UndimmedButtonStyle())
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: isOn)
    }

    private var trackColor: Color {
        switch (isOn, surface, isEnabled) {
        case (true, _, true): Palette.gold
        case (true, _, false): Palette.gold.opacity(0.5)
        case (false, .onDark, true): Palette.onDarkToggleOff
        case (false, .onDark, false): Palette.onDarkToggleDisabledTrack
        case (false, .light, true): Palette.toggleOffTrack
        // Not designed: a faded off track.
        case (false, .light, false): Palette.toggleOffTrack.opacity(0.5)
        }
    }

    private var knobColor: Color {
        switch (isOn, surface, isEnabled) {
        case (true, _, true): Palette.ink
        case (true, _, false): Palette.ink.opacity(0.6)
        case (false, .onDark, false): Palette.onDarkToggleDisabledKnob
        case (false, .light, false): Palette.white.opacity(0.7)
        case (false, _, true): Palette.white
        }
    }

    private struct Metrics {
        let track: CGSize
        let knob: CGSize
        let padding: CGFloat
        let trackHighlight: Double
        let size: PillToggleStyle.Size

        init(_ size: PillToggleStyle.Size) {
            self.size = size
            switch size {
            case .small:
                track = CGSize(width: 42, height: 24); knob = CGSize(width: 26, height: 20); padding = 2; trackHighlight = 0
            case .medium:
                track = CGSize(width: 48, height: 28); knob = CGSize(width: 28, height: 22); padding = 3; trackHighlight = 0.3
            case .large:
                track = CGSize(width: 52, height: 30); knob = CGSize(width: 32, height: 24); padding = 3; trackHighlight = 0.35
            case .extraLarge:
                track = CGSize(width: 72, height: 40); knob = CGSize(width: 42, height: 32); padding = 4; trackHighlight = 0.35
            }
        }

        func knobShadow(isOn: Bool) -> ShadowLayer {
            switch size {
            case .small: .css(y: 1, blur: 3, color: .black.opacity(isOn ? 0.3 : 0.25))
            case .medium: .css(y: 1, blur: 4, color: .black.opacity(0.4))
            case .large: .css(y: 2, blur: 5, color: .black.opacity(0.35))
            case .extraLarge: .css(y: 2, blur: 6, color: .black.opacity(0.35))
            }
        }
    }
}

/// Shows the label as is. `.plain` fades disabled content on macOS, which would
/// halve the designed disabled colours.
private struct UndimmedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
