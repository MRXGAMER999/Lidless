import CoreGraphics
import Foundation
import LidlessCore

// Seams between DeskModeController and the parts that touch the system, so
// tests can swap in fakes. Main-actor (the app's default isolation) unless
// marked otherwise; completions are delivered on the main actor.
// Frozen contract for Phase 3: change only with the controller's owner.

/// Turns the built-in screen off and on with one method.
protocol BuiltInSwitch: AnyObject {
    /// Runs the change off the main thread with a timeout, then verifies it:
    /// disconnect waits (up to 4 s) for the panel to leave the online list;
    /// black out checks the cover window is on screen. `completion(true)` only
    /// when verified.
    func disable(displayID: CGDirectDisplayID, uuid: String?, completion: @escaping @MainActor (Bool) -> Void)
    /// Enables the panel (session scope for disconnect, so the session baseline
    /// says "on"), re-finding it by UUID if its ID changed, then verifies it is
    /// online. Safe when already on. Never refuses.
    func enable(displayID: CGDirectDisplayID?, uuid: String?, completion: @escaping @MainActor (Bool) -> Void)
    /// Best-effort enable for the launch, quit, signal and power-off paths:
    /// blocks at most `timeout` seconds. True only when the display list
    /// confirms the panel online (black out: when its cover is down), never on
    /// a return code alone. The composite asks both switches.
    func enableNow(displayID: CGDirectDisplayID?, uuid: String?, timeout: TimeInterval) -> Bool
}

/// The keep-or-revert prompt.
protocol ConfirmationPresenter: AnyObject {
    /// Shows (or updates) the prompt on the display with this UUID (nil: the
    /// main display). `deadline` is `ProcessInfo.systemUptime` seconds. The
    /// presenter never decides anything: the machine's ticks enforce the deadline.
    func show(deadline: TimeInterval, total: TimeInterval, onDisplayUUID: String?, keep: @escaping @MainActor () -> Void, revert: @escaping @MainActor () -> Void)
    func hide()
}

/// The sidecar watchdog process.
protocol WatchdogLink: AnyObject {
    /// Spawns the sidecar if needed (`<executable> --watchdog <pid>`, own
    /// session) and sends "arm". Starts the main-run-loop heartbeat. False when
    /// no sidecar is running to receive it: Desk Mode then doesn't engage.
    @discardableResult
    func arm(displayID: CGDirectDisplayID, method: DeskModeMethod, uuid: String?) -> Bool
    func setDeadline(_ deadline: TimeInterval?)
    /// Sends "bye", stops the heartbeat and lets the sidecar exit.
    func disarm()
}

/// The crash marker file in Application Support.
protocol CrashMarkerStore: AnyObject {
    /// Atomic write. Failures are logged, never thrown: Desk Mode still works.
    func write(_ marker: CrashMarker)
    /// The marker, and whether a file exists at all (a damaged file reads nil).
    func read() -> (marker: CrashMarker?, fileExists: Bool)
    func clear()
    /// `kern.bootsessionuuid`, nil when unreadable.
    var currentBootSession: String? { get }
}

/// Informational notifications. Never part of the safety path.
protocol DeskModeNotifier: AnyObject {
    func restored(_ reason: DeskModeRestoreReason)
    /// At launch, after restoring a panel a crashed run left off.
    func recoveredAfterCrash()
}

/// Keeps App Nap from coalescing the safety timers while Desk Mode is on.
protocol ActivityHolder: AnyObject {
    func hold(_ on: Bool)
}

/// Notices another display switching mode while the built-in turns off or
/// on. Diagnostic only: it reads modes and never changes a display.
protocol DisplayModeWatching: AnyObject {
    /// Before a disable or enable is sent: remembers every online display's mode.
    func willSwitch()
    /// After the switch was verified: compares once macOS has settled.
    func didSwitch()
}

/// Watches nothing. The default, so test rigs don't need one.
final class NoDisplayModeWatch: DisplayModeWatching {
    func willSwitch() {}
    func didSwitch() {}
}

/// The in-process hang watchdog's switch.
protocol HangWatchdogControl: AnyObject {
    /// Armed while Desk Mode is on or switching: a main thread stuck for
    /// about 8 s then aborts the process, so the sidecar and WindowServer restore.
    func setArmed(_ armed: Bool)
}
