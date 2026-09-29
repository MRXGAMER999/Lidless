import AppKit
import Combine
import LidlessCore
import SwiftUI

/// The first-run window (design-spec §8): Welcome, then "Learn your panic key".
///
/// A fixed 640×560 window with a hidden title bar that can only be closed
/// (minimize and zoom stay greyed out, as the boards draw them). Only the light
/// appearance is designed, so the window is always light.
///
/// Onboarding counts as done only through "Start Using Lidless": that applies
/// the two switches on step 2, closes the window and calls `onFinish` (which
/// marks it completed and opens the popover). Closing the window any other way
/// changes nothing, so it shows again at the next launch.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let preferences: PreferencesStore
    private let launchAtLogin: any LaunchAtLogin
    private let onFinish: () -> Void
    private let flow: OnboardingFlow
    private var window: NSWindow?

    init(
        model: AppModel,
        preferences: PreferencesStore,
        actions: SettingsActions,
        launchAtLogin: any LaunchAtLogin,
        onFinish: @escaping () -> Void
    ) {
        self.model = model
        self.preferences = preferences
        self.launchAtLogin = launchAtLogin
        self.onFinish = onFinish
        flow = OnboardingFlow(actions: actions)
        super.init()
        flow.finishHandler = { [weak self] in self?.finish() }
    }

    /// Shows onboarding from step 1, reusing the window if it is already open.
    func show() {
        let window = window ?? makeWindow()
        flow.start(
            turnOnWhenPluggedIn: Self.turnsOffWhenPluggedIn(preferences.deskMode.rule),
            // The board has it on for a first run; shown again later, it
            // starts from what is actually registered.
            launchAtLogin: launchAtLogin.isEnabled || !preferences.general.onboardingCompleted,
            showsLaunchAtLogin: launchAtLogin.isAvailable
        )
        if !window.isVisible { window.center() }
        // The presenter has made the app regular and active.
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    /// Another screen's cancel (Settings closing, its Try It timing out) ends
    /// every wait, so step 2 listens again whenever this window comes forward.
    func windowDidBecomeKey(_ notification: Notification) {
        flow.resumeListening()
    }

    func windowWillClose(_ notification: Notification) {
        flow.stopListening()
    }

    // MARK: Private

    private func makeWindow() -> NSWindow {
        let window = OnboardingWindow(rootView: OnboardingView(flow: flow, deskMode: model.deskMode))
        window.delegate = self
        flow.announce = { [weak window] text in
            ConfirmHUDView.postAnnouncement(text, from: window ?? NSApp as Any)
        }
        self.window = window
        return window
    }

    /// "Start Using Lidless".
    private func finish() {
        var rule = preferences.deskMode.rule
        Self.apply(turnOnWhenPluggedIn: flow.turnOnWhenPluggedIn, to: &rule)
        preferences.deskMode.rule = rule
        if flow.showsLaunchAtLogin, flow.launchAtLogin != launchAtLogin.isEnabled {
            // Settings › Keys & App shows the Login Items hint if it needs approval.
            launchAtLogin.setEnabled(flow.launchAtLogin)
        }
        // Close first, so the popover `onFinish` opens is the last thing shown.
        window?.close()
        onFinish()
    }

    /// "Turn on Desk Mode when I plug in a display" is the rule sentence's
    /// "turn the built-in screen [off]".
    static func turnsOffWhenPluggedIn(_ rule: DeskModeRule) -> Bool {
        rule.isEnabled && rule.action == .off
    }

    /// Same mapping as Settings' rule sentence: off disables the rule (the
    /// sentence then reads "[on]"), and choosing "[off]" there enables it again.
    static func apply(turnOnWhenPluggedIn: Bool, to rule: inout DeskModeRule) {
        if turnOnWhenPluggedIn {
            rule.isEnabled = true
            rule.action = .off
        } else {
            rule.isEnabled = false
        }
    }
}

/// The fixed-size, close-only window with a hidden title bar.
private final class OnboardingWindow: NSWindow {
    /// The boards draw the traffic lights 16 pt from the top, 12 pt tall.
    private static let buttonRowHeight: CGFloat = 44
    /// A title-bar button layout is waiting for the run loop (`windowButtonsNeedLayout`).
    private var buttonsLayoutQueued = false

    init(rootView: OnboardingView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: OnboardingMetrics.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        // Hidden, but kept for VoiceOver and the Window menu.
        title = String(localized: "Welcome to Lidless", comment: "Title of the onboarding window (hidden; read by VoiceOver and shown in the Window menu)")
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenNone]
        tabbingMode = .disallowed
        appearance = NSAppearance(named: .aqua)
        // Without the style bits AppKit already greys these out; say so anyway.
        standardWindowButton(.miniaturizeButton)?.isEnabled = false
        standardWindowButton(.zoomButton)?.isEnabled = false

