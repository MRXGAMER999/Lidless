import CoreGraphics
import LidlessCore

// Seams between the live system monitors and SystemController, so tests can
// swap in fakes. Everything here is main-actor (the app's default isolation):
// implementations hop to the main queue before calling a handler.
// Phase 2 only reads. Nothing behind these protocols may change a display or
// its brightness.

/// Reads every online display.
protocol DisplayReader: AnyObject {
    /// One entry per ID in `CGGetOnlineDisplayList`. About 1 ms; the first
    /// call after launch takes about 60 ms.
    func snapshot() -> [DisplayFacts]
}

/// Says when the display arrangement may have changed.
protocol DisplayChangeSource: AnyObject {
    /// `onChange` runs on the main actor, coalesced: 0.3 s after the last event,
    /// and at most 1 s after the first. Starting twice is a no-op.
    func start(onChange: @escaping @MainActor () -> Void)
    /// Stops observing and drops a pending call. Safe when not started.
    func stop()
}

/// Something that happened that may change what `SystemReader` returns.
enum SystemEvent: Sendable, Equatable {
    case lid
    case power
    case thermal
    case didWake
    case screensDidSleep
    case screensDidWake
    case sessionDidBecomeActive
}

/// Reads lid, power and heat. Each read is well under 1 ms, so callers
/// re-read everything on every event.
protocol SystemReader: AnyObject {
    func lid() -> LidState
    func power() -> PowerSource
    func thermal() -> ThermalLevel
    /// `hw.model`, such as "Mac17,9"; nil when unreadable. Constant.
    var modelIdentifier: String? { get }
    /// macOS exports the SkyLight calls Desk Mode needs. Checked, never called. Constant.
    var deskModeCallsPresent: Bool { get }
}

/// Reports system events as they happen.
protocol SystemEventSource: AnyObject {
    /// `handler` runs on the main actor once per event, not coalesced.
    /// Starting twice is a no-op.
    func start(handler: @escaping @MainActor (SystemEvent) -> Void)
    /// Safe when not started.
    func stop()
}

/// Reads brightness through DisplayServices. Never sets it.
protocol BrightnessReader: AnyObject {
    /// The built-in panel's device-tree constants; fields are nil when absent.
    /// Read once, then cached.
    func panelInfo() -> PanelBrightnessInfo
    /// The slider level of a display macOS dims itself, or nil when it can't be
    /// read (external monitors, offline displays, symbols missing).
    func level(of display: CGDirectDisplayID) -> BrightnessLevelReading?
    /// Calls `onChange` on the main actor, coalesced to about 20 Hz, when the
    /// level of `display` may have changed. Replaces an earlier observation.
    /// Returns false when macOS offers no notification; poll instead.
    @discardableResult
    func observe(_ display: CGDirectDisplayID, onChange: @escaping @MainActor () -> Void) -> Bool
    /// Safe when not observing.
    func stopObserving()
}
