import Foundation

/// Whether Desk Mode can be offered, from what the system reports.
public enum DeskModeAvailability {
    public struct Inputs: Sendable, Equatable {
        /// `hw.model`, such as "Mac17,9".
        public var modelIdentifier: String?
        public var lid: LidState
        /// A built-in panel was seen this session, even if it is offline now.
        public var hasBuiltInPanel: Bool
        /// Wired externals Desk Mode could move to.
        public var usableExternalCount: Int
        /// macOS still exports the SkyLight calls Desk Mode uses.
        public var systemCallsPresent: Bool

        public init(modelIdentifier: String?, lid: LidState, hasBuiltInPanel: Bool, usableExternalCount: Int, systemCallsPresent: Bool) {
            self.modelIdentifier = modelIdentifier
            self.lid = lid
            self.hasBuiltInPanel = hasBuiltInPanel
            self.usableExternalCount = usableExternalCount
            self.systemCallsPresent = systemCallsPresent
        }
    }

    /// Why Desk Mode can't be used, or nil when it can. Permanent reasons come
    /// before passing ones, so the card never flickers between "needs a
    /// display" and "not available".
    public static func reason(for inputs: Inputs) -> DeskModeState.UnavailableReason? {
        if MacModel.blocksDeskMode(inputs.modelIdentifier) { return .unsupportedMac }
        // No clamshell key: a desktop or VM. A closed lid hides the panel from a
        // cold start's snapshot, so only an open lid without a panel rules the Mac out.
        if inputs.lid == .unknown || (!inputs.hasBuiltInPanel && inputs.lid == .open) { return .unsupportedMac }
        if !inputs.systemCallsPresent { return .unsupportedSystem }
        if inputs.lid == .closed { return .lidClosed }
        if inputs.usableExternalCount == 0 { return .needsDisplay }
        return nil
    }
}

extension DeskModeState {
    /// This state after availability changed. `.on` and `.switching` stay: the
    /// Desk Mode controller owns them. Anything else becomes `.off` or `.unavailable`.
    public func applying(availability reason: UnavailableReason?) -> DeskModeState {
        switch self {
        case .on, .switching: self
        case .off, .unavailable: reason.map(DeskModeState.unavailable) ?? .off
        }
    }
}

/// Holds the usable-external count steady while the screens sleep: asleep
/// displays can drop out of CoreGraphics' lists and IDs can be re-issued, which
/// would flash "Needs a display" at every display sleep.
public struct ScreenSleepLatch: Sendable, Equatable {
    public private(set) var screensAsleep = false
    private var lastAwakeCount: Int?

    public init() {}

    public mutating func screensDidSleep() {
        screensAsleep = true
    }

    public mutating func screensDidWake() {
        screensAsleep = false
    }

    /// The count to judge availability by: `live` while awake, the last awake
    /// count while asleep (or `live` if there is none yet).
    public mutating func count(for live: Int) -> Int {
        if screensAsleep { return lastAwakeCount ?? live }
        lastAwakeCount = live
        return live
    }
}
