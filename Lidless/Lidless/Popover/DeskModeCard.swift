import AppKit
import LidlessCore
import SwiftUI

/// The dark Desk Mode card: illustration, state, and the switch.
struct DeskModeCard: View {
    @ObservedObject var deskMode: DeskModeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = deskMode.state
        // The dark board adds a 1 pt gold border inside the card's box.
        let border: CGFloat = colorScheme == .dark ? Spacing.hairline : 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DeskMiniArt(
                    deskModeOn: state.isOn,
                    needsDisplay: state == .unavailable(.needsDisplay),
                    darkAppearance: colorScheme == .dark
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state)
                .accessibilityHidden(true)
                DeskModeCopy(state: state)
                Toggle(isOn: $deskMode.isOn) {
                    state.isAvailable
                        ? Text("Desk Mode", comment: "VoiceOver label of the Desk Mode switch")
                        : Text("Desk Mode, unavailable", comment: "VoiceOver label of the Desk Mode switch when it can't be used")
                }
                .toggleStyle(PillToggleStyle(size: .medium, surface: .onDark))
                .disabled(!state.isAvailable || state.isSwitching)
            }
            if case .on(let since, .automatic(let displayName)) = state {
                DeskModeTriggerNote(since: since, displayName: displayName)
            }
        }
        .padding(EdgeInsets(top: 12 + border, leading: 12 + border, bottom: 12 + border, trailing: 14 + border))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { HeroCardSurface(cornerRadius: Radius.card, elevation: .popover) }
    }
}

private struct DeskModeCopy: View {
    let state: DeskModeState

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DESK MODE", comment: "Overline of the popover's Desk Mode card")
                .lidlessStyle(.overlineCard)
                .foregroundStyle(Palette.gold)
                .lineBox(.overlineCard)
                // SwiftUI sets 10 pt text half a point lower in its line box than WebKit.
                .offset(y: -0.5)
            title
                .lidlessStyle(.appTitle)
                // The light card sets white; the dark one inherits the popover's text colour.
                .foregroundStyle(colorScheme == .dark ? Palette.textPrimary : Palette.white)
                .lineBox(.appTitle)
            detail
                .lidlessStyle(.helper)
                .foregroundStyle(Palette.textOnDark)
                .lineBox(.helper, lineHeight: 1.3)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The canvas's row is half a point taller than these line boxes (2x
        // renders); the extra sits below the text and moves the row's centre.
        .padding(.bottom, 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        // Own keys, so a bare "On"/"Off" elsewhere (the built-in readout) can be translated differently.
        switch state {
        case .off:
            Text(String(localized: "DeskMode.Title.Off", defaultValue: "Off", comment: "Desk Mode card title: Desk Mode (the setting) is off. Shown large above the card's description."))
        case .on:
            Text(String(localized: "DeskMode.Title.On", defaultValue: "On", comment: "Desk Mode card title: Desk Mode (the setting) is on. Shown large above the card's description."))
        case .switching(toOn: true):
            Text("Turning on…", comment: "Desk Mode card title while the built-in screen switches off")
        case .switching(toOn: false):
            Text("Turning off…", comment: "Desk Mode card title while the built-in screen comes back")
        case .unavailable(.needsDisplay):
            Text("Needs a display", comment: "Desk Mode card title when no external display is connected")
        case .unavailable(.lidClosed):
            Text("Lid closed", comment: "Desk Mode card title when the MacBook lid is closed")
        case .unavailable(.unsupportedMac), .unavailable(.unsupportedSystem):
            Text("Not available", comment: "Desk Mode card title when this Mac or macOS can't use Desk Mode")
        }
    }

    private var detail: Text {
        switch state {
        case .off:
            Text("Turn the built-in screen off. The lid stays open for cooling.", comment: "Desk Mode card description when off")
        case .on:
            Text("Built-in screen is off. Lid stays open to keep it cool.", comment: "Desk Mode card description when on")
        case .switching(toOn: true):
            Text("The built-in screen is switching off.", comment: "Desk Mode card description while turning on")
        case .switching(toOn: false):
            Text("Bringing the built-in screen back.", comment: "Desk Mode card description while turning off")
        case .unavailable(.needsDisplay):
            Text("Plug in a monitor and Lidless can turn this screen off.", comment: "Desk Mode card description when no external display is connected")
        case .unavailable(.lidClosed):
            Text("Open the lid and Lidless can turn this screen off.", comment: "Desk Mode card description when the lid is closed")
        case .unavailable(.unsupportedMac):
            Text("This Mac can't bring its screen back reliably, so Lidless leaves it on.", comment: "Desk Mode card description on unsupported Macs")
        case .unavailable(.unsupportedSystem):
            Text("This version of macOS can't turn the screen off safely.", comment: "Desk Mode card description on unsupported macOS versions")
        }
    }
}

/// "Turned on by itself at 9:14 AM, when LG UltraFine 27 connected."
private struct DeskModeTriggerNote: View {
    let since: Date
    let displayName: String

    var body: some View {
        let note = String(localized: "Turned on by itself at \(since, format: .dateTime.hour().minute()), when \(displayName) connected.", comment: "Desk Mode card footer after the automatic rule turned it on; the variables are the time and the display name")
        Group {
            if #available(macOS 13, *) {
                GreedyWrapLabel(string: note)
            } else {
                Text(verbatim: note)
                    .lidlessStyle(.helper)
                    .foregroundStyle(Palette.textOnDark)
                    .lineBox(.helper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // CSS: 1 pt top border, then 8 pt padding.
        .padding(.top, 8 + Spacing.hairline)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.onDarkHairline)
                .frame(height: 1)
        }
    }
}

/// Helper text wrapped greedily, as the canvas does. SwiftUI's `Text` moves a
/// word down rather than leave one alone on the last line ("… UltraFine /
/// 27 connected."); AppKit drops that when the line-break strategy is empty.
@available(macOS 13, *)
private struct GreedyWrapLabel: NSViewRepresentable {
    let string: String

    static let drawingOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    /// TextKit sets 11.5 pt lines 13 pt apart with the baseline 11 pt down. The
    /// canvas (Popover-DeskDark at 2x) has the same baselines 13.5 pt apart, so
    /// the extra half point goes below every line, the last one included.
    private static let lineGap: CGFloat = 0.5

    private var text: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakStrategy = []
        paragraph.lineSpacing = Self.lineGap
        return NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: TypeStyle.helper.size),
            .foregroundColor: NSColor(Palette.textOnDark),
            .paragraphStyle: paragraph,
        ])
    }

    func makeNSView(context: Context) -> TextView {
        TextView()
    }

    func updateNSView(_ view: TextView, context: Context) {
        view.text = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TextView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let bounds = text.boundingRect(
            with: CGSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: Self.drawingOptions
        )
        return CGSize(width: width ?? ceil(bounds.width), height: bounds.height + Self.lineGap)
    }

    final class TextView: NSView {
        var text = NSAttributedString() {
            didSet {
                guard text != oldValue else { return }
                needsDisplay = true
            }
        }

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            text.draw(with: bounds, options: GreedyWrapLabel.drawingOptions)
        }

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
        override func accessibilityValue() -> Any? { text.string }
    }
}
