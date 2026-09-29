import AppKit
import LidlessCore
import SwiftUI

/// Settings › Brightness (design-spec §7.3, `Settings2-Brightness`): the Boost
/// ceiling hero, guard rails, the brightness key and which screens can boost.
///
/// Each part observes only what it shows: the preferences for the controls,
/// `BrightnessStore` for the panel's normal maximum, `SystemStore` for the
/// screens. The window supplies the content padding around the tab.
struct BrightnessTab: View {
    let model: AppModel
    let preferences: PreferencesStore
    let actions: SettingsActions

    init(model: AppModel, preferences: PreferencesStore, actions: SettingsActions) {
        self.model = model
        self.preferences = preferences
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: Spacing.settingsGridGap) {
            BoostCeilingHero(preferences: preferences, brightness: model.brightness)
            HStack(alignment: .top, spacing: Spacing.settingsGridGap) {
                GuardRailsCard(preferences: preferences)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                VStack(spacing: Spacing.settingsGridGap) {
                    BrightnessKeyCard(preferences: preferences, actions: actions)
                    YourScreensCard(system: model.system, brightness: model.brightness)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Hero

/// "BRIGHTNESS BOOST": the ceiling in nits, "Boost allowed" and the ceiling slider.
private struct BoostCeilingHero: View {
    @ObservedObject var preferences: PreferencesStore
    /// Only for the panel's normal maximum, which labels the slider and the helper.
    @ObservedObject var brightness: BrightnessStore

    var body: some View {
        let normalMax = brightness.scale.normalMaxNits
        // What the handle shows: the stored ceiling kept inside this panel's range.
        let ceiling = Int(CeilingSlider.displayedCeiling(preferences.boost.ceilingNits, normalMaxNits: normalMax).rounded())
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BRIGHTNESS BOOST", comment: "Overline of the Settings › Brightness hero, uppercase by design")
                        .lidlessStyle(.overlineHero)
                        .foregroundStyle(Palette.gold)
                        .lineBox(.overlineHero)
                    headline(ceiling: ceiling, normalMax: normalMax)
                        .accessibilityAddTraits(.isHeader)
                    Text("Drag the handle to set how bright Boost can go. Normal brightness stops near \(Int(normalMax.rounded()), format: .number).", comment: "Helper under the Boost ceiling in Settings › Brightness. The variable is this Mac's normal maximum brightness in nits, e.g. 600.")
                        .lidlessStyle(.body)
                        .foregroundStyle(Palette.textOnDark)
                        .lineBox(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Text("Boost allowed", comment: "Label of the switch that allows Brightness Boost, in the Settings › Brightness hero")
                        .lidlessStyle(.body)
                        .foregroundStyle(Palette.textOnDark2)
                        .accessibilityHidden(true)
                    Toggle(isOn: $preferences.boost.allowed) {
                        Text("Boost allowed", comment: "Accessibility label of the switch that allows Brightness Boost")
                    }
                    .toggleStyle(PillToggleStyle(size: .large, surface: .onDarkSettingsHero))
                }
                .fixedSize()
            }

            CeilingSlider(ceilingNits: $preferences.boost.ceilingNits, normalMaxNits: normalMax)
                .disabled(!preferences.boost.allowed)
        }
        .padding(EdgeInsets(top: 22, leading: 30, bottom: 24, trailing: 30))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The design's 244 is a minimum: longer languages can wrap the helper,
        // and the grid below (flexible, laid out after the hero) gives way.
        .frame(minHeight: 244, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background { HeroCardSurface(cornerRadius: Radius.heroSettings, elevation: .flat) }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Boost ceiling", comment: "Accessibility label of the Settings › Brightness hero"))
    }

    /// "≈ 1,000  nits max  · up to 167% brightness", on one baseline.
    private func headline(ceiling: Int, normalMax: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("≈ \(ceiling, format: .number)", comment: "The Boost ceiling in nits, big in the Settings › Brightness hero, e.g. ≈ 1,000")
                .lidlessStyle(.heroNumber)
                .monospacedDigit()
                .foregroundStyle(Palette.gold)
                .lineBox(.heroNumber, lineHeight: 1)
            Text("nits max", comment: "Unit after the big Boost ceiling number in Settings › Brightness")
                .lidlessStyle(.unitLabel)
                .foregroundStyle(Palette.textOnDark2)
            Text("· up to \(Self.percent(ceiling: ceiling, normalMax: normalMax), format: .percent) brightness", comment: "After the Boost ceiling in Settings › Brightness: the brightest Boost gets, as a percentage of normal maximum, e.g. · up to 167% brightness")
                .lidlessStyle(.body)
                .foregroundStyle(Palette.textOnDark)
        }
        .lineLimit(1)
        // Read "≈" and "·" as words, not symbols.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("About \(ceiling) nits max, up to \(Self.percent(ceiling: ceiling, normalMax: normalMax))% brightness", comment: "VoiceOver label of the Boost ceiling headline in Settings › Brightness. The first variable is the ceiling in nits (e.g. 1000), the second the brightest Boost gets as a percentage of normal maximum (e.g. 167)."))
    }

    /// The ceiling as a percentage of the panel's normal maximum (1,000 of 600 → 167).
    static func percent(ceiling: Int, normalMax: Double) -> Int {
        guard normalMax.isFinite, normalMax > 0 else { return 100 }
        return Int((Double(ceiling) / normalMax * 100).rounded())
    }
}

// MARK: - Guard rails

private struct GuardRailsCard: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        SettingsCard(title: Text("Guard rails", comment: "Card title in Settings › Brightness"), fillsHeight: true) {
            Text("Boost steps back by itself when it should.", comment: "Description of the Guard rails card in Settings › Brightness")
                .lidlessStyle(.description)
                .foregroundStyle(Palette.text4)
                .lineBox(.description)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -6)

            GuardRailRow(
                glyph: .thermometer,
                title: Text("Mac gets hot", comment: "Guard rail title in Settings › Brightness"),
                detail: Text("Pause at this heat level", comment: "Guard rail helper in Settings › Brightness, beside the heat level menu")
            ) {
                TokenMenu(
                    selection: $preferences.boost.pauseAtHeat,
                    options: BoostSettings.heatChoices,
                    label: { Text(Self.heatName($0)) },
                    size: .compact,
                    accessibilityLabel: Text("Heat level", comment: "Accessibility label of the heat level menu in Settings › Brightness; VoiceOver adds the chosen level"),
                    menuTitle: Self.heatName
                )
            }

            GuardRailRow(
                glyph: .battery,
                title: Text("Battery runs low", comment: "Guard rail title in Settings › Brightness"),
                detail: Text("Pause when below", comment: "Guard rail helper in Settings › Brightness, beside the battery level menu")
            ) {
                TokenMenu(
                    selection: $preferences.boost.pauseBelowBattery,
                    options: BoostSettings.batteryChoices.map { Optional($0) } + [nil],
                    label: { Text(Self.batteryName($0)) },
                    size: .compact,
                    accessibilityLabel: Text("Battery level", comment: "Accessibility label of the battery level menu in Settings › Brightness; VoiceOver adds the chosen level"),
                    menuTitle: Self.batteryName
                )
            }

            GuardRailRow(
                glyph: .moon,
                title: Text("Screen sleeps", comment: "Guard rail title in Settings › Brightness"),
                detail: Text("Wake up at 100%, not boosted", comment: "Guard rail helper in Settings › Brightness: after the screen sleeps, brightness comes back at 100% instead of boosted")
            ) {
                Toggle(isOn: $preferences.boost.wakeAtNormal) {
                    Text("Wake up at 100 percent", comment: "Accessibility label of the switch that ends Boost when the screen sleeps")
                }
                .toggleStyle(PillToggleStyle(size: .small))
            }
        }
    }

    /// Menu and pill titles: `NSMenu` items need strings.
    static func heatName(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: String(localized: "Heat.Normal", defaultValue: "Normal", comment: "Heat level option in Settings › Brightness › Guard rails (the Mac's normal temperature). A separate key from the slider's “Normal” brightness zone.")
        case .fair: String(localized: "Fair", comment: "Heat level option in Settings › Brightness › Guard rails")
        case .serious: String(localized: "Serious", comment: "Heat level option in Settings › Brightness › Guard rails")
        case .critical: String(localized: "Critical", comment: "Heat level option in Settings › Brightness › Guard rails")
        }
    }

    static func batteryName(_ percent: Int?) -> String {
        guard let percent else {
            return String(localized: "Never", comment: "Battery option in Settings › Brightness › Guard rails: Boost doesn't pause on low battery")
        }
        return percent.formatted(.percent)
    }
}

