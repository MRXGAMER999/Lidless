import CoreGraphics
import Foundation
import LidlessCore

/// Built-in brightness writes through `DisplayServicesSetBrightness`, the
/// absolute 0...1 slider. Only the normal part of the popover slider (and its
/// release) reaches here; Boost itself never writes native brightness.
///
/// Writes are coalesced to about 30 Hz, latest value wins, and the last value
/// is always written once its slot comes. Never call `setLevel` from a
/// DisplayServices change callback: a read never triggers a write, or macOS and
/// the slider would chase each other. Use `isEcho` there instead.
final class DisplayServicesBrightnessWriter: BuiltInBrightnessWriter {
    /// What touches the system, injectable for tests.
    struct Setter {
        /// Whether `display` can take a write right now.
        var canWrite: (CGDirectDisplayID) -> Bool
        /// Writes an absolute level 0...1. The return code proves nothing, so none.
        var write: (CGDirectDisplayID, Float) -> Void

        /// DisplayServices, or nil when the setter isn't exported.
        static var displayServices: Setter? {
            guard let set = DisplayServicesAPI.setBrightness else { return nil }
            return Setter(
                canWrite: { display in
                    // CoreGraphics' own state: the built-in is offline with the lid
                    // closed or Desk Mode on, and DisplayServices is untested there.
                    display != 0 && CGDisplayIsOnline(display) != 0
                        && DisplayServicesAPI.canChangeBrightness?(display) == true
                },
                write: { display, level in _ = set(display, level) }
            )
        }
    }

    private var filter: BrightnessWriteFilter
    private let setter: Setter?
    private let clock: () -> TimeInterval
    /// Where the pending value goes (the latest display asked for).
    private var target: CGDirectDisplayID = 0
    /// `cancelPending` ran after the last `setLevel`: the filter's pending
    /// value (which the filter can't drop) is never written.
    private var isPendingCancelled = false
    /// Read from `deinit`, like DeskModeController's timers.
    nonisolated(unsafe) private var flushTimer: Timer?

    init(
        setter: Setter? = .displayServices,
        filter: BrightnessWriteFilter = .init(),
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.setter = setter
        self.filter = filter
        self.clock = clock
    }

    deinit {
        flushTimer?.invalidate()
    }

    @discardableResult
    func setLevel(_ level: Double, of display: CGDirectDisplayID) -> Bool {
        guard !level.isNaN, let setter, setter.canWrite(display) else { return false }
        target = display
        isPendingCancelled = false
        if let value = filter.submit(min(max(level, 0), 1), now: clock()) {
            setter.write(display, Float(value))
        } else {
            scheduleFlush()
        }
        return true
    }

    func isEcho(_ level: Double) -> Bool {
        filter.isEcho(level, now: clock())
    }

    func cancelPending() {
        cancelFlush()
        isPendingCancelled = true
    }

    /// True while a coalesced value waits for its slot.
    var hasPendingWrite: Bool { filter.pending != nil && !isPendingCancelled }

    /// Writes the pending value if its slot has come, else waits again. The
    /// timer calls it; tests call it after moving their clock.
    func flushIfDue() {
        cancelFlush()
        guard let setter, !isPendingCancelled else { return }
        if let level = filter.flush(now: clock()) {
            // The display may have gone away since (lid closed, Desk Mode): drop it.
            if setter.canWrite(target) { setter.write(target, Float(level)) }
        } else if filter.pending != nil {
            scheduleFlush()  // The timer fired a hair early.
        }
    }

    private func scheduleFlush() {
        guard flushTimer == nil, let due = filter.nextFlush(now: clock()) else { return }
        let timer = Timer(timeInterval: max(0, due - clock()), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushIfDue() }
        }
        // Common modes: the slider tracks the mouse in event-tracking mode.
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    private func cancelFlush() {
        flushTimer?.invalidate()
        flushTimer = nil
    }
}
