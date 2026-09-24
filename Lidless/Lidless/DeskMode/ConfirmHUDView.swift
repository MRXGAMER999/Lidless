import AppKit
import LidlessCore
import SwiftUI

/// The HUD button that has keyboard focus. The panel moves it with Tab,
/// whatever the Full Keyboard Access setting, and Space presses it.
enum ConfirmHUDButton: Equatable, Sendable {
    case turnBackOn
    case keepOff
}

/// The keep-or-revert prompt (design-spec §6, Confirm-HUD.dc.html).
///
/// Shows the countdown; it decides nothing. The Desk Mode machine's ticks
/// turn the screen back on at the deadline, whatever this view shows.
/// Times are `ProcessInfo.systemUptime` seconds, the machine's clock.
///
/// Keyboard handling lives in `ConfirmationPanel`: Escape turns the screen
/// back on, Tab moves `focus`, and Return does nothing, so nobody can keep
/// the screen off by accident.
struct ConfirmHUDView: View {
    let countdown: ConfirmationCountdown
    let panicKeys: ShortcutLabels
    var focus: ConfirmHUDButton?
    let revert: () -> Void
    let keep: () -> Void
    /// Speaks a VoiceOver announcement.
    var announce: (String) -> Void = { ConfirmHUDView.postAnnouncement($0, from: NSApp as Any) }

    static let cardWidth: CGFloat = 380

    var body: some View {
        VStack(spacing: 12) {
            HUDIcon()
            Text(Self.title)
                .lidlessStyle(.hudTitle)
                .foregroundStyle(Palette.textPrimary)
                .lineBox(.hudTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            CountdownMessage(countdown: countdown, announce: announce)
            CountdownBar(countdown: countdown)
            HUDButtons(focus: focus, revert: revert, keep: keep)
                .padding(.top, 4)
            PanicKeyFooter(keys: panicKeys)
        }
        .multilineTextAlignment(.center)
        .padding(24 + Spacing.hairline)
        .frame(width: Self.cardWidth)
        .modifier(HUDChrome())
        // role="alertdialog". Its name is the title, read once as the header
        // (and as the panel's own title): a group label would read it twice.
        .accessibilityElement(children: .contain)
    }
}

extension ConfirmHUDView {
    static var title: String {
        String(localized: "Built-in screen is off", comment: "Title of the keep-or-revert prompt shown after Desk Mode turned the built-in screen off")
    }

    /// The body sentence; the count is bold in the design. Automatic grammar
    /// agreement makes "1 second" singular without plural catalog variants.
    static func message(secondsLeft: Int) -> AttributedString {
        AttributedString(
            localized: "Can you see this? Keep it off, or it turns back on in **^[\(secondsLeft) second](inflect: true)**.",
            comment: "Keep-or-revert prompt text under the title. The variable is the whole seconds left before the built-in screen turns back on; the part between ** is bold, and ^[…](inflect: true) makes the noun agree with the number."
        )
    }

    static func tickAnnouncement(secondsLeft: Int) -> String {
        let text = AttributedString(
            localized: "Turns back on in ^[\(secondsLeft) second](inflect: true).",
            comment: "VoiceOver announcement while the keep-or-revert prompt counts down. The variable is the whole seconds left before the built-in screen turns back on; ^[…](inflect: true) makes the noun agree with the number."
        )
        return String(text.characters)
    }

