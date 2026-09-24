import AppKit
import LidlessCore
import SwiftUI

/// Settings › Desk Mode (design-spec §7.2, Settings2-DeskMode): the live hero
/// with the Desk Mode switch, then "Your rule" and "How it switches off" on the
/// left and the Safety net on the right (columns 1.5fr : 1fr).
///
/// Fills the area the Settings window gives it below the tab bar; the window
/// adds the content padding (0 18 18, §7.1).
struct DeskModeTab: View {
    let model: AppModel
    let preferences: PreferencesStore
    let actions: SettingsActions

    var body: some View {
        VStack(spacing: Spacing.settingsGridGap) {
            DeskModeHero(deskMode: model.deskMode, system: model.system)
            // The grid takes the rest of the height, as CSS `flex-grow: 1`.
            GeometryReader { proxy in
                let columns = proxy.size.width - Spacing.settingsGridGap
                HStack(alignment: .top, spacing: Spacing.settingsGridGap) {
                    VStack(spacing: Spacing.settingsGridGap) {
                        DeskRuleCard(preferences: preferences, system: model.system)
                        DeskMethodCard(preferences: preferences)
                    }
                    .frame(width: columns * 0.6)
                    SafetyNetCard(preferences: preferences, deskMode: model.deskMode, testSafetyNet: actions.testSafetyNet)
                        .frame(width: columns * 0.4)
                }
                .frame(height: proxy.size.height, alignment: .top)
            }
        }
    }
}

// MARK: - Hero

/// The dark "Desk Mode status" hero: art, live state, chips and the XL switch.
private struct DeskModeHero: View {
    @ObservedObject var deskMode: DeskModeStore
    @ObservedObject var system: SystemStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = deskMode.state
        HStack(spacing: 28) {
            VStack(spacing: 4) {
                DeskHeroArt(deskModeOn: state.isOn, width: 330)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.isOn)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(artLabel(isOn: state.isOn))
                    .accessibilityAddTraits(.isImage)
                Text("Lid open, so heat can escape", comment: "Caption under the Desk Mode illustration in Settings")
                    .lidlessStyle(.caption)
                    .foregroundStyle(Palette.textOnDark)
                    .lineBox(.caption)
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: 10) {
                Text("DESK MODE", comment: "Overline of the Settings Desk Mode hero; keep it uppercase")
                    .lidlessStyle(.overlineHero)
                    .foregroundStyle(Palette.gold)
                    .lineBox(.overlineHero)
                DeskHeroCopy(state: state, mainDisplayName: system.externals.first { $0.role == .main }?.name)
                DeskHeroChips(lid: system.lid, power: system.power, state: state)
                HStack(spacing: 12) {
                    Toggle(isOn: $deskMode.isOn) {
                        state.isAvailable
                            ? Text("Desk Mode", comment: "VoiceOver label of the Desk Mode switch")
                            : Text("Desk Mode, unavailable", comment: "VoiceOver label of the Desk Mode switch when it can't be used")
                    }
                    .toggleStyle(PillToggleStyle(size: .extraLarge, surface: .onDarkSettingsHero))
                    .disabled(!state.isAvailable || state.isSwitching)
                    toggleLabel(isOn: state.isOn)
                        .lidlessStyle(.heroToggleLabel)
                        .foregroundStyle(Palette.white)
                        .lineBox(.heroToggleLabel)
                        // The switch already says it.
                        .accessibilityHidden(true)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 32))
        .frame(maxWidth: .infinity)
        // The board's 232 pt, taller if a translation needs it; the grid
        // below gives up the height.
        .frame(minHeight: 232)
        .background { HeroCardSurface(cornerRadius: Radius.heroSettings, elevation: .flat) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Desk Mode status", comment: "VoiceOver label of the Settings Desk Mode hero"))
    }

    private func artLabel(isOn: Bool) -> Text {
        isOn
            ? Text("MacBook with lid open and screen off, next to a glowing monitor", comment: "VoiceOver description of the Desk Mode illustration when Desk Mode is on")
            : Text("MacBook with lid open and screen on, next to a glowing monitor", comment: "VoiceOver description of the Desk Mode illustration when Desk Mode is off")
    }

