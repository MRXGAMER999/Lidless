import AppKit
import LidlessCore
import SwiftUI

/// Settings › Keys & App (design-spec §7.4, Settings2-General): the panic key
/// hero, the quick keys, the menu bar options and About.
///
/// Fills the content area the Settings window gives it (the window applies the
/// 0/18/18 padding); the About card takes the height that is left, as its
/// `flex-grow` does on the canvas.
struct KeysTab: View {
    let model: AppModel
    @ObservedObject var preferences: PreferencesStore
    let actions: SettingsActions
    let launchAtLogin: any LaunchAtLogin

    init(model: AppModel, preferences: PreferencesStore, actions: SettingsActions, launchAtLogin: any LaunchAtLogin) {
        self.model = model
        self.preferences = preferences
        self.actions = actions
        self.launchAtLogin = launchAtLogin
    }

    var body: some View {
        VStack(spacing: Spacing.settingsGridGap) {
            PanicKeyHero(
                deskMode: model.deskMode,
                // The subscript ignores nil for the panic slot, so it can't be removed.
                panic: $preferences.shortcuts[.panic],
                shortcuts: preferences.shortcuts,
                actions: actions
            )
            HStack(alignment: .top, spacing: Spacing.settingsGridGap) {
                QuickKeysCard(shortcuts: $preferences.shortcuts, actions: actions)
                MenuBarCard(launchAtLogin: launchAtLogin, iconShowsState: $preferences.general.iconShowsState)
            }
            // CSS grid rows stretch: both cards take the taller one's height.
            .fixedSize(horizontal: false, vertical: true)
            AboutCard(autoUpdate: $preferences.general.autoUpdate, actions: actions)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Panic key hero

/// "PANIC KEY": what it does, "Change Keys" / "Try It", and the keys in 76 pt caps.
private struct PanicKeyHero: View {
    @ObservedObject var deskMode: DeskModeStore
    @Binding var panic: KeyShortcut?
    let shortcuts: ShortcutSet
    let actions: SettingsActions

    @State private var isRecording = false
    @State private var trial: PanicTrial = .idle
    /// Why "Change Keys" refused the last keys, shown under the buttons.
    @State private var recorderProblem: String?
    /// Why the panic key may not work (refused by macOS, shared with another
    /// app, not registered), shown under the buttons too.
    @State private var notice: PanicKeyNotice?
    /// The last panic key recorded here, until the app has registered it.
    @State private var change: PanicKeyNotice.Change?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 10) {
                Text("PANIC KEY", comment: "Overline of the panic key hero in Settings › Keys & App")
                    .lidlessStyle(.overlineHero)
                    .foregroundStyle(Palette.gold)
                    .lineBox(.overlineHero)
                Text("One shortcut that always brings your screen back.", comment: "Title of the panic key hero in Settings › Keys & App")
                    .lidlessStyle(.heroTitleMedium)
                    .foregroundStyle(Palette.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(.heroTitleMedium, lineHeight: 1.15)
                    .accessibilityAddTraits(.isHeader)
                Text("Works even if Lidless is busy. You can change the keys, never remove them.", comment: "Body of the panic key hero in Settings › Keys & App")
                    .lidlessStyle(.body)
                    .foregroundStyle(Palette.textOnDark)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(.body, lineHeight: 1.45)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        changeKeysButton
                        TryItButton(trial: trial, action: toggleTrial)
                            .disabled(isRecording)
                    }
                    // Not designed. The hero (min 230 pt) grows to fit them.
                    if let recorderProblem {
                        Text(verbatim: recorderProblem)
                            .lidlessStyle(.helper)
                            .foregroundStyle(Palette.goldOnDark)
                            .fixedSize(horizontal: false, vertical: true)
                            // Announced, and part of the recorder's value.
                            .accessibilityHidden(true)
                    }
                    if let notice {
                        Text(verbatim: notice.message(keys: { Self.labels($0).keycaps.joined() }))
                            .lidlessStyle(.helper)
                            .foregroundStyle(Palette.goldOnDark)
                            .fixedSize(horizontal: false, vertical: true)
                            // Keys read as words, not symbols.
                            .accessibilityLabel(Text(verbatim: notice.message(keys: { Self.labels($0).spokenName })))
                    }
                }
                .padding(.top, 4)
            }
            .frame(width: 330, alignment: .leading)

            PanicKeycaps(keys: deskMode.panicKeys)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, minHeight: 230)
        .background { HeroCardSurface(cornerRadius: Radius.heroSettings, elevation: .flat) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Panic key", comment: "Accessibility label of the panic key hero in Settings › Keys & App"))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: trial)
        .task(id: trial) { await expire(trial) }
        // After each change, once the app has registered (or refused) the keys.
        .task(id: PanicKeyCheck(saved: panic, change: change)) {
            try? await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)
            guard !Task.isCancelled else { return }
            refreshNotice()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshNotice() }
        .onDisappear {
            stopTrial()
            recorderProblem = nil
            change = nil
            notice = nil
        }
    }

    /// Records into the saved panic key, remembering the change to check it.
    private var recordedPanic: Binding<KeyShortcut?> {
        Binding(
            get: { panic },
            set: { newValue in
                if let newValue, let previous = panic, newValue != previous {
                    change = PanicKeyNotice.Change(recorded: newValue, previous: previous)
                }
                panic = newValue
            }
        )
    }

    private func refreshNotice() {
        guard let saved = panic else { return }
        let result = PanicKeyNotice.resolve(change: change, saved: saved, registration: actions.panicKeyRegistration())
        if result.change != change { change = result.change }
        guard result.notice != notice else { return }
        notice = result.notice
        // Only a refusal answers something the user just did; the others are
        // read in place.
        if let refused = result.notice, case .refused = refused {
            announce(refused.message(keys: { Self.labels($0).spokenName }))
        }
    }

    /// Keycaps and spoken name on the current keyboard layout.
    private static func labels(_ shortcut: KeyShortcut) -> ShortcutLabels {
        ShortcutLabels(shortcut, keyLabel: shortcut.displayKeyLabel)
    }

    /// "Change Keys": records a new panic key. Clearing is off, so the panic
    /// key can be changed but never removed.
    private var changeKeysButton: some View {
        ShortcutRecorder(
            shortcut: recordedPanic,
            slot: .panic,
            shortcuts: shortcuts,
            allowsClearing: false,
            setRecording: { recording in
                if recording {
                    stopTrial()
                    // A new recording replaces the last refusal.
                    if case .refused = notice { notice = nil }
                    change = nil
                }
                isRecording = recording
                actions.setRecordingShortcut(recording)
            },
            style: .changeKeysButton,
            problem: $recorderProblem
        )
    }

    private func toggleTrial() {
        switch trial {
        case .idle, .succeeded:
            trial = .waiting
            actions.awaitPanicKey {
                guard trial == .waiting else { return }
                trial = .succeeded
                announce(String(localized: "It works. The panic key brings your screen back.", comment: "VoiceOver announcement after the panic key was pressed during Try It"))
            }
        case .waiting:
            stopTrial()
        }
    }

    /// Stops waiting for the panic key (a second click, recording, or leaving the tab).
    private func stopTrial() {
        if trial == .waiting { actions.cancelAwaitPanicKey() }
        trial = .idle
    }

    /// Gives up waiting after a while, and lets the check mark go back to "Try It".
    private func expire(_ state: PanicTrial) async {
        let seconds: UInt64
        switch state {
        case .idle: return
        case .waiting: seconds = PanicTrial.waitSeconds
        case .succeeded: seconds = PanicTrial.checkMarkSeconds
        }
        try? await Task.sleep(nanoseconds: seconds * NSEC_PER_SEC)
        guard !Task.isCancelled, trial == state else { return }
        if state == .waiting {
            announce(String(localized: "Stopped waiting for the panic key.", comment: "VoiceOver announcement when Try It gives up after 15 seconds without the panic key"))
        }
        stopTrial()
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

/// What the panic key check waits on: a new saved key, or a new recording
/// (which may end on the key it started from, if the app refused it at once).
private struct PanicKeyCheck: Equatable {
    let saved: KeyShortcut?
    let change: PanicKeyNotice.Change?
}

/// Where "Try It" is: waiting for the panic key, or showing that it worked.
private enum PanicTrial: Equatable {
    case idle
    case waiting
    case succeeded

    /// The same 15 s the keep-or-revert prompt waits.
    static let waitSeconds: UInt64 = 15
    static let checkMarkSeconds: UInt64 = 5
}

/// The gold "Try It" button: "Press the Keys…" while waiting, a check mark once the keys work.
private struct TryItButton: View {
    let trial: PanicTrial
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if trial == .succeeded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .accessibilityHidden(true)
                }
                title
            }
        }
        .buttonStyle(PrimaryButtonStyle(size: .small))
        .accessibilityHint(hint)
    }

    private var title: Text {
        switch trial {
        case .idle:
            Text("Try It", comment: "Button in the panic key hero: waits for the panic key without turning anything off")
        case .waiting:
            Text("Press the Keys…", comment: "The Try It button while it waits for the panic key; clicking again stops")
        case .succeeded:
            Text("It Works", comment: "The Try It button after the panic key was pressed, next to a check mark")
        }
    }

    private var hint: Text {
        switch trial {
        case .idle, .succeeded:
            Text("Checks that the panic key reaches Lidless. Nothing turns off.", comment: "VoiceOver hint of the Try It button")
        case .waiting:
            Text("Press the panic key now. Click again to stop.", comment: "VoiceOver hint of the Try It button while it waits")
        }
    }
}