    /// A high-priority announcement, so it interrupts whatever VoiceOver is
    /// reading: the user may not be looking at this screen.
    static func postAnnouncement(_ text: String, from element: Any) {
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

// MARK: - Parts

/// 56 pt ink circle with the gold `laptopSlash` glyph (`shadowHUDIcon`).
private struct HUDIcon: View {
    var body: some View {
        GlyphView(glyph: .laptopSlash, size: 28, lineWidth: 1.8)
            .foregroundStyle(Palette.gold)
            .frame(width: 56, height: 56)
            .background {
                Circle()
                    .fill(Palette.heroBackground)
                    .overlay { CapsuleInsetHighlight(color: Palette.white.opacity(0.12), dy: 1) }
                    .lidlessShadow(.css(y: 6, blur: 16, color: HUDPalette.iconShadow))
            }
            .accessibilityHidden(true)
    }
}

/// The sentence with the live count, redrawn at each whole second.
private struct CountdownMessage: View {
    let countdown: ConfirmationCountdown
    let announce: (String) -> Void

    var body: some View {
        TimelineView(CountdownSchedule(countdown: countdown)) { _ in
            CountdownSentence(
                secondsLeft: countdown.secondsLeft(now: ProcessInfo.processInfo.systemUptime),
                announce: announce
            )
        }
    }
}

private struct CountdownSentence: View {
    let secondsLeft: Int
    let announce: (String) -> Void
    @State private var hasAnnounced = false

    var body: some View {
        // Never "0 seconds": the panel hides at the deadline, and a redraw
        // that lands just before it still reads 1.
        Text(ConfirmHUDView.message(secondsLeft: max(1, secondsLeft)))
            .lidlessStyle(.body)
            .monospacedDigit()
            .foregroundStyle(Palette.text2)
            .lineBox(.body, lineHeight: 1.45)
            .fixedSize(horizontal: false, vertical: true)
            .task(id: secondsLeft) { announceIfNeeded() }
    }

    /// The panel shows up without taking focus, so VoiceOver wouldn't read it:
    /// the first announcement says what it is, later ones only the count.
    private func announceIfNeeded() {
        guard secondsLeft > 0 else { return }
        if !hasAnnounced {
            hasAnnounced = true
            let sentence = String(ConfirmHUDView.message(secondsLeft: secondsLeft).characters)
            announce(ConfirmHUDView.title + "\n" + sentence)
        } else if ConfirmationCountdown.shouldAnnounce(secondsLeft: secondsLeft) {
            announce(ConfirmHUDView.tickAnnouncement(secondsLeft: secondsLeft))
        }
    }
}

/// `CountdownBar`: remaining over total, draining linearly. With Reduce
/// Motion it steps once a second instead of moving continuously.
private struct CountdownBar: View {
    let countdown: ConfirmationCountdown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            TimelineView(CountdownSchedule(countdown: countdown)) { _ in
                CountdownBarTrack(fraction: steppedFraction)
            }
        } else {
            // Paused once over: the panel hides by expiring the countdown, and
            // an ordered-out window must not keep redrawing at 30 Hz.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: countdown.isExpired(now: ProcessInfo.processInfo.systemUptime))) { _ in
                CountdownBarTrack(fraction: countdown.fraction(now: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    private var steppedFraction: Double {
        guard countdown.total > 0 else { return 0 }
        let left = countdown.secondsLeft(now: ProcessInfo.processInfo.systemUptime)
        return min(1, Double(left) / countdown.total)
    }
}

private struct CountdownBarTrack: View {
    let fraction: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .circular)
        shape.fill(Palette.track)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    shape.fill(Palette.gold)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            // The sentence above already reads the count.
            .accessibilityHidden(true)
    }
}

/// "Turn Back On" and "Keep Off", equal widths. Neither is a default button.
private struct HUDButtons: View {
    let focus: ConfirmHUDButton?
    let revert: () -> Void
    let keep: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: revert) {
                Text("Turn Back On", comment: "Keep-or-revert prompt button that turns the built-in screen back on now")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HUDSecondaryButtonStyle())
            .focusable(false)
            .modifier(HUDFocusRing(isFocused: focus == .turnBackOn))

            Button(action: keep) {
                Text("Keep Off", comment: "Keep-or-revert prompt button that keeps the built-in screen off")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(size: .large))
            .focusable(false)
            .modifier(HUDFocusRing(isFocused: focus == .keepOff))
        }
    }
}

