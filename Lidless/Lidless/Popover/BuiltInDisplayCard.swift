import LidlessCore
import SwiftUI

/// The built-in screen: its brightness and Boost, or how to bring it back
/// while Desk Mode has it switched off.
struct BuiltInDisplayCard: View {
    @ObservedObject var deskMode: DeskModeStore
    let brightness: BrightnessStore

    var body: some View {
        let deskModeOn = deskMode.state.builtInDark
        VStack(alignment: .leading, spacing: 10) {
            BuiltInTitleRow(brightness: brightness, deskModeOn: deskModeOn)
            if deskModeOn {
                BuiltInOffNote(keys: deskMode.panicKeys)
            } else {
                BuiltInBrightnessControls(brightness: brightness)
            }
        }
        .glassCard()
    }
}

extension DeskModeState {
    /// True while Desk Mode has the built-in screen off or is switching it
    /// either way. `isOn` is false once a restore starts, but the panel stays
    /// dark until it finishes, so the popover keeps showing it as off.
    var builtInDark: Bool {
        switch self {
        case .on, .switching: true
        case .off, .unavailable: false
        }
    }
}

/// The canvas sets this card's title row on a 17.5 pt line and its 12 pt text
/// on 14 pt lines, a little under the shared `readout` and `small` tokens.
private enum CanvasLine {
    static let readout: CGFloat = 17.5 / 15
    static let small: CGFloat = 14 / 12
}

private struct BuiltInTitleRow: View {
    @ObservedObject var brightness: BrightnessStore
    let deskModeOn: Bool

    var body: some View {
        let scale = brightness.effectiveScale
        let boosted = !deskModeOn && scale.isBoosted(brightness.position)
        HStack(spacing: 8) {
            GlyphView(glyph: .laptop, size: 16, lineWidth: 1.8)
                .foregroundStyle(Palette.text3)
            Text("Built-in Display", comment: "Title of the popover's built-in display card")
                .lidlessStyle(.bodyStrong)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            readout(percent: scale.displayPercent(brightness.position))
                .lidlessStyle(.readout)
                .monospacedDigit()
                .foregroundStyle(deskModeOn ? Palette.readoutOff : (boosted ? Palette.goldDeep : Palette.textPrimary))
                .lineBox(.readout, lineHeight: CanvasLine.readout)
        }
        .accessibilityElement(children: .combine)
    }

    private func readout(percent: Int) -> Text {
        // Its own key, so translators can word a dark screen apart from Desk Mode's "Off".
        deskModeOn
            ? Text(String(localized: "BuiltInDisplay.Readout.Off", defaultValue: "Off", comment: "Readout at the right of the built-in display card's title while Desk Mode has switched the screen off (in place of a percentage). Describes the screen, not a setting."))
            : Text(percent, format: .percent)
    }
}

private struct BuiltInBrightnessControls: View {
    @ObservedObject var brightness: BrightnessStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let scale = brightness.effectiveScale
        let nits = scale.displayNits(brightness.position)
        VStack(alignment: .leading, spacing: 10) {
            BoostSlider(
                position: $brightness.position,
                scale: scale,
                label: Text("Built-in display brightness", comment: "VoiceOver label of the built-in brightness slider"),
                onEditingChanged: { brightness.setTracking($0) }
            )
            if scale.isBoosted(brightness.position) {
                Callout(
                    glyph: .flame,
                    message: Text("**Boost on · ≈ \(nits, format: .number) nits.** Uses more battery and heat. Steps back by itself if your Mac gets hot.", comment: "Boost callout in the popover; the variable is the estimated brightness in nits")
                )
                HStack(spacing: 8) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                            brightness.leaveBoost()
                        }
                    } label: {
                        Text("Back to 100%", comment: "Popover button that leaves Boost and sets the built-in screen to full normal brightness. The hint “or press brightness down” follows it on the same line, so the two read as one sentence: “[Back to 100%] or press brightness down”.")
                    }
                    .buttonStyle(SecondaryButtonStyle(size: .small))
                    Text("or press brightness down", comment: "Hint to the right of the “Back to 100%” button that finishes the sentence “[Back to 100%] or press brightness down”, so it starts in lowercase. If your language can’t continue the button’s label this way, translate it as a phrase that stands alone, such as “Or press the brightness-down key.” “brightness down” is the keyboard key that dims the screen (F1).")
                        .lidlessStyle(.caption)
                        .foregroundStyle(Palette.text4)
                }
            } else {
                hint(nits: nits, canBoost: scale.canBoost)
                    .lidlessStyle(.small)
                    .foregroundStyle(Palette.text3)
                    .lineBox(.small, lineHeight: CanvasLine.small)
            }
        }
    }

    private func hint(nits: Int, canBoost: Bool) -> Text {
        canBoost
            ? Text("≈ \(nits, format: .number) nits · Drag past the line to boost", comment: "Hint under the built-in brightness slider; the variable is the estimated brightness in nits")
            : Text("≈ \(nits, format: .number) nits", comment: "Hint under the built-in brightness slider when Boost is off; the variable is the estimated brightness in nits")
    }
}

/// "Off while Desk Mode is on. Bring it back: ⌃⌥⌘B"
private struct BuiltInOffNote: View {
    let keys: ShortcutLabels

    var body: some View {
        // CSS flex-wrap with a 6 pt gap; the keys never fit on the sentence's line.
        VStack(alignment: .leading, spacing: 6) {
            Text("Off while Desk Mode is on. Bring it back:", comment: "Built-in display card text while Desk Mode is on, followed by the panic shortcut")
                .lidlessStyle(.small)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                .lineBox(.small, lineHeight: CanvasLine.small)
            KeyCombo(keys: keys, size: .small)
        }
        .accessibilityElement(children: .combine)
    }
}
