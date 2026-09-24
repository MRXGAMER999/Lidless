import Foundation

/// Coalesces built-in brightness writes and recognises the echo of our own
/// writes in DisplayServices' change notifications, so the slider and macOS
/// never chase each other (phase4-research.md §2.3).
///
/// Times are seconds on one monotonic clock (`ProcessInfo.systemUptime`;
/// `ContinuousClock` needs macOS 13). The first write goes out at once; later
/// ones inside `minInterval` wait in `pending`, latest value wins, until
/// `nextFlush(now:)`.
public struct BrightnessWriteFilter: Sendable, Equatable {
    /// At most one write per this interval (≈ 30 Hz).
    public var minInterval: TimeInterval
    /// A read within this window after a write that matches it (± `tolerance`) is our echo.
    public var echoWindow: TimeInterval
    public var tolerance: Double

    public init(minInterval: TimeInterval = 1.0 / 30, echoWindow: TimeInterval = 1, tolerance: Double = 0.01) {
        self.minInterval = minInterval
        self.echoWindow = echoWindow
        self.tolerance = tolerance
    }

    /// The value waiting for the next write slot.
    public private(set) var pending: Double?

    private struct Write: Sendable, Equatable {
        var level: Double
        var at: TimeInterval
    }

    /// Writes still young enough to echo, oldest first. While dragging, the
    /// callback for one write can arrive after the next write went out, so
    /// every recent write counts, not only the last.
    private var recent: [Write] = []

    /// A timer can fire a hair before the slot by our clock; that must not
    /// strand the final value of a drag.
    private static let timerSlack: TimeInterval = 0.001

    /// Queues `level` (0...1). Returns the level to write now, or nil when the
    /// caller should flush later (`nextFlush(now:)`). A NaN level is dropped.
    public mutating func submit(_ level: Double, now: TimeInterval) -> Double? {
        guard !level.isNaN else { return nil }
        let level = min(max(level, 0), 1)
        guard slotIsOpen(now: now) else {
            pending = level
            return nil
        }
        pending = nil
        record(level, now: now)
        return level
    }

    /// When the pending value may be written, or nil if nothing is pending.
    /// Never earlier than `now`.
    public func nextFlush(now: TimeInterval) -> TimeInterval? {
        guard pending != nil else { return nil }
        guard let last = recent.last else { return now }
        return max(now, last.at + minInterval)
    }

    /// Takes the pending value if its slot has come.
    public mutating func flush(now: TimeInterval) -> Double? {
        guard let level = pending, slotIsOpen(now: now) else { return nil }
        pending = nil
        record(level, now: now)
        return level
    }

    /// True when a read is the echo of one of our recent writes.
    public func isEcho(_ level: Double, now: TimeInterval) -> Bool {
        recent.contains { write in
            let age = now - write.at
            return age >= 0 && age <= echoWindow && abs(write.level - level) <= tolerance
        }
    }

    private func slotIsOpen(now: TimeInterval) -> Bool {
        guard let last = recent.last else { return true }
        return now >= last.at + minInterval - Self.timerSlack
    }

    private mutating func record(_ level: Double, now: TimeInterval) {
        recent.removeAll { now - $0.at > echoWindow }
        recent.append(Write(level: level, at: now))
    }
}

/// "Keep pressing to boost": what a brightness key press does to the slider.
public enum BrightnessKeyPolicy {
    public enum Key: Sendable, Equatable { case up, down }

    /// Slider positions per key press in the Boost range (the 50-position Boost
    /// third in 8 presses, about macOS's 16 steps for the normal range).
    public static let boostStep = 50.0 / 8

    /// Native levels at or above this count as 100 %. The step below full is
    /// about 0.92 (the key ladder is 0.0825 wide), so this only rounds off float noise.
    static let fullLevel = 0.999

    /// The new slider position when a brightness key is pressed, or nil to let
    /// macOS handle it. The key tap only listens, so macOS always sees the key
    /// too: up at native 100 % (with `keysIntoBoost`) moves one `boostStep`
    /// further into Boost, capped at the scale's end; anything else is macOS's,
    /// and the slider follows the level it reads back (down leaves Boost,
    /// because the native level drops below 100 %).
    ///
    /// `nativeLevel` must be the level read *before* this key: the press that
    /// arrives at 100 % only reaches full brightness and doesn't boost yet.
    public static func position(after key: Key, current: Double, nativeLevel: Double, scale: BrightnessScale, keysIntoBoost: Bool) -> Double? {
        guard key == .up, keysIntoBoost, scale.canBoost, nativeLevel >= fullLevel else { return nil }
        let base = current.isNaN ? BrightnessScale.normalLimit : max(current, BrightnessScale.normalLimit)
        return min(base + boostStep, BrightnessScale.sliderMax)
    }
}