/// The panic key in 76 pt caps, each named below; the last key is gold and
/// captioned "back".
private struct PanicKeycaps: View {
    let keys: ShortcutLabels

    var body: some View {
        let caps = keys.keycaps
        // Five keys (with ⇧) don't fit the hero at 76 pt; the 68 pt caps do.
        let size: KeyCap.Size = caps.count > 4 ? .large : .extraLarge
        HStack(spacing: 12) {
            ForEach(Array(caps.enumerated()), id: \.element) { item in
                let isLast = item.offset == caps.count - 1
                VStack(spacing: 8) {
                    KeyCap(label: item.element, size: size, isAccent: isLast)
                    caption(for: item.element, isLast: isLast)
                        .lidlessStyle(isLast ? .smallStrongCaption : .caption)
                        .foregroundStyle(isLast ? Palette.gold : Palette.textOnDark)
                        .lineBox(.caption)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: keys.spokenName))
    }

    private func caption(for key: String, isLast: Bool) -> Text {
        if isLast { return Text("back", comment: "Caption under the panic key's letter key: pressing it brings the screen back") }
        switch key {
        case "⌃": return Text("control", comment: "Caption under the Control keycap")
        case "⌥": return Text("option", comment: "Caption under the Option keycap")
        case "⇧": return Text("shift", comment: "Caption under the Shift keycap")
        case "⌘": return Text("command", comment: "Caption under the Command keycap")
        default: return Text(verbatim: "")
        }
    }
}

private extension TypeStyle {
    /// 11/600: the gold "back" caption.
    static let smallStrongCaption = TypeStyle(size: 11, weight: .semibold, design: .default, cssLineHeight: 13, nativeLineHeight: 14)
}

// MARK: - Quick keys

/// "Quick keys": Desk Mode and Boost shortcuts; either can be cleared.
private struct QuickKeysCard: View {
    @Binding var shortcuts: ShortcutSet
    let actions: SettingsActions

