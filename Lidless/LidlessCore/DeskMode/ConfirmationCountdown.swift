import Foundation

/// The keep-or-revert prompt's countdown, from its deadline. Pure so the HUD,
/// VoiceOver announcements and tests agree on every number.
public struct ConfirmationCountdown: Sendable, Equatable {
    public var deadline: TimeInterval
    public var total: TimeInterval

    public init(deadline: TimeInterval, total: TimeInterval = 15) {
        self.deadline = deadline
        self.total = total
    }

    /// Whole seconds left, rounded up ("12 seconds"), never negative.
    public func secondsLeft(now: TimeInterval) -> Int {
        max(0, Int((deadline - now).rounded(.up)))
    }

    /// Bar fill, 1 at the start down to 0 at the deadline, linear.
    public func fraction(now: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(max((deadline - now) / total, 0), 1)
    }

    public func isExpired(now: TimeInterval) -> Bool { now >= deadline }

    /// Whether VoiceOver should announce at this second: 15, 10, 5 and each of the last 3.
    public static func shouldAnnounce(secondsLeft: Int) -> Bool {
        announcedSeconds.contains(secondsLeft)
    }

    private static let announcedSeconds: Set<Int> = [15, 10, 5, 3, 2, 1]
}