/// The HUD's "Turn Back On": `SecondaryButtonStyle(.large)` on a 0.85 white fill.
private struct HUDSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeStyle.bodyStrong.font)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 20 + Spacing.hairline)
            .frame(height: 38)
            .background {
                Capsule()
                    .fill(HUDPalette.secondaryFill)
                    .overlay { Capsule().strokeBorder(Palette.secondaryButtonBorder, lineWidth: 1) }
                    .lidlessShadow(.css(y: 1, blur: 3, color: Palette.secondaryButtonShadow))
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The system focus ring around a capsule button. The panel owns focus, so
/// SwiftUI's own ring is off (`focusable(false)`) and this one stands in.
private struct HUDFocusRing: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content.overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                .padding(-3)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

/// "Panic key, anytime" and the current panic shortcut, keycaps 4 pt apart.
private struct PanicKeyFooter: View {
    let keys: ShortcutLabels

    var body: some View {
        let caps = keys.keycaps
        HStack(spacing: 4) {
            Text("Panic key, anytime", comment: "Keep-or-revert prompt footer, followed by the panic shortcut's keys")
                .lidlessStyle(.small)
                .foregroundStyle(Palette.text3)
                .padding(.trailing, 4)
            ForEach(Array(caps.enumerated()), id: \.element) { item in
                KeyCap(label: item.element, size: .small, isAccent: item.offset == caps.count - 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Panic key, anytime", comment: "Keep-or-revert prompt footer, followed by the panic shortcut's keys"))
        .accessibilityValue(Text(verbatim: keys.spokenName))
    }
}

// MARK: - Glass

/// `hudGlass` and `shadowHUD` (design-spec §1.6–1.7): the popover's recipe
/// with a 0.62 wash, a 0.3 bottom highlight and a `0 24px 60px` drop.
///
/// The blur itself comes from the panel's `NSVisualEffectView`, kept active
/// while Lidless is in the background, which it nearly always is.
private struct HUDChrome: ViewModifier {
    func body(content: Content) -> some View {
        let radius = Radius.hud
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        content
            .background { HUDWash(shape: shape) }
            .overlay {
                ZStack {
                    InsetHighlight(cornerRadius: radius - 1, color: Palette.popoverInsetTop, dy: 1.5, blur: 1)
                        .padding(Spacing.hairline)
                    InsetHighlight(cornerRadius: radius - 1, color: HUDPalette.insetBottom, dy: -1, blur: 1)
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
                OuterShadow(cornerRadius: radius, far: .css(y: 24, blur: 60, color: HUDPalette.shadow))
            }
    }
}

private struct HUDWash: View {
    let shape: RoundedRectangle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(macOS 26, *) {
            // As the popover on 26+: Liquid Glass at partial strength over the
            // material, and a lighter wash because both layers already tint.
            ZStack {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .opacity(colorScheme == .dark ? 0.3 : 0.6)
                shape.fill(Palette.popoverGlassWash)
            }
            .clipShape(shape)
        } else {
            shape.fill(HUDPalette.wash)
        }
    }
}

/// HUD-only colours (design-spec §1.1, §1.6). The HUD has no dark design;
/// dark values follow the popover's dark recipe.
private nonisolated enum HUDPalette {
    static let wash = adaptive("hudWash", light: srgb(0xFFFFFF, 0.62), dark: srgb(0x1C1C24, 0.64))
    static let insetBottom = adaptive("hudInsetBottom", light: srgb(0xFFFFFF, 0.3), dark: srgb(0xFFFFFF, 0.06))
    static let shadow = adaptive("hudShadow", light: srgb(0x3C280A, 0.3), dark: srgb(0x000000, 0.5))
    static let secondaryFill = adaptive("hudSecondaryFill", light: srgb(0xFFFFFF, 0.85), dark: srgb(0xFFFFFF, 0.12))
    static let iconShadow = Color(nsColor: srgb(0x141B24, 0.35))

    private static func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    // Nonisolated on purpose, as in `Palette`: AppKit may call the provider
    // off the main thread while drawing.
    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> Color {
        let color = NSColor(name: NSColor.Name("Lidless." + name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
        return Color(nsColor: color)
    }
}

// MARK: - Timing

/// Fires as each whole second of the countdown ticks over (plus a little, so
/// the rounded-up count has changed by then), down to 1. Not at the deadline
/// itself: the prompt goes away then, and must not flash "0 seconds" first.
/// Keyed to `systemUptime`, like the machine, rather than the wall clock.
private nonisolated struct CountdownSchedule: TimelineSchedule {
    let countdown: ConfirmationCountdown

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {
        let left = countdown.deadline - ProcessInfo.processInfo.systemUptime
        guard left > 0 else { return [startDate] }
        let deadline = Date().addingTimeInterval(left + Self.lag)
        let boundaries = (1..<Int(left.rounded(.up))).reversed().map { deadline.addingTimeInterval(-Double($0)) }
        return [startDate] + boundaries.filter { $0 > startDate }
    }

    private static let lag: TimeInterval = 0.02
}

// MARK: - Preview

#Preview("Keep or revert") {
    ZStack {
        Color(nsColor: NSColor(srgbRed: 0xEF / 255, green: 0xE7 / 255, blue: 0xDA / 255, alpha: 1))
        Circle().fill(Color(nsColor: NSColor(srgbRed: 1, green: 0xC9 / 255, blue: 0x4D / 255, alpha: 1)))
            .frame(width: 280, height: 280).position(x: 260, y: 100)
        Circle().fill(Color(nsColor: NSColor(srgbRed: 0x7F / 255, green: 0x9B / 255, blue: 0xE0 / 255, alpha: 1)))
            .frame(width: 300, height: 300).position(x: 530, y: 330)
        Circle().fill(Color(nsColor: NSColor(srgbRed: 1, green: 0x94 / 255, blue: 0x70 / 255, alpha: 1)))
            .frame(width: 220, height: 220).position(x: 70, y: 350)
        ConfirmHUDView(
            countdown: ConfirmationCountdown(deadline: ProcessInfo.processInfo.systemUptime + 12, total: 15),
            panicKeys: ShortcutLabels(.defaultPanic, keyLabel: KeyShortcut.defaultPanic.keyLabel),
            revert: {},
            keep: {},
            announce: { _ in }
        )
        // The panel's NSVisualEffectView, which previews don't have.
        .background {
            RoundedRectangle(cornerRadius: Radius.hud, style: .circular).fill(.ultraThinMaterial)
        }
    }
    .frame(width: 720, height: 420)
    .preferredColorScheme(.light)
}