    var body: some View {
        SettingsCard(title: Text("Quick keys", comment: "Card title in Settings › Keys & App"), fillsHeight: true) {
            row(Text("Desk Mode on or off", comment: "Quick key row in Settings › Keys & App"), slot: .toggleDeskMode, shortcut: $shortcuts.toggleDeskMode)
            row(Text("Boost on or off", comment: "Quick key row in Settings › Keys & App"), slot: .toggleBoost, shortcut: $shortcuts.toggleBoost)
            Text("Click a shortcut, then press the new keys.", comment: "Hint under the quick keys in Settings › Keys & App")
                .lidlessStyle(.helper)
                .foregroundStyle(Palette.text4)
                .fixedSize(horizontal: false, vertical: true)
                .lineBox(.helper)
        }
    }

    private func row(_ title: Text, slot: ShortcutSet.Slot, shortcut: Binding<KeyShortcut?>) -> some View {
        // Top-aligned so a refusal under the keys doesn't move the title; the
        // 5 pt centres its line on the 26 pt keycaps, as `align-items: center` does.
        HStack(alignment: .top, spacing: 10) {
            title
                .lidlessStyle(.body)
                .foregroundStyle(Palette.textPrimary)
                .lineBox(.body)
                .padding(.top, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The recorder carries the same name.
                .accessibilityHidden(true)
            ShortcutRecorder(
                shortcut: shortcut,
                slot: slot,
                shortcuts: shortcuts,
                allowsClearing: true,
                setRecording: actions.setRecordingShortcut
            )
        }
    }
}

// MARK: - Menu bar

/// "Menu bar": launch at login (hidden where SMAppService doesn't exist) and
/// "Icon shows what's on".
private struct MenuBarCard: View {
    let launchAtLogin: any LaunchAtLogin
    @Binding var iconShowsState: Bool

