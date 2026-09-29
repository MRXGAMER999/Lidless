import LidlessCore
import SwiftUI

/// App icon, name, one-line status and the settings button.
struct PopoverHeader: View {
    let system: SystemStore
    let deskMode: DeskModeStore
    let brightness: BrightnessStore
    let openSettings: (SettingsTab) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(.appIconArt)
                .resizable()
                .frame(width: 34, height: 34)
                // The canvas's drop-shadow(0 2px 4px): a drop-shadow blur is a
                // standard deviation, not box-shadow's 2σ, so it isn't `.css(blur:)`.
                .lidlessShadow(ShadowLayer(color: Palette.appIconShadow, radius: 4, y: 2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Lidless")
                    .lidlessStyle(.appTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineBox(.appTitle)
                HeaderStatusLine(system: system, deskMode: deskMode)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // "Lidless, Lid open, 3 displays, On power": one stop.
            .accessibilityElement(children: .combine)
            HeaderSettingsButton(deskMode: deskMode, brightness: brightness, openSettings: openSettings)
        }
        .padding(EdgeInsets(top: 2, leading: 4, bottom: 0, trailing: 2))
    }
}

/// "Lid open · 3 displays · On power".
private struct HeaderStatusLine: View {
    @ObservedObject var system: SystemStore
    @ObservedObject var deskMode: DeskModeStore
    @Environment(\.locale) private var locale

    var body: some View {
        let segments = StatusLine.segments(
            lid: system.lid,
            externalCount: system.externals.count,
            builtInLit: !deskMode.state.builtInDark,
            power: system.power
        )
        Text(verbatim: segments.map(\.localizedText).joined(separator: " · "))
            .lidlessStyle(.caption)
            .foregroundStyle(Palette.text3)
            .lineLimit(1)
            .lineBox(.caption)
            // A list rather than " · ", which VoiceOver may read as "middle dot".
            .accessibilityLabel(Text(verbatim: StatusSegment.spokenList(segments, locale: locale)))
    }
}

private struct HeaderSettingsButton: View {
    // Not observed: only the click reads them, so slider drags don't redraw the header.
    let deskMode: DeskModeStore
    let brightness: BrightnessStore
    let openSettings: (SettingsTab) -> Void

    var body: some View {
        Button {
            openSettings(SettingsTab.forPopoverButton(boosted: brightness.isBoosted, deskModeAvailable: deskMode.state.isAvailable))
        } label: {
            GlyphView(glyph: .sliders, size: 16, lineWidth: 1.9)
        }
        .buttonStyle(CircleIconButtonStyle())
        .accessibilityLabel(Text("Open Settings", comment: "VoiceOver label of the popover's settings button"))
        .help(Text("Settings", comment: "Tooltip of the popover's settings button"))
    }
}

extension StatusSegment {
    /// The status line as VoiceOver reads it: "Lid open, 3 displays, On power".
    static func spokenList(_ segments: [StatusSegment], locale: Locale = .current) -> String {
        segments.map(\.localizedText).formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    var localizedText: String {
        switch self {
        case .lidOpen:
            String(localized: "Lid open", comment: "Popover status line segment")
        case .lidClosed:
            String(localized: "Lid closed", comment: "Popover status line segment")
        case .builtInOnly:
            String(localized: "Built-in only", comment: "Popover status line segment: no external displays")
        case .builtInOff:
            String(localized: "Built-in off", comment: "Popover status line segment: the built-in screen is off")
        case .displayCount(let count):
            String(localized: "\(count) displays", comment: "Popover status line segment: number of lit displays")
        case .onPower:
            String(localized: "On power", comment: "Popover status line segment")
        case .onBattery(let percent?):
            String(localized: "On battery (\(percent, format: .percent))", comment: "Popover status line segment; the variable is the battery charge, e.g. 64%")
        case .onBattery(nil):
            String(localized: "On battery", comment: "Popover status line segment when the charge is unknown")
        }
    }
}
