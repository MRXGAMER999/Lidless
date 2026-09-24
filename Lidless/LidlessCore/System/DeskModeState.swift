import Foundation

/// What Desk Mode is doing right now.
public enum DeskModeState: Sendable, Equatable {
    /// Desk Mode can't be used. The built-in screen is on.
    case unavailable(UnavailableReason)
    /// The built-in screen is on and Desk Mode could be turned on.
    case off
    /// The built-in screen is being turned off or back on.
    case switching(toOn: Bool)
    /// The built-in screen is off.
    case on(since: Date, trigger: Trigger)

    public enum UnavailableReason: Sendable, Equatable {
        /// No external display to move to.
        case needsDisplay
        /// The lid is closed, so the built-in screen is already dark.
        case lidClosed
        /// This Mac can't reliably bring the built-in screen back.
        case unsupportedMac
        /// macOS no longer offers the call Desk Mode relies on.
        case unsupportedSystem
    }

    public enum Trigger: Sendable, Equatable {
        /// Turned on from the popover, a shortcut or Shortcuts.
        case manual
        /// Turned on by the "When I plug in…" rule, when this display connected.
        case automatic(displayName: String)
    }

    /// True when the built-in screen is off, or about to be.
    public var isOn: Bool {
        switch self {
        case .on: true
        case .switching(let toOn): toOn
        case .off, .unavailable: false
        }
    }

    public var isAvailable: Bool {
        if case .unavailable = self { return false }
        return true
    }

    /// True while the built-in screen is being turned off or back on.
    public var isSwitching: Bool {
        if case .switching = self { return true }
        return false
    }
}