    /// Read from `SMAppService` on appear and whenever the app comes forward,
    /// since the user can change it in System Settings at any time.
    @State private var login: LoginStatus

    init(launchAtLogin: any LaunchAtLogin, iconShowsState: Binding<Bool>) {
        self.launchAtLogin = launchAtLogin
        _iconShowsState = iconShowsState
        login = LoginStatus(launchAtLogin)
    }

    var body: some View {
        SettingsCard(title: Text("Menu bar", comment: "Card title in Settings › Keys & App"), fillsHeight: true) {
            if login.isAvailable { loginRow }
            iconRow
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var loginRow: some View {
        let title = Text("Start Lidless when I log in", comment: "Toggle in Settings › Keys & App › Menu bar")
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .lidlessStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineBox(.body)
                    .accessibilityHidden(true)
                if login.needsApproval { approvalHint }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: loginBinding) { title }
                .toggleStyle(PillToggleStyle(size: .small))
        }
    }

    /// Shown while macOS waits for the user to allow Lidless in Login Items.
    /// Stacked, so a longer translation wraps instead of pushing the switch.
    private var approvalHint: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Needs your OK in System Settings.", comment: "Hint under Start Lidless when I log in, while macOS waits for approval in Login Items")
                .lidlessStyle(.helper)
                .foregroundStyle(Palette.text4)
                .lineBox(.helper)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: launchAtLogin.openLoginItemsSettings) {
                Text("Open Login Items", comment: "Link that opens System Settings › General › Login Items")
                    .lidlessStyle(.helperStrong)
            }
            .buttonStyle(InlineLinkButtonStyle())
        }
    }

    private var iconRow: some View {
        let title = Text("Icon shows what's on", comment: "Toggle in Settings › Keys & App › Menu bar")
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                title
                    .lidlessStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineBox(.body)
                    .accessibilityHidden(true)
                IconStateChips()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: $iconShowsState) { title }
                .toggleStyle(PillToggleStyle(size: .small))
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { login.isEnabled },
            set: { newValue in
                launchAtLogin.setEnabled(newValue)
                // Whatever macOS made of it, failure included.
                refresh()
            }
        )
    }

    private func refresh() {
        let status = LoginStatus(launchAtLogin)
        if status != login { login = status }
    }
}

/// A snapshot of `LaunchAtLogin`, so the view redraws when it changes.
private struct LoginStatus: Equatable {
    let isAvailable: Bool
    let isEnabled: Bool
    let needsApproval: Bool

    init(_ service: any LaunchAtLogin) {
        isAvailable = service.isAvailable
        isEnabled = service.isEnabled
        needsApproval = service.needsApproval
    }
}

// MARK: - About

/// App icon, version, licence, source link and updates.
private struct AboutCard: View {
    @Binding var autoUpdate: Bool
    let actions: SettingsActions

