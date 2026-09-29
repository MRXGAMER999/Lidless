import CoreGraphics
import Foundation
import LidlessCore

// Seams between BoostController / ExternalBrightnessController and the parts
// that touch the system. Main-actor (the app's default isolation); callbacks on
// the main actor. Frozen contract for Phase 4.

/// The EDR multiply overlay on the built-in screen.
extension BoostOverlay {
    func setHeadroomRequest(_ factor: Double) {}
}

protocol BoostOverlay: AnyObject {
    /// Puts the overlay on the screen of `displayID` (if not already there) and
    /// ramps its factor to `factor` over `rampSeconds`. Returns false when the
    /// screen isn't found or Metal isn't available.
    func show(on displayID: CGDirectDisplayID, factor: Double, rampSeconds: Double) -> Bool
    /// Ramps to 1 over `rampSeconds` (0 = at once), then removes the window.
    func hide(rampSeconds: Double)
    /// The factor Boost is heading for, so the engine can ask macOS for that
    /// headroom at once rather than only for the factor on screen.
    func setHeadroomRequest(_ factor: Double)
    var isShown: Bool { get }
    /// The screen's `maximumExtendedDynamicRangeColorComponentValue` while shown:
    /// after every screen-parameter change and on a light poll (1 s, 0.1 s while engaging).
    var onHeadroom: (@MainActor (Double) -> Void)? { get set }
    /// The window left the built-in screen or the screen went away; already removed.
    var onLost: (@MainActor () -> Void)? { get set }
}

/// Writes the built-in panel's native brightness through DisplayServices.
protocol BuiltInBrightnessWriter: AnyObject {
    /// Absolute level 0...1 (`DisplayServicesSetBrightness`). Coalesced to about
    /// 30 Hz with `BrightnessWriteFilter`. Returns false when unavailable.
    @discardableResult
    func setLevel(_ level: Double, of display: CGDirectDisplayID) -> Bool
    /// True when `level` read back now is the echo of our own recent write.
    func isEcho(_ level: Double) -> Bool
    /// Drops a coalesced level still waiting for its slot, so nothing reaches
    /// the panel once Desk Mode switches, displays reconfigure or the Mac sleeps.
    func cancelPending()
}

/// How an external display's brightness is changed.
nonisolated enum ExternalBrightnessMethod: Sendable, Equatable {
    /// macOS dims it itself (Apple displays): DisplayServices.
    case native
    /// DDC/CI over IOAVService, verified by a successful read.
    case ddc(maximum: UInt16)
    /// A black click-through overlay ("shade").
    case shade
    /// Not decided yet (probe in flight).
    case probing
}

/// Brightness for external displays.
protocol ExternalBrightnessControl: AnyObject {
    /// Starts probing new displays and forgets gone ones. `onChange` runs when a
    /// display's method or level changes (e.g. after a DDC read).
    func update(displays: [DisplayDescriptor])
    func method(for displayUUID: String) -> ExternalBrightnessMethod
    /// The last known level 0...1, if any (DDC reads it back; shades start at 1).
    func level(for displayUUID: String) -> Double?
    /// Applies a level 0...1. DDC writes are serialized per display and skipped
    /// while display changes are paused.
    func setLevel(_ level: Double, for displayUUID: String)
    /// Pauses DDC traffic (display reconfiguration, Desk Mode switching, sleep)
    /// until `resume`. Shades are kept but re-placed after resume.
    func pause()
    func resume(after delay: TimeInterval)
    /// Removes every shade (panic key, quit).
    func removeAllShades()
    var onChange: (@MainActor () -> Void)? { get set }
}

/// Input Monitoring, the only permission Lidless ever asks for.
nonisolated enum InputMonitoringPermission: Sendable, Equatable { case granted, denied, notDetermined }

/// The brightness keys, for "Keep pressing to boost".
protocol BrightnessKeySource: AnyObject {
    /// Input Monitoring status (`CGPreflightListenEventAccess`), no prompt.
    var permission: InputMonitoringPermission { get }
    /// Shows the system prompt once (`CGRequestListenEventAccess`).
    func requestPermission()
    /// Starts a listen-only tap for brightness key presses; false without permission.
    @discardableResult
    func start(handler: @escaping @MainActor (BrightnessKeyPolicy.Key) -> Void) -> Bool
    func stop()
}