    private func toggleLabel(isOn: Bool) -> Text {
        // Own keys, so the bare "On"/"Off" can be translated for this spot.
        isOn
            ? Text(String(localized: "DeskMode.Hero.Switch.On", defaultValue: "On", comment: "Beside the big Desk Mode switch in Settings when it is on"))
            : Text(String(localized: "DeskMode.Hero.Switch.Off", defaultValue: "Off", comment: "Beside the big Desk Mode switch in Settings when it is off"))
    }
}

/// Title and paragraph of the hero, per Desk Mode state.
private struct DeskHeroCopy: View {
    let state: DeskModeState
    /// The external that is now the main display, if any.
    let mainDisplayName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            title
                .lidlessStyle(.heroTitleLarge)
                .foregroundStyle(Palette.white)
                .lineBox(.heroTitleLarge, lineHeight: 1.1)
                .fixedSize(horizontal: false, vertical: true)
                // The hero's heading (the board's <h1>).
                .accessibilityAddTraits(.isHeader)
            detail
                .lidlessStyle(.heroBody)
                .foregroundStyle(Palette.textOnDark)
                .lineBox(.heroBody, lineHeight: 1.45)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: Text {
        switch state {
        case .on:
            Text("Desk Mode is on", comment: "Settings Desk Mode hero title")
        case .off:
            Text("Desk Mode is off", comment: "Settings Desk Mode hero title")
        case .switching(toOn: true):
            Text("Turning Desk Mode on…", comment: "Settings Desk Mode hero title while the built-in screen switches off")
        case .switching(toOn: false):
            Text("Turning Desk Mode off…", comment: "Settings Desk Mode hero title while the built-in screen comes back")
        case .unavailable(.needsDisplay):
            Text("Desk Mode needs a display", comment: "Settings Desk Mode hero title when no external display is connected")
        case .unavailable(.lidClosed):
            Text("The lid is closed", comment: "Settings Desk Mode hero title when the MacBook lid is closed")
        case .unavailable(.unsupportedMac), .unavailable(.unsupportedSystem):
            Text("Desk Mode isn't available", comment: "Settings Desk Mode hero title when this Mac or macOS can't use Desk Mode")
        }
    }

    private var detail: Text {
        switch state {
        case .on:
            if let mainDisplayName {
                Text("Your built-in screen is off. \(mainDisplayName) is now your main display.", comment: "Settings Desk Mode hero text when on; the variable is the external display's name")
            } else {
                // Black out keeps the built-in as the main display.
                Text("Your built-in screen is off.", comment: "Settings Desk Mode hero text when on and the built-in is still the main display")
            }
        case .off:
            Text("Your built-in screen is on. Flip the switch to turn it off and let the Mac run cooler.", comment: "Settings Desk Mode hero text when off")
        // The rest reuse the popover card's sentences.
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

/// "Lid open" · "On power" · "Built-in screen off/on", from live state.
private struct DeskHeroChips: View {
    let lid: LidState
    let power: PowerSource
    let state: DeskModeState

    var body: some View {
        HStack(spacing: 6) {
            switch lid {
            case .open: InfoChip(text: Text(verbatim: StatusSegment.lidOpen.localizedText))
            case .closed: InfoChip(text: Text(verbatim: StatusSegment.lidClosed.localizedText))
            case .unknown: EmptyView()
            }
            switch power {
            case .adapter: InfoChip(text: Text(verbatim: StatusSegment.onPower.localizedText))
            case .battery(let percent): InfoChip(text: Text(verbatim: StatusSegment.onBattery(percent: percent).localizedText))
            case .unknown: EmptyView()
            }
            // A closed lid already says the screen is dark.
            if lid != .closed {
                state.isOn
                    ? InfoChip(text: Text("Built-in screen off", comment: "Settings Desk Mode hero chip"), isActive: true)
                    : InfoChip(text: Text("Built-in screen on", comment: "Settings Desk Mode hero chip"), isEmphasized: true)
            }
        }
    }
}

// MARK: - Your rule

/// "Your rule": the sentence with three token menus, then "Only when my Mac is plugged in".
private struct DeskRuleCard: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var system: SystemStore

    var body: some View {
        let rule = preferences.deskMode.rule
        SettingsCard(title: Text("Your rule", comment: "Settings Desk Mode card title"), spacing: 8) {
            RuleSentence(
                display: $preferences.deskMode.rule.settingsDisplay,
                displays: displayChoices(rule: rule),
                action: $preferences.deskMode.rule.settingsAction,
                delay: $preferences.deskMode.rule.delaySeconds
            )
            HStack(spacing: 10) {
                Text("Only when my Mac is plugged in", comment: "Settings Desk Mode rule option")
                    .lidlessStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                Toggle(isOn: $preferences.deskMode.rule.onlyOnPower) {
                    Text("Only when my Mac is plugged in", comment: "Settings Desk Mode rule option")
                }
                .toggleStyle(PillToggleStyle(size: .small))
            }
            // CSS: 1 pt top border, then 8 pt padding.
            .padding(.top, 8 + Spacing.hairline)
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.divider).frame(height: 1)
            }
        }
    }

