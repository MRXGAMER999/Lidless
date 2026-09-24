import AppKit
import Combine
import LidlessCore
import SwiftUI

// ShortcutRecorder: a clickable shortcut that records new keys (design-spec §4,
// §7.4 "Quick keys" and the panic hero's "Change Keys").
//
//     ShortcutRecorder(
//         shortcut: Binding<KeyShortcut?>,   // $preferences.shortcuts[slot] works
//         slot: ShortcutSet.Slot,
//         shortcuts: ShortcutSet,            // the whole set, for conflicts
//         allowsClearing: Bool,              // false for .panic
//         setRecording: @escaping (Bool) -> Void,  // SettingsActions.setRecordingShortcut
//         style: .keyCombo,                  // or .changeKeysButton for the dark hero
//         problem: $text                     // optional; .changeKeysButton only
//     )
//
// Click (or Space with keyboard navigation) to listen: "Press keys…", held
// modifiers show as they go down. Esc cancels, Tab moves on, ⌫ clears where
// allowed; a combination is checked with `ShortcutSet.problem(assigning:to:)`
// and a refusal shows under the recorder (or goes to `problem`, for the
// caller to show under its row of buttons) while it keeps listening. Only one
// recorder listens at a time. While listening, global hot keys other than the
// panic key are paused through `setRecording`, so their keys can be recorded.
//
// The panic key stays registered with Carbon, which swallows its keys before
// any app sees them: pressing the panic combination while recording another
// slot fires the panic key instead of showing "taken".

/// A clickable shortcut that records new keys into `shortcut`.
struct ShortcutRecorder: View {
    enum Style {
        /// Medium light keycaps with no gold key, as in "Quick keys".
        case keyCombo
        /// "Change Keys" on the panic hero; the hero draws the keys itself.
        case changeKeysButton
    }

    @Binding private var shortcut: KeyShortcut?
    private let slot: ShortcutSet.Slot
    private let shortcuts: ShortcutSet
    private let allowsClearing: Bool
    private let setRecording: (Bool) -> Void
    private let style: Style
    private let problem: Binding<String?>?

    @StateObject private var recorder = ShortcutRecorderModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        shortcut: Binding<KeyShortcut?>,
        slot: ShortcutSet.Slot,
        shortcuts: ShortcutSet,
        allowsClearing: Bool,
        setRecording: @escaping (Bool) -> Void,
        style: Style = .keyCombo,
        problem: Binding<String?>? = nil
    ) {
        _shortcut = shortcut
        self.slot = slot
        self.shortcuts = shortcuts
        self.allowsClearing = allowsClearing
        self.setRecording = setRecording
        self.style = style
        self.problem = problem
    }

    var body: some View {
        Group {
            switch style {
            case .keyCombo:
                VStack(alignment: .trailing, spacing: 6) {
                    recorderButton
                    if let rejection = recorder.rejection {
                        problemText(rejection)
                            .foregroundStyle(Palette.thermalCritical)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 240, alignment: .trailing)
                    }
                }
            case .changeKeysButton:
                if let problem {
                    // The hero shows it under both of its buttons ("Try It"
                    // sits beside this one), where the hero can grow.
                    recorderButton
                        .onAppearAndChange(of: recorder.rejection.map(ShortcutRecorderModel.message(for:))) { message in
                            if problem.wrappedValue != message { problem.wrappedValue = message }
                        }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        recorderButton
                        if let rejection = recorder.rejection {
                            problemText(rejection)
                                .foregroundStyle(Palette.goldOnDark)
                        }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: recorder.isListening)
        .onDisappear { recorder.cancel() }
    }

    private var recorderButton: some View {
        Button(action: toggle) {
            switch style {
            case .keyCombo: KeysLabel(shortcut: shortcut, recorder: recorder)
            case .changeKeysButton: ChangeKeysLabel(isListening: recorder.isListening)
            }
        }
        .buttonStyle(RecorderButtonStyle(style: style, isListening: recorder.isListening))
        .background(RecorderAnchor(recorder: recorder))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(Text(ShortcutRecorderModel.instructions(allowsClearing: allowsClearing)))
    }

    private func toggle() {
        if recorder.isListening {
            recorder.cancel()
        } else {
            let binding = $shortcut
            recorder.start(ShortcutRecorderModel.Request(
                slot: slot,
                shortcuts: shortcuts,
                allowsClearing: allowsClearing,
                commit: { binding.wrappedValue = $0 },
                setRecording: setRecording
            ))
        }
    }

    private func problemText(_ rejection: ShortcutCapture.Rejection) -> some View {
        Text(ShortcutRecorderModel.message(for: rejection))
            .lidlessStyle(.helper)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true) // Announced, and part of the button's value.
    }

    private var accessibilityLabel: Text {
        switch style {
        case .keyCombo: Text(ShortcutRecorderModel.name(of: slot))
        case .changeKeysButton: Text("Change Keys", comment: "Panic key hero: button that records new keys for the panic key")
        }
    }

    private var accessibilityValue: Text {
        if recorder.isListening {
            let listening = String(localized: "Listening for new keys", comment: "VoiceOver value of a shortcut recorder while it waits for keys")
            guard let rejection = recorder.rejection else { return Text(listening) }
            let message = ShortcutRecorderModel.message(for: rejection)
            return Text(String(localized: "Listening for new keys. \(message)", comment: "VoiceOver value of a shortcut recorder that refused the keys and keeps listening; the variable is why, e.g. “macOS already uses these keys.”"))
        }
        guard let shortcut else {
            return Text("Not set", comment: "Shortcut recorder with no shortcut (the user removed it)")
        }
        return Text(verbatim: recorder.labels(for: shortcut).spokenName)
    }
}