    var body: some View {
        SettingsCard(spacing: 0, padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18), fillsHeight: true) {
            HStack(spacing: 14) {
                Image(.appIconArt)
                    .resizable()
                    .frame(width: 52, height: 52)
                    // drop-shadow(0 3px 6px): a drop-shadow blur is a standard deviation.
                    .lidlessShadow(ShadowLayer(color: Palette.appIconShadow, radius: 6, y: 3))
                    .accessibilityLabel(Text("Lidless app icon", comment: "Accessibility label of the app icon in Settings › Keys & App › About"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lidless \(Self.version)", comment: "App name and version in Settings › Keys & App › About; the variable is the version, e.g. 0.1.0")
                        .lidlessStyle(.appTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineBox(.appTitle)
                        // The About card's heading.
                        .accessibilityAddTraits(.isHeader)
                    licenceLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                autoUpdateToggle
                Button(action: actions.checkForUpdates) {
                    Text("Check Now", comment: "Button in Settings › Keys & App › About: checks for a newer version")
                }
                .buttonStyle(SecondaryButtonStyle(size: .medium))
            }
            // The card grows to fill the tab (flex-grow); its row stays centred.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// "Free and open source · MIT License · Source on GitHub": one sentence
    /// for translators, with the link as a real button so Tab reaches it.
    private var licenceLine: some View {
        let line = LicenceLine.localized
        return HStack(spacing: 0) {
            licenceText(line.before)
            Button(action: actions.openSourceOnGitHub) {
                Text(verbatim: line.link)
                    .lidlessStyle(.smallStrong)
            }
            .buttonStyle(InlineLinkButtonStyle())
            licenceText(line.after)
        }
    }

    @ViewBuilder private func licenceText(_ text: String) -> some View {
        if !text.isEmpty {
            Text(verbatim: text)
                .lidlessStyle(.small)
                .foregroundStyle(Palette.text4)
                .lineBox(.small)
        }
    }

    private var autoUpdateToggle: some View {
        let title = Text("Auto-update", comment: "Toggle in Settings › Keys & App › About")
        return HStack(spacing: 8) {
            title
                .lidlessStyle(.description)
                .foregroundStyle(Palette.text2)
                .lineBox(.description)
                .accessibilityHidden(true)
            Toggle(isOn: $autoUpdate) { title }
                .toggleStyle(PillToggleStyle(size: .small))
        }
    }

    /// CFBundleShortVersionString, e.g. "0.1.0".
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
}

/// The About card's licence sentence, split around its link.
private struct LicenceLine {
    let before: String
    let link: String
    let after: String

    /// From one localized Markdown string; the `[bracketed](source)` words are the link.
    static var localized: LicenceLine {
        let text = AttributedString(
            localized: "Free and open source · MIT License · [Source on GitHub](source)",
            comment: "Licence line in Settings › Keys & App › About. Keep the Markdown link: the words in [brackets] become a link to the source code; keep “(source)” as is."
        )
        var before = "", link = "", after = ""
        for run in text.runs {
            let piece = String(text[run.range].characters)
            if run.link != nil {
                link += piece
            } else if link.isEmpty {
                before += piece
            } else {
                after += piece
            }
        }
        // A translation that lost the link would lose the button: use English.
        guard !link.isEmpty else {
            return LicenceLine(before: "Free and open source · MIT License · ", link: "Source on GitHub", after: "")
        }
        return LicenceLine(before: before, link: link, after: after)
    }
}

// MARK: - Shared

private extension TypeStyle {
    /// 11.5/600: the "Open Login Items" link.
    static let helperStrong = TypeStyle(size: 11.5, weight: .semibold, design: .default, cssLineHeight: 13, nativeLineHeight: 14)
}

/// The design's inline link: gold-brown text (#8A5A00), darker on hover
/// (`a:hover` #5A3B00) and while pressed.
private struct InlineLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InlineLink(configuration: configuration)
    }

    private struct InlineLink: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovered || configuration.isPressed ? Palette.brown : Palette.goldDeep)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .accessibilityAddTraits(.isLink)
        }
    }
}

#if DEBUG
private final class PreviewLaunchAtLogin: LaunchAtLogin {
    var isAvailable = true
    var isEnabled = true
    var needsApproval = false
    func setEnabled(_ enabled: Bool) -> Bool { isEnabled = enabled; return true }
    func openLoginItemsSettings() {}
}

#Preview("Keys & App") {
    let model = AppModel()
    KeysTab(model: model, preferences: model.preferences, actions: SettingsActions(), launchAtLogin: PreviewLaunchAtLogin())
        .padding(EdgeInsets(top: 0, leading: 18, bottom: 18, trailing: 18))
        .frame(width: 878, height: 662)
        .background { SettingsWindowBackground() }
}
#endif