    /// "any display", the connected externals, and the chosen display while it
    /// isn't connected (so the menu can show it).
    private func displayChoices(rule: DeskModeRule) -> [RuleDisplay] {
        var choices = [RuleDisplay.any]
        choices += system.externals.map { RuleDisplay(uuid: $0.id, name: $0.name) }
        if let uuid = rule.displayUUID, !choices.contains(RuleDisplay(uuid: uuid, name: "")) {
            choices.append(RuleDisplay(uuid: uuid, name: rule.displayName ?? ""))
        }
        return choices
    }
}

/// The display token's value. Equal by UUID, so a renamed display stays selected.
private nonisolated struct RuleDisplay: Hashable, Sendable {
    /// nil is "any display".
    let uuid: String?
    let name: String

    static let any = RuleDisplay(uuid: nil, name: "")

    static func == (lhs: RuleDisplay, rhs: RuleDisplay) -> Bool { lhs.uuid == rhs.uuid }
    func hash(into hasher: inout Hasher) { hasher.combine(uuid) }
}

private nonisolated extension DeskModeRule {
    /// The display token: "any display" or one display, remembered with its name.
    var settingsDisplay: RuleDisplay {
        get { RuleDisplay(uuid: displayUUID, name: displayName ?? "") }
        set {
            displayUUID = newValue.uuid
            displayName = newValue.uuid == nil ? nil : newValue.name
        }
    }

    /// The action token. The rule only acts when it is enabled and set to
    /// "off", so anything else reads as "on"; choosing "off" enables it.
    var settingsAction: Action {
        get { isEnabled && action == .off ? .off : .on }
        set {
            action = newValue
            if newValue == .off { isEnabled = true }
        }
    }
}

/// "When I plug in [any display ▾], turn the built-in screen [off ▾] after [3 seconds ▾]."
///
/// One localized template with `{display}`, `{action}` and `{delay}` markers,
/// so translators can reorder it. It wraps like the canvas's inline text:
/// between words, never between a menu and the punctuation after it.
private struct RuleSentence: View {
    @Binding var display: RuleDisplay
    let displays: [RuleDisplay]
    @Binding var action: DeskModeRule.Action
    @Binding var delay: Int

    /// macOS 12 only (no `Layout` there): each word's width once laid out, and
    /// the width the sentence has.
    @State private var measuredWidths: [Int: CGFloat] = [:]
    @State private var availableWidth: CGFloat?