// MARK: - Labels

/// The keys as medium light keycaps, "Not set", or "Press keys…" while listening.
private struct KeysLabel: View {
    let shortcut: KeyShortcut?
    @ObservedObject var recorder: ShortcutRecorderModel
    @Environment(\.colorSchemeContrast) private var contrast

    /// About four medium keycaps, so the row doesn't jump when listening starts.
    private static let listeningMinWidth: CGFloat = 4 * 26 + 3 * 4

    var body: some View {
        if recorder.isListening {
            Group {
                if recorder.heldModifiers.isEmpty {
                    Text("Press keys…", comment: "Shortcut recorder while it waits for the new keys")
                        .lidlessStyle(.smallStrong)
                } else {
                    Text(verbatim: Self.symbols(recorder.heldModifiers) + "…")
                        .lidlessStyle(.keyM)
                }
            }
            .foregroundStyle(Palette.calloutText)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: Self.listeningMinWidth, minHeight: 26, maxHeight: 26)
            .background {
                Capsule()
                    .fill(Palette.calloutFill)
                    .overlay { Capsule().strokeBorder(Palette.goldBorderSelected, lineWidth: contrast == .increased ? 2 : 1.5) }
            }
        } else if let shortcut {
            HStack(spacing: 4) {
                ForEach(Array(recorder.labels(for: shortcut).keycaps.enumerated()), id: \.offset) { item in
                    KeyCap(label: item.element, size: .medium)
                }
            }
        } else {
            Text("Not set", comment: "Shortcut recorder with no shortcut (the user removed it)")
                .lidlessStyle(.small)
                .foregroundStyle(Palette.text4)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 26, maxHeight: 26)
                .background {
                    // Stronger with Increase Contrast (the token's own variant).
                    Capsule().strokeBorder(Palette.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
        }
    }

    /// "⌃⌥", the held modifiers in macOS order.
    static func symbols(_ modifiers: KeyShortcut.Modifiers) -> String {
        KeyShortcut(keyCode: 0, keyLabel: "", modifiers: modifiers).keycaps(keyLabel: "").joined()
    }
}

/// "Change Keys", or "Press keys…" while listening.
private struct ChangeKeysLabel: View {
    let isListening: Bool

