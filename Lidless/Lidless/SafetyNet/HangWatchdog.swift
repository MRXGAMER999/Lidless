import Foundation
import os

/// L6, the in-process hang watchdog. While armed, a main-run-loop timer beats
/// every 0.5 s and a timer on a private queue checks the beat every second.
/// A main thread stuck for longer than `limit` logs a fault and aborts: the
/// process death makes WindowServer drop the app-only disable, the sidecar
/// restores whatever is left, and the next launch finds the crash marker.
///
/// Both clocks are uptime (`DispatchTime`), which stops while the Mac sleeps,
/// so a sleep never reads as a hang.
final class HangWatchdog: HangWatchdogControl {
    private let limit: TimeInterval
    private let onHang: @Sendable (TimeInterval) -> Void
    private let state = HangWatchdogState()
    private let queue = DispatchQueue(label: "io.github.mrxgamer999.Lidless.hang-watchdog", qos: .utility)
    // deinit reads these; they're otherwise touched on the main actor only.
    nonisolated(unsafe) private var beatTimer: Timer?
    nonisolated(unsafe) private var checkTimer: (any DispatchSourceTimer)?

    private(set) var isArmed = false

    /// - Parameters:
    ///   - limit: How long the main thread may go without a beat.
    ///   - onHang: Called on the watchdog queue with the stall length. Tests
    ///     pass their own; the default logs and aborts.
    init(limit: TimeInterval = 8, onHang: (@Sendable (TimeInterval) -> Void)? = nil) {
        self.limit = limit
        self.onHang = onHang ?? HangWatchdogState.abortProcess
    }

    deinit {
        beatTimer?.invalidate()
        checkTimer?.cancel()
    }

    func setArmed(_ armed: Bool) {
        // A fresh beat on every arm, so time spent before it never counts.
        state.arm(armed)
        guard armed != isArmed else { return }
        isArmed = armed
        if armed {
            startBeating()
            checkTimer = HangWatchdogState.makeCheckTimer(state: state, queue: queue, limit: limit, onHang: onHang)
        } else {
            beatTimer?.invalidate()
            beatTimer = nil
            checkTimer?.cancel()
            checkTimer = nil
        }
    }

    private func startBeating() {
        // The block is @Sendable and nonisolated; it only touches the lock-guarded state.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [state] _ in state.beat() }
        timer.tolerance = 0.1
        // Common modes keep it beating during menu tracking and modal panels,
        // which are not hangs.
        RunLoop.main.add(timer, forMode: .common)
        beatTimer = timer
    }

    #if DEBUG
    /// Blocks the main thread for 30 s, for the hands-on L6 test. Armed, the
    /// process should abort after about 8 s and the built-in should come back.
    func simulateHang() {
        HangWatchdogState.log.notice("Simulating a main-thread hang (armed: \(self.isArmed, privacy: .public))")
        Thread.sleep(forTimeInterval: 30)
    }
    #endif
}

/// The beat and the armed flag, shared by the main thread and the watchdog queue.
///
/// `Synchronization.Atomic` needs macOS 15 and `OSAllocatedUnfairLock` macOS 13,
/// so this guards plain fields with an `os_unfair_lock` on macOS 12. The lock
/// lives in its own heap allocation: an `os_unfair_lock` stored as a Swift
/// property may move, which the lock forbids.
///
/// `nonisolated`: its methods and the check timer's handler run on the watchdog
/// queue, where a main-actor-isolated closure would trap at run time.
nonisolated final class HangWatchdogState: @unchecked Sendable {
    static let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "HangWatchdog")

    /// A check that runs this late means the whole process was stopped
    /// (SIGSTOP, a debugger, a starved queue), not just the main thread. The
    /// main thread then gets a fresh window rather than an instant abort on
    /// resume; the sidecar covers stops that last.
    static let suspendedGap: UInt64 = 3_000_000_000

    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var armed = false
    private var lastBeat: UInt64 = 0
    private var lastCheck: UInt64 = 0

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    private func locked<T>(_ body: (UInt64) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        // Read inside the lock, so a beat never lands after `now`.
        return body(DispatchTime.now().uptimeNanoseconds)
    }

    func arm(_ on: Bool) {
        locked { now in
            armed = on
            lastBeat = now
            lastCheck = now
        }
    }

    func beat() {
        locked { now in lastBeat = now }
    }

    /// The stall in seconds when armed and the last beat is older than `limit`, else nil.
    func stall(limit: TimeInterval) -> TimeInterval? {
        locked { now in
            guard armed else { return nil }
            defer { lastCheck = now }
            if now - lastCheck > Self.suspendedGap {
                lastBeat = now
                return nil
            }
            let age = Double(now - lastBeat) / 1e9
            return age > limit ? age : nil
        }
    }

    static func makeCheckTimer(state: HangWatchdogState, queue: DispatchQueue, limit: TimeInterval, onHang: @escaping @Sendable (TimeInterval) -> Void) -> any DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { @Sendable in
            if let stall = state.stall(limit: limit) { onHang(stall) }
        }
        timer.resume()
        return timer
    }

    static let abortProcess: @Sendable (TimeInterval) -> Void = { stall in
        log.fault("Main thread stalled for \(stall, format: .fixed(precision: 1), privacy: .public) s with Desk Mode on; aborting so the built-in display comes back")
        abort()
    }
}
