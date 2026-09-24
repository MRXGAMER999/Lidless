import AppKit
import LidlessCore
import os

/// Opens the Settings window and onboarding, each created on first use and
/// reused after that, and keeps the app's activation policy in step with them.
///
/// Lidless is an accessory app (`LSUIElement`): no Dock tile, no menu bar. While
/// one of these windows is open it becomes a regular app, so the window gets a
/// Dock tile, ⌘-Tab and the main menu (⌘, ⌘W, the Edit menu for text fields);
/// once the last one closes it goes back to accessory (platform.md §1.4).
final class WindowCoordinator: NSObject, WindowPresenter {
    private let model: AppModel
    private let actions: SettingsActions
    private let launchAtLogin: any LaunchAtLogin
    private let openPopover: () -> Void
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Windows")

    private var settingsWindow: SettingsWindow?
    private var settingsNavigation: SettingsNavigation?
    private var onboarding: OnboardingWindowController?
    /// This coordinator switched the app to `.regular`, so it switches it back.
    private var isForeground = false

    /// - Parameter openPopover: Opens the menu bar popover.
    init(model: AppModel, actions: SettingsActions, launchAtLogin: any LaunchAtLogin, openPopover: @escaping () -> Void) {
        self.model = model
        self.actions = actions
        self.launchAtLogin = launchAtLogin
        self.openPopover = openPopover
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    // MARK: WindowPresenter

    func showSettings(_ tab: SettingsTab) {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsNavigation?.tab = tab
        comeForward()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        let controller = onboarding ?? OnboardingWindowController(
            model: model,
            preferences: model.preferences,
            actions: actions,
            launchAtLogin: launchAtLogin,
            onFinish: { [weak self] in self?.onboardingFinished() }
        )
        onboarding = controller
        comeForward()
        controller.show()
    }

    func showPopover() {
        openPopover()
    }

    // MARK: Private

    private func makeSettingsWindow() -> SettingsWindow {
        let navigation = SettingsNavigation()
        let window = SettingsWindow(
            navigation: navigation,
            model: model,
            actions: actions,
            launchAtLogin: launchAtLogin
        )
        settingsNavigation = navigation
        settingsWindow = window
        return window
    }

    /// "Start Using Lidless": the onboarding window has closed by now.
    private func onboardingFinished() {
        model.preferences.general.onboardingCompleted = true
        log.info("Onboarding finished")
        // After the activation policy settles (`windowWillClose` switches it on
        // the next turn), so the panel isn't dismissed by the app deactivating.
        perform(#selector(showPopoverAfterOnboarding), with: nil, afterDelay: 0.3)
    }

    @objc private func showPopoverAfterOnboarding() {
        showPopover()
    }

    private func comeForward() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            isForeground = true
        }
        // Best effort: activation can be refused (SDK: "does not guarantee that
        // the app will be activated at all"); the window still comes up.
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Any window closing: Settings or onboarding stop waiting for the panic
    /// key (a closed window may never see its views disappear), and once the
    /// last titled window is gone, back to accessory. That is checked on the
    /// next turn, when the closing window is no longer visible.
    @objc private func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, isSettingsOrOnboarding(window) {
            // Ends every wait, also one the other window may hold (the
            // contract has no tokens); the check mark is only shown while open.
            actions.cancelAwaitPanicKey()
        }
        guard isForeground else { return }
        perform(#selector(returnToBackgroundIfIdle), with: nil, afterDelay: 0)
    }

    private func isSettingsOrOnboarding(_ window: NSWindow) -> Bool {
        if window === settingsWindow { return true }
        // The onboarding window's class is private to its controller, its delegate.
        guard let onboarding, let delegate = window.delegate else { return false }
        return delegate === onboarding
    }

    @objc private func returnToBackgroundIfIdle() {
        guard isForeground else { return }
        // Panels (the popover, the keep-or-revert prompt, overlays) don't need
        // a Dock tile; a minimized window does, or it could never come back.
        let stillOpen = NSApp.windows.contains { window in
            window.styleMask.contains(.titled) && !(window is NSPanel) && (window.isVisible || window.isMiniaturized)
        }
        guard !stillOpen else { return }
        isForeground = false
        NSApp.setActivationPolicy(.accessory)
    }
}