/// Icon tile · title and helper · control.
private struct GuardRailRow<Control: View>: View {
    let glyph: LidlessGlyph
    let title: Text
    let detail: Text
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            IconTile(glyph: glyph, style: .cream)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .lidlessStyle(.bodyStrong)
                    .foregroundStyle(Palette.textPrimary)
                    .lineBox(.bodyStrong)
                detail
                    .lidlessStyle(.helper)
                    .foregroundStyle(Palette.text4)
                    .lineBox(.helper)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            control()
                .fixedSize()
        }
    }
}

// MARK: - Brightness key

/// "Keep pressing to boost", the Input Monitoring note and the auto-brightness note.
private struct BrightnessKeyCard: View {
    @ObservedObject var preferences: PreferencesStore
    let actions: SettingsActions

    /// Input Monitoring as last read. `actions.keyPermission()` is a live read
    /// that nothing publishes, so it's read again when the card appears, when
    /// the switch changes and when the user comes back from System Settings.
    @State private var permission: InputMonitoringPermission?

    var body: some View {
        SettingsCard {
            HStack(spacing: 12) {
                F2KeyIcon()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep pressing to boost", comment: "Setting title in Settings › Brightness: the brightness-up key goes on into Boost at 100%")
                        .lidlessStyle(.bodyStrong)
                        .foregroundStyle(Palette.textPrimary)
                        .lineBox(.bodyStrong)
                    Text("At 100%, the brightness key keeps going into Boost.", comment: "Helper under Keep pressing to boost in Settings › Brightness")
                        .lidlessStyle(.helper)
                        .foregroundStyle(Palette.text4)
                        .lineBox(.helper, lineHeight: 1.35)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Toggle(isOn: keysIntoBoost) {
                    Text("Brightness key goes into Boost", comment: "Accessibility label of the Keep pressing to boost switch")
                }
                .toggleStyle(PillToggleStyle(size: .small))
                .fixedSize()
            }

            if preferences.boost.keysIntoBoost, permission == .denied {
                // Not designed: styled like the auto-brightness note below.
                NoteCallout {
                    NoteWithLink(
                        text: Text("The brightness key needs Input Monitoring.", comment: "Note in Settings › Brightness when Keep pressing to boost is on but Lidless may not see key presses (Input Monitoring not allowed)"),
                        link: Text("Open Input Monitoring settings", comment: "Link in Settings › Brightness that opens System Settings › Privacy & Security › Input Monitoring"),
                        action: actions.openInputMonitoringSettings
                    )
                }
            }

            // Shown always, as designed: no store reports auto-brightness yet,
            // so it can't follow the setting (design-spec §10).
            NoteCallout {
                NoteWithLink(
                    text: Text("Auto-brightness can block Boost on some Macs.", comment: "Note under Keep pressing to boost in Settings › Brightness, followed by the Open Displays settings link"),
                    link: Text("Open Displays settings", comment: "Link in the auto-brightness note in Settings › Brightness: opens System Settings › Displays"),
                    action: actions.openDisplaysSettings
                )
            }
        }
        .onAppear {
            // With the switch on by default, the prompt never came from turning
            // it on: ask when the tab shows it on and macOS hasn't been asked.
            // The request shows the system prompt at most once per launch.
            if preferences.boost.keysIntoBoost, actions.keyPermission() == .notDetermined {
                actions.requestKeyPermission()
            }
            permission = actions.keyPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission = actions.keyPermission()
        }
    }

