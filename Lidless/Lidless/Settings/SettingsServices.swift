import Foundation
import LidlessCore

// Seams for Phase 5 (Settings, onboarding, launch at login, App Intents).
// Frozen contract; the settings-shell agent implements the concrete classes.

/// Opens and closes the app's windows.
protocol WindowPresenter: AnyObject {
    /// Shows the Settings window on `tab`, bringing the app forward.
    func showSettings(_ tab: SettingsTab)
    /// Shows onboarding from step 1.
    func showOnboarding()
    /// Opens the menu bar popover (after onboarding's "Start Using Lidless").
    func showPopover()
}

/// "Start Lidless when I log in". Reads `SMAppService.mainApp.status` every
/// time (never a shadow flag); unavailable below macOS 13.
protocol LaunchAtLogin: AnyObject {
    var isAvailable: Bool { get }
    var isEnabled: Bool { get }
    /// The user must approve it in System Settings › Login Items.
    var needsApproval: Bool { get }
    /// Returns false (and logs) when registration failed.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool
    func openLoginItemsSettings()
}

/// Things the Settings window and onboarding ask the app to do.
struct SettingsActions {
    /// "Test the safety net": turns Desk Mode on with the keep-or-revert
    /// prompt forced, so the user sees the screen come back.
    var testSafetyNet: () -> Void = {}
    /// "Try It" / onboarding: calls `pressed` once at the next press of the
    /// panic key. The press still does everything the panic key does (brings
    /// the built-in back, ends Boost and the external shades); it never turns
    /// anything off. Waiting survives shortcut changes.
    var awaitPanicKey: (_ pressed: @escaping @MainActor () -> Void) -> Void = { _ in }
    /// Ends every wait: two screens waiting at once (Settings and onboarding)
    /// share it, so one cancelling cancels both.
    var cancelAwaitPanicKey: () -> Void = {}
    /// Pauses global hot keys (except the panic key) while a recorder listens.
    var setRecordingShortcut: (Bool) -> Void = { _ in }
    /// System Settings › Displays.
    var openDisplaysSettings: () -> Void = {}
    /// Asks for Input Monitoring when "Keep pressing to boost" is switched on.
    var requestKeyPermission: () -> Void = {}
    /// Updater (Phase 6 wires Sparkle); no-op until then.
    var checkForUpdates: () -> Void = {}
    var openSourceOnGitHub: () -> Void = {}
    /// Input Monitoring for "Keep pressing to boost", read live each call
    /// (never prompts).
    var keyPermission: () -> InputMonitoringPermission = { .notDetermined }
    /// System Settings › Privacy & Security › Input Monitoring.
    var openInputMonitoringSettings: () -> Void = {}
}
