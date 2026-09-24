import Foundation

/// Trailing debounce with a ceiling: fire `quiet` seconds after the last event,
/// but never later than `maxWait` after the first event of a burst, so a steady
/// stream (an EDR ramp) can't starve the refresh. Times are monotonic seconds.
public struct RefreshSchedule: Sendable, Equatable {
    public var quiet: Double
    public var maxWait: Double
    private var burstStart: Double?

    public init(quiet: Double = 0.3, maxWait: Double = 1.0) {
        self.quiet = quiet
        self.maxWait = max(quiet, maxWait)
    }

    /// True between an event and the refresh it schedules.
    public var isPending: Bool { burstStart != nil }

    /// Records an event and returns when the refresh should run.
    public mutating func eventArrived(at now: Double) -> Double {
        let start = burstStart ?? now
        burstStart = start
        return min(now + quiet, start + maxWait)
    }

    /// Call when the refresh ran; the next event starts a new burst.
    public mutating func fired() {
        burstStart = nil
    }
}