    var body: some View {
        if isListening {
            Text("Press keys…", comment: "Shortcut recorder while it waits for the new keys")
        } else {
            Text("Change Keys", comment: "Panic key hero: button that records new keys for the panic key")
        }
    }
}

private struct RecorderButtonStyle: ButtonStyle {
    let style: ShortcutRecorder.Style
    let isListening: Bool

    func makeBody(configuration: Configuration) -> some View {
        switch style {
        case .keyCombo:
            configuration.label
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
        case .changeKeysButton:
            GhostOnDarkButtonStyle().makeBody(configuration: configuration)
                .overlay {
                    Capsule()
                        .strokeBorder(Palette.gold, lineWidth: 1.5)
                        .opacity(isListening ? 1 : 0)
                        .allowsHitTesting(false)
                }
        }
    }
}

/// An empty AppKit view behind the recorder: where it is in its window, so a
/// click elsewhere can end listening, and which window to watch.
private struct RecorderAnchor: NSViewRepresentable {
    let recorder: ShortcutRecorderModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        recorder.anchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        recorder.anchor = nsView
    }
}

// MARK: - Model

/// Listens for keys on behalf of one `ShortcutRecorder`.
///
/// A local `NSEvent` monitor (key downs, modifier changes, clicks) exists only
/// while listening. Listening ends on Esc, Tab, a recorded or cleared shortcut,
/// a click outside the recorder, the window losing key status or closing,
/// the view going away, or another recorder starting.
final class ShortcutRecorderModel: ObservableObject {
    /// What to record into, captured when listening starts.
    struct Request {
        let slot: ShortcutSet.Slot
        let shortcuts: ShortcutSet
        let allowsClearing: Bool
        /// Receives the new shortcut, or nil when it was cleared.
        let commit: (KeyShortcut?) -> Void
        let setRecording: (Bool) -> Void
    }

    /// `NSEvent`'s local monitor, or a fake in tests.
    struct EventMonitor {
        var add: (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
        var remove: (Any) -> Void

        static let local = EventMonitor(
            add: { NSEvent.addLocalMonitorForEvents(matching: $0, handler: $1) },
            remove: { NSEvent.removeMonitor($0) }
        )
    }

    static let monitoredEvents: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    @Published private(set) var isListening = false
    /// Modifiers held down while listening, shown as they are pressed.
    @Published private(set) var heldModifiers: KeyShortcut.Modifiers = []
    /// Why the last keys were refused; cleared when listening ends.
    @Published private(set) var rejection: ShortcutCapture.Rejection?

    /// The recorder's AppKit stand-in (`RecorderAnchor`).
    weak var anchor: NSView?

    /// The one recorder listening now.
    private static weak var listening: ShortcutRecorderModel?

    private let monitor: EventMonitor
    private let notificationCenter: NotificationCenter
    private let layoutLabel: (_ keyCode: UInt16, _ commandHeld: Bool) -> String?
    private let displayLabel: (KeyShortcut) -> String
    private let announce: @MainActor (String) -> Void

    private var request: Request?
    private var monitorToken: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var layoutObserver: KeyboardLayoutObserver?
    /// Labels per shortcut for the current keyboard layout, so views don't call
    /// Carbon on every redraw. Emptied when the layout changes.
    private var labelCache: [KeyShortcut: ShortcutLabels] = [:]

    /// - Parameters:
    ///   - layoutLabel: What a key types on the current layout (tests pass a fake).
    ///   - displayLabel: How a saved shortcut's key is named now.
    ///   - announce: Speaks through VoiceOver.
    init(
        monitor: EventMonitor = .local,
        notificationCenter: NotificationCenter = .default,
        layoutLabel: @escaping (_ keyCode: UInt16, _ commandHeld: Bool) -> String? = { KeyboardLayout.label(forKeyCode: $0, commandHeld: $1) },
        displayLabel: @escaping (KeyShortcut) -> String = { $0.displayKeyLabel },
        observesKeyboardLayout: Bool = true,
        announce: @escaping @MainActor (String) -> Void = ShortcutRecorderModel.postAnnouncement
    ) {
        self.monitor = monitor
        self.notificationCenter = notificationCenter
        self.layoutLabel = layoutLabel
        self.displayLabel = displayLabel
        self.announce = announce
        if observesKeyboardLayout {
            layoutObserver = KeyboardLayoutObserver { [weak self] in self?.keyboardLayoutDidChange() }
        }
    }