    /// CSS `line-height: 2.1` at 15 pt.
    private static let lineHeight: CGFloat = 31.5
    private static let wordSpace = (" " as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: TypeStyle.ruleSentence.size)]).width

    var body: some View {
        let words = RuleTemplate.words(immediate: delay == 0)
        // No space after a word in languages written without spaces.
        let gaps = words.map { $0.spaceAfter ? Self.wordSpace : 0 }
        Group {
            if #available(macOS 13, *) {
                SentenceFlow(gaps: gaps, lineHeight: Self.lineHeight) {
                    ForEach(Array(words.enumerated()), id: \.offset) { word in
                        wordView(word.element.parts)
                    }
                }
            } else {
                measuredFlow(words, gaps: gaps)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // VoiceOver reads the sentence once (the words are hidden), then the three menus.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: spokenSentence(words)))
    }

    /// macOS 12: the same line breaking as `SentenceFlow`, from the widths the
    /// words report once laid out. Until they have, it breaks after each menu.
    private func measuredFlow(_ words: [RuleTemplate.Word], gaps: [CGFloat]) -> some View {
        let widths = words.indices.compactMap { measuredWidths[$0] }
        let lines: [[Int]]
        if let availableWidth, widths.count == words.count {
            lines = SentenceLines.lines(widths: widths, gaps: gaps, maxWidth: availableWidth).map(\.indices)
        } else {
            lines = RuleTemplate.menuLines(words)
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { line in
                HStack(spacing: 0) {
                    ForEach(line.element, id: \.self) { index in
                        wordView(words[index].parts)
                            .onSizeChange { size in
                                if measuredWidths[index] != size.width { measuredWidths[index] = size.width }
                            }
                            .padding(.trailing, index == line.element.last ? 0 : gaps[index])
                    }
                }
                .frame(height: Self.lineHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onSizeChange { size in
            if availableWidth != size.width { availableWidth = size.width }
        }
    }

    private func spokenSentence(_ words: [RuleTemplate.Word]) -> String {
        words.map { word in
            word.parts.map { part in
                switch part {
                case .text(let text): text
                case .token(.display): displayName(display)
                case .token(.action): RuleTemplate.label(for: action)
                case .token(.delay): RuleTemplate.label(forDelay: delay)
                }
            }
            .joined() + (word.spaceAfter ? " " : "")
        }
        .joined()
    }

    /// One unbreakable run: plain text, or a menu with the punctuation that follows it.
    private func wordView(_ parts: [RuleTemplate.Part]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { part in
                switch part.element {
                case .text(let text):
                    Text(verbatim: text)
                        .lidlessStyle(.ruleSentence)
                        .foregroundStyle(Palette.text2)
                        .fixedSize()
                        .accessibilityHidden(true)
                case .token(.display):
                    TokenMenu(
                        selection: $display,
                        options: displays,
                        label: { Text(verbatim: displayName($0)) },
                        accessibilityLabel: Text("Display", comment: "VoiceOver label of the rule's display menu in Settings"),
                        menuTitle: displayName
                    )
                case .token(.action):
                    TokenMenu(
                        selection: $action,
                        options: DeskModeRule.Action.allCases,
                        label: { Text(verbatim: RuleTemplate.label(for: $0)) },
                        accessibilityLabel: Text("Built-in screen", comment: "VoiceOver label of the rule's off/on menu in Settings"),
                        menuTitle: RuleTemplate.label(for:)
                    )
                case .token(.delay):
                    TokenMenu(
                        selection: $delay,
                        options: DeskModeRule.delayChoices,
                        label: { Text(verbatim: RuleTemplate.label(forDelay: $0)) },
                        accessibilityLabel: Text("Delay", comment: "VoiceOver label of the rule's delay menu in Settings"),
                        menuTitle: RuleTemplate.label(forDelay:)
                    )
                }
            }
        }
    }

    /// The live name while connected, else the remembered one.
    private func displayName(_ choice: RuleDisplay) -> String {
        guard choice.uuid != nil else { return RuleTemplate.anyDisplay }
        let name = displays.first { $0 == choice }?.name ?? choice.name
        return name.isEmpty
            ? String(localized: "DeskRule.Display.Unnamed", defaultValue: "a saved display", comment: "Rule sentence token for a chosen display whose name is unknown")
            : name
    }
}

/// The rule sentence's template, split into words for wrapping.
private nonisolated enum RuleTemplate {
    enum Token: String, CaseIterable {
        case display, action, delay
    }

    enum Part: Equatable {
        case text(String)
        case token(Token)

        var token: Token? {
            if case .token(let token) = self { return token }
            return nil
        }
    }

    /// An unbreakable run of the sentence: text, or a menu with the
    /// punctuation next to it.
    struct Word: Equatable {
        var parts: [Part]
        /// A space follows it; not between words of languages written without spaces.
        var spaceAfter: Bool
    }

    static var anyDisplay: String {
        String(localized: "DeskRule.Display.Any", defaultValue: "any display", comment: "Rule sentence token: the rule fires for any external display. Lowercase, mid-sentence.")
    }

    static func label(for action: DeskModeRule.Action) -> String {
        switch action {
        case .off: String(localized: "DeskRule.Action.Off", defaultValue: "off", comment: "Rule sentence token: turn the built-in screen off. Lowercase, mid-sentence.")
        case .on: String(localized: "DeskRule.Action.On", defaultValue: "on", comment: "Rule sentence token: leave the built-in screen on (the rule does nothing). Lowercase, mid-sentence.")
        }
    }

    static func label(forDelay seconds: Int) -> String {
        seconds == 0
            ? String(localized: "DeskRule.Delay.Now", defaultValue: "right away", comment: "Rule sentence token: no delay. Lowercase, mid-sentence.")
            : String(localized: "DeskRule.Delay.Seconds", defaultValue: "\(seconds) seconds", comment: "Rule sentence token: the delay, e.g. 3 seconds. Lowercase, mid-sentence.")
    }

    /// Words of the sentence. "right away" drops the "after".
    static func words(immediate: Bool) -> [Word] {
        let template = immediate
            ? String(localized: "DeskRule.Sentence.Now", defaultValue: "When I plug in {display}, turn the built-in screen {action} {delay}.", comment: "Settings Desk Mode rule when the delay is \"right away\". Keep {display}, {action} and {delay}: each becomes a pop-up menu (e.g. \"any display\", \"off\", \"right away\").")
            : String(localized: "DeskRule.Sentence", defaultValue: "When I plug in {display}, turn the built-in screen {action} after {delay}.", comment: "Settings Desk Mode rule. Keep {display}, {action} and {delay}: each becomes a pop-up menu (e.g. \"any display\", \"off\", \"3 seconds\").")
        let words = parse(template)
        // A translation that lost a marker would lose its menu: use English.
        guard Set(words.flatMap(\.parts).compactMap(\.token)) == Set(Token.allCases) else {
            return parse(immediate
                ? "When I plug in {display}, turn the built-in screen {action} {delay}."
                : "When I plug in {display}, turn the built-in screen {action} after {delay}.")
        }
        return words
    }

    /// macOS 12 before the words are measured: a break after every word that holds a menu.
    static func menuLines(_ words: [Word]) -> [[Int]] {
        var lines: [[Int]] = [[]]
        for index in words.indices {
            lines[lines.count - 1].append(index)
            if words[index].parts.contains(where: { $0.token != nil }), index < words.count - 1 {
                lines.append([])
            }
        }
        return lines
    }

    /// Splits a template into words. A line may break at a space, and between
    /// two words the system's word breaking finds (so Chinese or Japanese
    /// wrap too, and "built-in" may break after the hyphen). Punctuation stays
    /// with what comes before it, and a menu with the punctuation around it.
    static func parse(_ template: String) -> [Word] {
        var builder = WordBuilder()
        for segment in segments(template) {
            switch segment {
            case .token(let token):
                builder.append(.token(token), breakBefore: builder.endsWithLetter)
            case .text(let text):
                for chunk in chunks(text) {
                    // Spaces inside a chunk ("écran «") are break points too.
                    var breakBefore = chunk.startsAtWord
                    var piece = ""
                    for character in chunk.text {
                        if isBreakingSpace(character) {
                            if !piece.isEmpty { builder.append(.text(piece), breakBefore: breakBefore) }
                            piece = ""
                            breakBefore = false
                            builder.space()
                        } else {
                            piece.append(character)
                        }
                    }
                    if !piece.isEmpty { builder.append(.text(piece), breakBefore: breakBefore) }
                }
            }
        }
        return builder.finish()
    }

    /// A space a line may break at: not the no-break spaces French puts
    /// inside « » or before punctuation.
    private static func isBreakingSpace(_ character: Character) -> Bool {
        character.isWhitespace && !["\u{00A0}", "\u{202F}", "\u{2007}"].contains(character)
    }

    private enum Segment {
        case text(String)
        case token(Token)
    }

    /// Text and `{marker}`s, in order. Braces that aren't a marker are text.
    private static func segments(_ template: String) -> [Segment] {
        var segments: [Segment] = []
        var text = ""
        var rest = Substring(template)
        while let first = rest.first {
            if first == "{", let close = rest.firstIndex(of: "}"),
               let token = Token(rawValue: String(rest[rest.index(after: rest.startIndex)..<close])) {
                if !text.isEmpty { segments.append(.text(text)) }
                text = ""
                segments.append(.token(token))
                rest = rest[rest.index(after: close)...]
            } else {
                text.append(first)
                rest = rest.dropFirst()
            }
        }
        if !text.isEmpty { segments.append(.text(text)) }
        return segments
    }

    /// Cuts text where each word starts; each piece keeps the spaces and
    /// punctuation after its word.
    private static func chunks(_ text: String) -> [(text: Substring, startsAtWord: Bool)] {
        var wordStarts: [String.Index] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            wordStarts.append(range.lowerBound)
        }
        var chunks: [(text: Substring, startsAtWord: Bool)] = []
        var start = text.startIndex
        for cut in wordStarts where cut > start {
            chunks.append((text[start..<cut], wordStarts.contains(start)))
            start = cut
        }
        if start < text.endIndex {
            chunks.append((text[start...], wordStarts.contains(start)))
        }
        return chunks
    }

    /// Collects parts into words.
    private struct WordBuilder {
        private var words: [Word] = []
        private var current: [Part] = []
        private var spacePending = false

        /// The run so far ends in a letter or digit with no space after it,
        /// so a menu that follows may start a new line (languages without spaces).
        var endsWithLetter: Bool {
            guard !spacePending, case .text(let text)? = current.last, let last = text.last else { return false }
            return last.isLetter || last.isNumber
        }

        mutating func space() {
            if !current.isEmpty { spacePending = true }
        }

        mutating func append(_ part: Part, breakBefore: Bool) {
            if !current.isEmpty, spacePending || breakBefore {
                words.append(Word(parts: current, spaceAfter: spacePending))
                current = []
            }
            spacePending = false
            if case .text(let new) = part, case .text(let old)? = current.last {
                current[current.count - 1] = .text(old + new)
            } else {
                current.append(part)
            }
        }

        mutating func finish() -> [Word] {
            if !current.isEmpty { words.append(Word(parts: current, spaceAfter: false)) }
            current = []
            return words
        }
    }
}

/// Greedy line breaking shared by `SentenceFlow` and macOS 12's fallback:
/// as many words on a line as fit, each followed by its gap.
private nonisolated enum SentenceLines {
    struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
    }

    static func lines(widths: [CGFloat], gaps: [CGFloat], maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in widths.indices {
            let width = widths[index]
            let needed = current.indices.last.map { current.width + gap(gaps, after: $0) + width } ?? width
            // Half a point of slack for rounding in measured widths.
            if needed > maxWidth + 0.5, !current.indices.isEmpty {
                lines.append(current)
                current = Line(indices: [index], width: width)
            } else {
                current.indices.append(index)
                current.width = needed
            }
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }

    static func gap(_ gaps: [CGFloat], after index: Int) -> CGFloat {
        gaps.indices.contains(index) ? gaps[index] : 0
    }
}

/// Inline text flow: words left to right, each followed by its gap, wrapping
/// onto lines `lineHeight` apart with each word centred on its line (CSS
/// inline boxes with `vertical-align: middle`).
@available(macOS 13, *)
private nonisolated struct SentenceFlow: Layout {
    /// The space after each word.
    let gaps: [CGFloat]
    let lineHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = lines(maxWidth: maxWidth, subviews: subviews)
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: CGFloat(lines.count) * lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (row, line) in lines(maxWidth: bounds.width, subviews: subviews).enumerated() {
            var x = bounds.minX
            let midY = bounds.minY + (CGFloat(row) + 0.5) * lineHeight
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: midY), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + SentenceLines.gap(gaps, after: index)
            }
        }
    }

    private func lines(maxWidth: CGFloat, subviews: Subviews) -> [SentenceLines.Line] {
        SentenceLines.lines(widths: subviews.map { $0.sizeThatFits(.unspecified).width }, gaps: gaps, maxWidth: maxWidth)
    }
}