        let hostingView = NSHostingView(rootView: rootView)
        if #available(macOS 13, *) {
            // The window's size is fixed; SwiftUI must never resize it.
            hostingView.sizingOptions = []
        }
        contentView = hostingView
        setContentSize(OnboardingMetrics.windowSize)

        observeWindowButtons()
        layOutWindowButtons()
    }

    // MARK: Traffic lights

    /// Moves the traffic lights down to the design's row, as `SettingsWindow`
    /// does: the title bar container grows to `buttonRowHeight` and the buttons
    /// centre in it, keeping their x. Does nothing if AppKit's view hierarchy
    /// isn't the expected one.
    private func layOutWindowButtons() {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(standardWindowButton)
        guard let first = buttons.first, let container = first.superview?.superview,
              let frameView = container.superview else { return }
        let height = Self.buttonRowHeight
        var frame = container.frame
        frame.size.height = height
        frame.origin.y = frameView.bounds.height - height
        if container.frame != frame { container.frame = frame }
        for button in buttons {
            guard let row = button.superview else { continue }
            let y = ((row.bounds.height - button.frame.height) / 2).rounded()
            if button.frame.origin.y != y { button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y)) }
        }
    }

    /// AppKit lays the title bar out again on its own (key changes, screen
    /// changes): follow every move of the container or a button.
    private func observeWindowButtons() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
            center.addObserver(self, selector: #selector(windowButtonsNeedLayout(_:)), name: name, object: self)
        }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(standardWindowButton)
        let views = buttons + [buttons.first?.superview?.superview].compactMap { $0 }
        for view in views {
            view.postsFrameChangedNotifications = true
            center.addObserver(self, selector: #selector(windowButtonsNeedLayout(_:)), name: NSView.frameDidChangeNotification, object: view)
        }
    }

    @objc private func windowButtonsNeedLayout(_ notification: Notification) {
        guard notification.name == NSView.frameDidChangeNotification else {
            layOutWindowButtons()
            return
        }
        // A button or its container moved inside AppKit's own title-bar layout
        // pass: moving them again from there can recurse. Lay out once, after it.
        guard !buttonsLayoutQueued else { return }
        buttonsLayoutQueued = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                self?.buttonsLayoutQueued = false
                self?.layOutWindowButtons()
            }
        }
    }
}

/// Onboarding's state: the step, the panic key check and the two switches,
/// which apply only when onboarding finishes.
final class OnboardingFlow: ObservableObject {
    enum Step: Int {
        case welcome
        case setup
    }

    @Published private(set) var step: Step = .welcome
    /// The panic key was pressed on step 2.
    @Published private(set) var panicKeyWorked = false
    @Published var turnOnWhenPluggedIn = true
    @Published var launchAtLogin = true
    /// False below macOS 13 (no `SMAppService`): the row is hidden.
    @Published private(set) var showsLaunchAtLogin = true
    /// Changes on every `start`, so the view begins fresh.
    @Published private(set) var presentation = 0

    var finishHandler: () -> Void = {}
    var announce: (String) -> Void = { _ in }

    private let actions: SettingsActions
    private var isListening = false
    /// Tells a stale panic-key callback (from before a cancel) from the current one.
    private var listenGeneration = 0

    init(actions: SettingsActions) {
        self.actions = actions
    }

    func start(turnOnWhenPluggedIn: Bool, launchAtLogin: Bool, showsLaunchAtLogin: Bool) {
        stopListening()
        step = .welcome
        panicKeyWorked = false
        self.turnOnWhenPluggedIn = turnOnWhenPluggedIn
        self.launchAtLogin = launchAtLogin
        self.showsLaunchAtLogin = showsLaunchAtLogin
        presentation &+= 1
    }

    /// "Continue": step 2 starts listening for the panic key ("Try it now").
    func goToSetup() {
        step = .setup
        listen()
    }

    /// "Back".
    func goToWelcome() {
        stopListening()
        step = .welcome
    }

    /// "Start Using Lidless".
    func finish() {
        stopListening()
        finishHandler()
    }

    /// Leaving step 2 or closing the window.
    func stopListening() {
        guard isListening else { return }
        isListening = false
        actions.cancelAwaitPanicKey()
    }

    /// Waits again on step 2 (a new wait; an older one still pending is
    /// ignored by the generation check).
    func resumeListening() {
        guard step == .setup, !panicKeyWorked else { return }
        isListening = false
        listen()
    }

    private func listen() {
        guard !panicKeyWorked, !isListening else { return }
        isListening = true
        listenGeneration &+= 1
        let generation = listenGeneration
        actions.awaitPanicKey { [weak self] in
            guard let self, isListening, listenGeneration == generation else { return }
            isListening = false
            panicKeyWorked = true
            announce(OnboardingCopy.panicKeyWorked)
        }
    }
}

#if DEBUG
extension OnboardingFlow {
    /// A flow already on `step`, for previews.
    static func preview(step: Step, panicKeyWorked: Bool = false) -> OnboardingFlow {
        let flow = OnboardingFlow(actions: SettingsActions())
        flow.step = step
        flow.panicKeyWorked = panicKeyWorked
        return flow
    }
}
#endif
