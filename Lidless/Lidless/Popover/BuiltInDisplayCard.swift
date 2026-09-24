import LidlessCore
import SwiftUI

/// The built-in screen: its brightness and Boost, or how to bring it back
/// while Desk Mode has it switched off.
struct BuiltInDisplayCard: View {
    @ObservedObject var deskMode: DeskModeStore
    let brightness: BrightnessStore
    let boost: BoostStatusStore

    var body: some View {
        let deskModeOn = deskMode.state.builtInDark
        VStack(alignment: .leading, spacing: 10) {
            BuiltInTitleRow(brightness: brightness, deskModeOn: deskModeOn)
            if deskModeOn {
                BuiltInOffNote(keys: deskMode.panicKeys)
            } else {
                BuiltInBrightnessControls(brightness: brightness, boost: boost)
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
    @ObservedObject var boost: BoostStatusStore
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
                if let caption = BoostCaption(boost.status) {
                    Callout(glyph: caption.glyph, message: caption.message)
                } else {
                    let boostedNits = Self.boostNits(status: boost.status, scale: scale) ?? nits
                    Callout(
                        glyph: .flame,
                        message: Text("**Boost on · ≈ \(boostedNits, format: .number) nits.** Uses more battery and heat. Steps back by itself if your Mac gets hot.", comment: "Boost callout in the popover; the variable is the estimated brightness in nits")
                    )
                }
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

    /// What the screen shows while Boost is on: the normal maximum times the
    /// factor actually on screen, which can be below what the slider asks for
    /// (headroom or thermal caps). Rounded like `BrightnessScale.displayNits`.
    /// Nil unless Boost is on; the slider's figure is used then.
    static func boostNits(status: BoostStatus, scale: BrightnessScale) -> Int? {
        guard case .on(let factor) = status, factor.isFinite else { return nil }
        let nits = scale.normalMaxNits * max(factor, 1)
        return Int((nits / 10).rounded()) * 10
    }

    private func hint(nits: Int, canBoost: Bool) -> Text {
        canBoost
            ? Text("≈ \(nits, format: .number) nits · Drag past the line to boost", comment: "Hint under the built-in brightness slider; the variable is the estimated brightness in nits")
            : Text("≈ \(nits, format: .number) nits", comment: "Hint under the built-in brightness slider when Boost is off; the variable is the estimated brightness in nits")
    }
}

/// The one-line callout that stands in for "Boost on · ≈ N nits" while the
/// slider asks for Boost but the screen isn't boosted: waiting for headroom,
/// paused by a guard rail, or refused by macOS. Not designed: it reuses the
/// Boost callout with a single short line. Nil when Boost is on (or off), so
/// the designed callout shows.
private struct BoostCaption {
    let glyph: LidlessGlyph
    let message: Text

    init?(_ status: BoostStatus) {
        switch status {
        case .off, .on:
            return nil
        case .engaging:
            glyph = .flame
            message = Text("Boosting…", comment: "Popover Boost callout while Lidless waits for macOS to let the built-in screen go brighter (usually under a second)")
        case .unavailable:
            glyph = .info
            message = Text("macOS isn't allowing Boost right now.", comment: "Popover Boost callout when macOS gave the screen no extra brightness after several tries; Boost tries again the next time the slider moves into Boost")
        case .blocked(let block):
            let paused = Self.paused(block)
            glyph = paused.glyph
            message = paused.message
        }
    }

    private static func paused(_ block: BoostBlock) -> (glyph: LidlessGlyph, message: Text) {
        switch block {
        case .hot:
            (.thermometer, Text("Paused: your Mac is hot.", comment: "Popover Boost callout: Boost stepped back because the Mac reached the heat level set in Settings; it comes back by itself when the Mac cools down"))
        case .lowBattery:
            (.battery, Text("Paused: battery is low.", comment: "Popover Boost callout: Boost stepped back because the battery fell below the level set in Settings; it comes back by itself when charging"))
        case .lowPower:
            (.battery, Text("Paused: Low Power Mode is on.", comment: "Popover Boost callout: Boost is paused while macOS Low Power Mode is on. “Low Power Mode” is the macOS feature name; use Apple’s translation."))
        case .builtInUnavailable:
            (.info, Text("Paused while the built-in screen is off.", comment: "Popover Boost callout: Boost is paused because the lid is closed or the built-in screen is switched off"))
        case .screenAsleepOrLocked:
            (.moon, Text("Paused while the screen sleeps.", comment: "Popover Boost callout: Boost is paused while the displays sleep or the screen is locked"))
        case .reconfiguring:
            (.info, Text("Paused while displays change.", comment: "Popover Boost callout: Boost is paused for a few seconds while a display is connected, disconnected or rearranged"))
        case .hdrSuppressed:
            (.info, Text("Paused: macOS is limiting bright content.", comment: "Popover Boost callout: macOS asked apps to hold back HDR (extra-bright) content for now, so Boost is paused"))
        case .notAllowed:
            (.info, Text("Boost is turned off in Settings.", comment: "Popover Boost callout: “Boost allowed” is off in Settings › Brightness"))
        case .unsupported:
            (.info, Text("This screen can't boost right now.", comment: "Popover Boost callout: the built-in screen has no extra brightness to give, for example because a fixed reference preset is selected in System Settings › Displays"))
        }
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