    /// Switching it on asks for Input Monitoring, which the key tap needs.
    private var keysIntoBoost: Binding<Bool> {
        Binding(
            get: { preferences.boost.keysIntoBoost },
            set: { isOn in
                let wasOn = preferences.boost.keysIntoBoost
                preferences.boost.keysIntoBoost = isOn
                if isOn, !wasOn { actions.requestKeyPermission() }
                permission = actions.keyPermission()
            }
        )
    }
}

/// A note's sentence followed by its link: "Auto-brightness can block Boost on
/// some Macs. Open Displays settings".
///
/// The link is a real button, so it's a Tab stop with keyboard navigation on,
/// VoiceOver lists it as a link, and it darkens on hover like the design's
/// `a:hover`. The sentence and the link are two whole strings for translators
/// (a statement, then a command), so no language has to split a sentence
/// around a link. They share a line when both fit; otherwise the link goes on
/// the next line, whole (the design wraps inside it at 1x widths; the height
/// is the same two lines).
private struct NoteWithLink: View {
    let text: Text
    let link: Text
    let action: () -> Void

    /// `lineBox(.small, lineHeight: 1.4)`'s line spacing, between the two lines.
    private static let lineGap = 1.4 * TypeStyle.small.size - TypeStyle.small.nativeLineHeight