    deinit {
        // SwiftUI calls onDisappear first; this only guards against a missed
        // one leaving the hot keys paused and a monitor behind.
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { cancel() }
    }

    // MARK: Listening

    func start(_ request: Request) {
        if isListening { cancel() }
        if let other = Self.listening, other !== self { other.cancel() }
        self.request = request
        isListening = true
        heldModifiers = []
        rejection = nil
        Self.listening = self
        monitorToken = monitor.add(Self.monitoredEvents) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
        observeWindow()
        request.setRecording(true)
        announce(Self.instructions(allowsClearing: request.allowsClearing))
    }

    /// Stops listening and keeps the old shortcut.
    func cancel() {
        guard isListening else { return }
        let request = request
        self.request = nil
        isListening = false
        heldModifiers = []
        rejection = nil
        if Self.listening === self { Self.listening = nil }
        if let monitorToken { monitor.remove(monitorToken) }
        monitorToken = nil
        for observer in windowObservers { notificationCenter.removeObserver(observer) }
        windowObservers = []
        request?.setRecording(false)
    }

    // MARK: Events

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            let swallow = handleKeyDown(keyCode: event.keyCode, flags: event.modifierFlags, isRepeat: event.isARepeat)
            return swallow ? nil : event
        case .flagsChanged:
            handleFlagsChanged(event.modifierFlags)
            return event
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            handleMouseDown(in: event.window, at: event.locationInWindow)
            return event
        default:
            return event
        }
    }

    /// Acts on a key down. Returns whether to swallow it (everything but the
    /// Tab that moves focus on).
    @discardableResult
    func handleKeyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool = false) -> Bool {
        guard isListening, let request else { return false }
        guard !isRepeat else { return true }
        let modifiers = HotKeyCenter.modifiers(flags)
        let outcome = ShortcutCapture.keyDown(
            keyCode: keyCode,
            modifiers: modifiers,
            layoutLabel: layoutLabel(keyCode, modifiers.contains(.command)),
            slot: request.slot,
            shortcuts: request.shortcuts,
            allowsClearing: request.allowsClearing
        )
        switch outcome {
        case .modifiers(let held):
            heldModifiers = held
        case .cancel:
            cancel()
        case .moveFocus:
            cancel()
            return false
        case .clear:
            cancel()
            request.commit(nil)
            announce(String(localized: "Shortcut removed.", comment: "VoiceOver announcement after Delete removed a shortcut in the recorder"))
        case .rejected(let reason):
            rejection = reason
            announce(Self.message(for: reason))
        case .record(let shortcut):
            cancel()
            request.commit(shortcut)
            let spoken = labels(for: shortcut).spokenName
            announce(String(localized: "Shortcut set to \(spoken).", comment: "VoiceOver announcement after recording a shortcut. The variable is the spoken keys, e.g. “Control Option Command K”"))
        case .ignore:
            break
        }
        return true
    }

    func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard isListening else { return }
        if case .modifiers(let held) = ShortcutCapture.flagsChanged(modifiers: HotKeyCenter.modifiers(flags)) {
            heldModifiers = held
        }
    }

    /// A click anywhere but the recorder ends listening. A click on it is left
    /// to the button, which toggles listening off.
    func handleMouseDown(in window: NSWindow?, at locationInWindow: NSPoint) {
        guard isListening else { return }
        if let anchor, let window, anchor.window === window,
           anchor.bounds.contains(anchor.convert(locationInWindow, from: nil)) {
            return
        }
        cancel()
    }

    private func observeWindow() {
        guard let window = anchor?.window else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            // AppKit posts these on the main thread.
            windowObservers.append(notificationCenter.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
    }

    // MARK: Labels

    /// `shortcut`'s keycaps and spoken name on the current keyboard layout.
    func labels(for shortcut: KeyShortcut) -> ShortcutLabels {
        if let cached = labelCache[shortcut] { return cached }
        let labels = ShortcutLabels(shortcut, keyLabel: displayLabel(shortcut))
        labelCache[shortcut] = labels
        return labels
    }

    func keyboardLayoutDidChange() {
        labelCache = [:]
        objectWillChange.send()
    }

    // MARK: Copy

    /// What each slot does, as the Settings rows name it.
    static func name(of slot: ShortcutSet.Slot) -> String {
        switch slot {
        case .panic: String(localized: "Panic key", comment: "Name of the shortcut that always brings the built-in screen back")
        case .toggleDeskMode: String(localized: "Desk Mode on or off", comment: "Settings › Keys & App › Quick keys: row for the Desk Mode shortcut")
        case .toggleBoost: String(localized: "Boost on or off", comment: "Settings › Keys & App › Quick keys: row for the Boost shortcut")
        }
    }

    /// Why keys were refused, shown under the recorder and announced.
    static func message(for rejection: ShortcutCapture.Rejection) -> String {
        switch rejection {
        case .cannotClear:
            String(localized: "The panic key can be changed, never removed.", comment: "Shortcut recorder: Delete was pressed while recording the panic key")
        case .problem(.needsControlOrCommand):
            String(localized: "Add Control or Command to the keys.", comment: "Shortcut recorder: the keys pressed had neither Control nor Command")
        case .problem(.reservedBySystem):
            String(localized: "macOS already uses these keys.", comment: "Shortcut recorder: the keys pressed are a system shortcut such as Command-Q")
        case .problem(.taken(by: .panic)):
            String(localized: "The panic key already uses these keys.", comment: "Shortcut recorder: the keys pressed are the panic key's")
        case .problem(.taken(by: .toggleDeskMode)):
            String(localized: "Desk Mode on or off already uses these keys.", comment: "Shortcut recorder: the keys pressed are the Desk Mode shortcut's")
        case .problem(.taken(by: .toggleBoost)):
            String(localized: "Boost on or off already uses these keys.", comment: "Shortcut recorder: the keys pressed are the Boost shortcut's")
        }
    }

    /// Announced when listening starts, and the recorder's VoiceOver hint.
    static func instructions(allowsClearing: Bool) -> String {
        allowsClearing
            ? String(localized: "Press the new keys. Escape cancels, Delete removes the shortcut.", comment: "VoiceOver: how to use a shortcut recorder whose shortcut can be removed")
            : String(localized: "Press the new keys. Escape cancels.", comment: "VoiceOver: how to use the panic key's recorder, which can't be removed")
    }

    static func postAnnouncement(_ text: String) {
        guard let app = NSApp else { return }
        let element: Any = app.keyWindow.map { $0 as Any } ?? app
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

// MARK: - Previews

#Preview("Quick keys") {
    struct Demo: View {
        @State var shortcuts = ShortcutSet.defaults
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([ShortcutSet.Slot.toggleDeskMode, .toggleBoost], id: \.self) { slot in
                    HStack(alignment: .top) {
                        Text(verbatim: ShortcutRecorderModel.name(of: slot)).lidlessStyle(.body)
                        Spacer()
                        ShortcutRecorder(shortcut: $shortcuts[slot], slot: slot, shortcuts: shortcuts, allowsClearing: true, setRecording: { _ in })
                    }
                }
            }
            .padding(18)
            .frame(width: 413)
        }
    }
    return Demo()
}

#Preview("Change Keys") {
    struct Demo: View {
        @State var shortcuts = ShortcutSet.defaults
        var body: some View {
            ShortcutRecorder(shortcut: $shortcuts[.panic], slot: .panic, shortcuts: shortcuts, allowsClearing: false, setRecording: { _ in }, style: .changeKeysButton)
                .padding(32)
                .frame(width: 420, height: 160, alignment: .topLeading)
                .background(Palette.heroBackground)
        }
    }
    return Demo()
}