// MARK: - How it switches off

/// "How it switches off": Disconnect or Black out.
private struct DeskMethodCard: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        let method = preferences.deskMode.method
        // Grows to the column's height (CSS `flex-grow: 1`).
        SettingsCard(title: Text("How it switches off", comment: "Settings Desk Mode card title"), spacing: 10, fillsHeight: true) {
            HStack(alignment: .top, spacing: 10) {
                MethodCard(
                    title: Text("Disconnect", comment: "Desk Mode method: SkyLight takes the built-in screen out of the arrangement"),
                    detail: Text("Windows move to your other screen. Coolest and lightest on the GPU.", comment: "Description of the Disconnect method"),
                    isSelected: method == .disconnect,
                    action: { preferences.deskMode.method = .disconnect },
                    art: { MethodDisconnectArt() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                MethodCard(
                    title: Text("Black out", comment: "Desk Mode method: a black cover over the built-in screen"),
                    detail: Text("Screen goes dark, windows stay put. Quicker to switch back.", comment: "Description of the Black out method"),
                    isSelected: method == .blackout,
                    action: { preferences.deskMode.method = .blackout },
                    art: { MethodBlackOutArt() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Both cards as tall as the taller one (CSS grid rows stretch).
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Safety net

/// "Safety net": the three ways the screen comes back, and the test button.
private struct SafetyNetCard: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var deskMode: DeskModeStore
    let testSafetyNet: () -> Void

    var body: some View {
        // As tall as the grid row (CSS grid items stretch).
        SettingsCard(spacing: 12, fillsHeight: true) {
            HStack(spacing: 8) {
                GlyphView(glyph: .shield, size: 18, lineWidth: 1.8, interiorFill: Palette.gold)
                    .foregroundStyle(Palette.ink)
                Text("Safety net", comment: "Settings Desk Mode card title")
                    .lidlessStyle(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineBox(.cardTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Three ways your screen always comes back.", comment: "Settings Safety net card description")
                .lidlessStyle(.description)
                .foregroundStyle(Palette.text4)
                .lineBox(.description, lineHeight: 1.4)
                .fixedSize(horizontal: false, vertical: true)
            SafetyNetRow(number: 1) {
                SafetyNetText(
                    title: Text("Unplug everything, it comes back", comment: "Safety net item 1 title"),
                    detail: Text("Also checked at wake and login.", comment: "Safety net item 1 helper")
                )
                Badge(text: Text("Always", comment: "Badge: this safety net item is always on and can't be turned off"), style: .locked)
            }
            .accessibilityElement(children: .combine)
            SafetyNetRow(number: 2) {
                SafetyNetText(
                    title: Text("Ask before keeping it off", comment: "Safety net item 2 title"),
                    detail: Text("No answer in 15 seconds? It turns back on.", comment: "Safety net item 2 helper")
                )
                .accessibilityHidden(true)
                Toggle(isOn: $preferences.deskMode.askBeforeKeeping) {
                    Text("Ask before keeping it off", comment: "Safety net item 2 title")
                }
                .toggleStyle(PillToggleStyle(size: .small))
                .accessibilityHint(Text("No answer in 15 seconds? It turns back on.", comment: "Safety net item 2 helper"))
            }
            SafetyNetRow(number: 3) {
                VStack(alignment: .leading, spacing: 6) {
                    SafetyNetTitle(text: Text("Panic key", comment: "Safety net item 3 title"))
                    KeyCombo(keys: deskMode.panicKeys, size: .medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            // CSS `margin-top: auto`: the button sits at the bottom of the card.
            Spacer(minLength: 0)
            SafetyNetTestButton(state: deskMode.state, action: testSafetyNet)
        }
    }
}

/// A numbered row: `NumberBadge`, then the row's content, top-aligned.
private struct SafetyNetRow<Content: View>: View {
    let number: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NumberBadge(number: number)
                .accessibilityHidden(true)
            content()
        }
    }
}

private struct SafetyNetTitle: View {
    let text: Text

    var body: some View {
        text
            .lidlessStyle(.bodyStrong)
            .foregroundStyle(Palette.textPrimary)
            .lineBox(.bodyStrong)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Title and helper of a Safety net row; takes the row's free width.
private struct SafetyNetText: View {
    let title: Text
    let detail: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SafetyNetTitle(text: title)
            detail
                .lidlessStyle(.helper)
                .foregroundStyle(Palette.text4)
                .lineBox(.helper, lineHeight: 1.4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Test the safety net": runs Desk Mode with the keep-or-revert prompt forced.
///
/// Works only while Desk Mode is off. Otherwise it keeps the board's
/// full-strength look (the board shows it with Desk Mode on) but does nothing,
/// and its tooltip and VoiceOver hint say why.
private struct SafetyNetTestButton: View {
    let state: DeskModeState
    let action: () -> Void

    var body: some View {
        let isEnabled = state == .off
        Button(action: action) {
            HStack(spacing: 8) {
                GlyphView(glyph: .play, size: 14)
                    .foregroundStyle(Palette.gold)
                Text("Test the safety net", comment: "Settings Safety net button: turns Desk Mode on with the keep-or-revert prompt")
            }
        }
        .buttonStyle(DarkButtonStyle())
        // The style draws no disabled look, so the button stays full strength.
        .disabled(!isEnabled)
        .accessibilityHint(hint)
        .overlay {
            // A disabled control shows no tooltip: this catches the hover
            // (and the clicks, which would do nothing anyway).
            if let reason = unavailableReason {
                Capsule()
                    .fill(Color.clear)
                    .contentShape(Capsule())
                    .help(reason)
                    .accessibilityHidden(true)
            }
        }
    }

    private var hint: Text {
        unavailableReason ?? Text("Turns the built-in screen off, then asks whether to keep it off.", comment: "VoiceOver hint of the Test the safety net button")
    }

    /// Why the test can't run now; nil while it can.
    private var unavailableReason: Text? {
        switch state {
        case .off:
            nil
        case .on, .switching:
            Text("Turn Desk Mode off first.", comment: "Tooltip and VoiceOver hint of Test the safety net while Desk Mode is on or switching")
        case .unavailable:
            Text("Desk Mode can't be used right now.", comment: "Tooltip and VoiceOver hint of Test the safety net while Desk Mode is unavailable (no display, lid closed, unsupported Mac)")
        }
    }
}

#if DEBUG
#Preview("Desk Mode tab, off") {
    let model = SampleData.deskSetup()
    DeskModeTab(model: model, preferences: model.preferences, actions: SettingsActions())
        .padding(EdgeInsets(top: 0, leading: 18, bottom: 18, trailing: 18))
        .frame(width: 878, height: 662)
        .background { SettingsWindowBackground() }
        .preferredColorScheme(.light)
}

#Preview("Desk Mode tab, on") {
    let model = SampleData.deskModeOn()
    DeskModeTab(model: model, preferences: model.preferences, actions: SettingsActions())
        .padding(EdgeInsets(top: 0, leading: 18, bottom: 18, trailing: 18))
        .frame(width: 878, height: 662)
        .background { SettingsWindowBackground() }
        .preferredColorScheme(.light)
}
#endif