    var body: some View {
        if #available(macOS 13, *) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    // The space belongs to the sentence, as in the design's markup.
                    (text + Text(verbatim: " ")).fixedSize()
                    linkButton.fixedSize()
                }
                stacked
            }
        } else {
            stacked
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: Self.lineGap) {
            text.fixedSize(horizontal: false, vertical: true)
            linkButton.fixedSize(horizontal: false, vertical: true)
        }
    }

    private var linkButton: some View {
        Button(action: action) {
            link.font(TypeStyle.smallStrong.font)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(NoteLinkButtonStyle())
    }
}

/// The design's inline link: #8A5A00 semibold, #5A3B00 on hover and while
/// pressed (`a:hover`, design-spec §1.1 `brown`). Settings isn't designed in
/// dark: there the link is `goldDeep`'s #FFD466 and hover lightens it
/// (`sunWhite`), since brown would vanish on the dark callout.
private struct NoteLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NoteLink(configuration: configuration)
    }

    private struct NoteLink: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.colorScheme) private var colorScheme
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovered || configuration.isPressed ? hoverColor : Palette.goldDeep)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .accessibilityAddTraits(.isLink)
        }

        private var hoverColor: Color {
            colorScheme == .dark ? Palette.sunWhite : Palette.brown
        }
    }
}

// MARK: - Your screens

/// One row per connected screen: the built-in can boost, externals can't.
private struct YourScreensCard: View {
    @ObservedObject var system: SystemStore
    /// Whether the built-in has a Boost range (XDR panel, no reference preset).
    @ObservedObject var brightness: BrightnessStore

    var body: some View {
        SettingsCard(
            title: Text("Your screens", comment: "Card title in Settings › Brightness"),
            spacing: 10,
            padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18),
            fillsHeight: true
        ) {
            if let builtIn = system.builtIn {
                ScreenRow(glyph: .laptop, name: builtIn.name, canBoost: brightness.scale.canBoost)
            }
            ForEach(system.externals) { display in
                ScreenRow(glyph: .monitor, name: display.name, canBoost: false)
            }
        }
    }
}

private struct ScreenRow: View {
    let glyph: LidlessGlyph
    let name: String
    let canBoost: Bool

    var body: some View {
        HStack(spacing: 10) {
            GlyphView(glyph: glyph, size: 18)
                .foregroundStyle(Palette.rowIcon)
            Text(name)
                .lidlessStyle(.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canBoost {
                Badge(text: Text("Boost ready", comment: "Badge on the built-in screen in Settings › Brightness › Your screens"), style: .gold)
            } else {
                Badge(text: Text("Normal only", comment: "Badge on a screen that can't boost in Settings › Brightness › Your screens"), style: .neutral)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Brightness") {
    let model = SampleData.deskSetup()
    BrightnessTab(model: model, preferences: model.preferences, actions: SettingsActions())
        .padding(EdgeInsets(top: 0, leading: 18, bottom: 18, trailing: 18))
        .frame(width: 880, height: 664)
        .background { SettingsWindowBackground() }
}

#Preview("Brightness, Input Monitoring denied") {
    let model = SampleData.deskSetup()
    BrightnessTab(model: model, preferences: model.preferences, actions: SettingsActions(keyPermission: { .denied }))
        .padding(EdgeInsets(top: 0, leading: 18, bottom: 18, trailing: 18))
        .frame(width: 880, height: 664)
        .background { SettingsWindowBackground() }
}
