import CoreFoundation
import CoreGraphics
import Darwin
import Foundation
import LidlessCore
import os

/// The sidecar side of layer 7: `Lidless --watchdog <pid>`, spawned by
/// `SidecarWatchdog` in its own session. No AppKit.
///
/// It reads `WatchdogMessage` lines from stdin, watches the parent through
/// pipe EOF and a process-exit source, and every 0.25 s asks `WatchdogPolicy`
/// what to do: SIGKILL a hung or stopped parent (WindowServer then drops its
/// app-only configuration), enable the panel if it still isn't back, or exit.
///
/// The work runs on one serial queue, and display enables on a second one so a
/// wedged CoreGraphics call can't hold up a kill. The types are `nonisolated`
/// because the app target defaults to the main actor, and a main-actor handler
/// on these queues would trap at run time.
nonisolated enum WatchdogProcess {
    static func run(parentPID: pid_t) -> Never {
        // CoreGraphics caches the display list per process and refreshes it from
        // WindowServer notifications that arrive on the main run loop; under
        // `dispatchMain()` nothing runs it, and a stale cache could call the panel
        // back when it isn't. Registering a callback subscribes this process to
        // them; the timer only keeps `CFRunLoopRun` from returning for want of a
        // source.
        _ = CGDisplayRegisterReconfigurationCallback({ _, _, _ in }, nil)
        let keepAlive = CFRunLoopTimerCreateWithHandler(nil, Date.distantFuture.timeIntervalSinceReferenceDate, 0, 0, 0) { _ in }
        CFRunLoopAddTimer(CFRunLoopGetMain(), keepAlive, .commonModes)

        let sidecar = Sidecar(parentPID: parentPID)
        sidecar.queue.async { @Sendable in sidecar.start() }
        while true { CFRunLoopRun() }
    }
}

/// State is touched only on `queue`, hence the unchecked conformance.
private nonisolated final class Sidecar: @unchecked Sendable {
    let queue = DispatchQueue(label: "io.github.mrxgamer999.Lidless.watchdog", qos: .userInteractive)
    /// Display calls only, one at a time: a call that never returns blocks
    /// later enables, never the tick.
    private let enableQueue = DispatchQueue(label: "io.github.mrxgamer999.Lidless.watchdog.enable", qos: .userInteractive)
    private let parentPID: pid_t
    private let policy = WatchdogPolicy()
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Watchdog")

    private var sources: [any DispatchSourceProtocol] = []
    private var reader: (any DispatchSourceRead)?
    private var input = WatchdogLineBuffer()
    private var armed: (displayID: CGDirectDisplayID, method: DeskModeMethod, uuid: String?)?
    private var saidBye = false
    private var lastHeartbeat: TimeInterval?
    private var deadline: TimeInterval?
    private var parentDiedAt: TimeInterval?
    private var killedParent = false
    private var startedAt: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    /// Keeps App Nap and timer coalescing off the 0.25 s tick.
    private var activity: (any NSObjectProtocol)?

    // Restore state.
    private var restoreStartedAt: TimeInterval?
    private var lastRestoreAttempt: TimeInterval?
    private var restoreAttempts = 0
    /// Enables of a found panel that left it offline, since the last
    /// permanent-configuration restore.
    private var failedEnables = 0
    private var lastPermanentRestore: TimeInterval?
    /// When the call on `enableQueue` started; nil when none runs.
    private var callStartedAt: TimeInterval?
    /// The running call is an enable (not the permanent-configuration restore).
    private var callIsEnable = false
    /// The running call was already written off as failed by the timeout.
    private var callTimedOut = false
    /// A session enable finished (or timed out) after the parent died. Until
    /// then the online list alone never ends the watch.
    private var enabledSinceDeath = false

    private let tickInterval = 0.25
    private let armTimeout: TimeInterval = 30
    /// A tick this late means this process was stopped or starved, not the app.
    private let suspendedGap: TimeInterval = 3
    /// Above the ~30 s CoreGraphics can take to complete a transaction.
    private let callTimeout: TimeInterval = 35
    private let fastRetryInterval: TimeInterval = 1
    private let fastRetryPeriod: TimeInterval = 60
    private let slowRetryInterval: TimeInterval = 5
    private let restoreGiveUp: TimeInterval = 30 * 60
    private let permanentAfterFailures = 5
    private let permanentInterval: TimeInterval = 60

    init(parentPID: pid_t) {
        self.parentPID = parentPID
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        startedAt = now
        lastTick = startedAt
        log.info("Watchdog \(getpid()) guarding \(self.parentPID)")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Lidless watchdog"
        )

        _ = fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK)
        let reader = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: queue)
        reader.setEventHandler { @Sendable [self] in readInput() }
        reader.resume()
        self.reader = reader

        let parentExit = DispatchSource.makeProcessSource(identifier: parentPID, eventMask: .exit, queue: queue)
        parentExit.setEventHandler { @Sendable [self] in parentDied("exit event") }
        parentExit.resume()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + tickInterval, repeating: tickInterval, leeway: .milliseconds(25))
        timer.setEventHandler { @Sendable [self] in tick() }
        timer.resume()
        sources = [reader, parentExit, timer]

        // The parent may be gone already, before the exit source was attached.
        if !parentAlive { parentDied("gone at start") }
    }

    /// Still our parent (so the PID wasn't reused by someone else) and alive.
    private var parentAlive: Bool {
        getppid() == parentPID && (kill(parentPID, 0) == 0 || errno == EPERM)
    }

    private func parentDied(_ why: String) {
        guard parentDiedAt == nil else { return }
        parentDiedAt = now
        log.info("Parent \(self.parentPID) gone (\(why, privacy: .public))")
    }

    // MARK: - Input

    private func readInput() {
        guard reader != nil else { return }
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = bytes.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
            if n > 0 {
                input.append(Array(bytes[..<n])).forEach(handle)
                continue
            }
            if n < 0, errno == EINTR { continue }
            if n < 0, errno == EAGAIN { return }
            // EOF (or a broken pipe): the write end closes only when the app
            // disarmed after "bye" or died.
            reader?.cancel()
            reader = nil
            parentDied("pipe closed")
            return
        }
    }

    private func handle(_ message: WatchdogMessage) {
        switch message {
        case let .arm(displayID, method, uuid):
            armed = (displayID, method, uuid)
            // Counts as a heartbeat: the policy gives no hang verdict without
            // one, so a hang before the first "hb" would go unnoticed.
            lastHeartbeat = now
            log.info("Armed: display \(displayID), \(method.rawValue, privacy: .public)")
        case .heartbeat:
            lastHeartbeat = now
        case let .deadline(deadline):
            // nil ("deadline none") drops the deadline kill: the app sends it
            // once the prompt is kept and on every restore.
            self.deadline = deadline
        case .bye:
            saidBye = true
            log.info("Bye")
            exit(0)
        }
    }

    // MARK: - Policy

    private func tick() {
        // Lines already in the pipe count before any verdict: a heartbeat
        // queued behind a busy tick is not a hang.
        readInput()
        let t = now
        defer { lastTick = t }
        if t - lastTick > tickInterval + suspendedGap, lastHeartbeat != nil {
            // This process was stopped or starved, so the heartbeat's age says
            // nothing about the app. Give it a fresh window.
            log.notice("Tick \(t - self.lastTick, format: .fixed(precision: 1), privacy: .public) s apart; restarting the hang window")
            lastHeartbeat = t
        }
        checkCall(at: t)
        guard let armed else {
            // Nothing to guard: a parent that never armed or already left.
            if parentDiedAt != nil || t - startedAt > armTimeout {
                log.info("Exiting unarmed")
                exit(0)
            }
            return
        }

        // Hang first, without touching CoreGraphics: a slow display read must
        // never hold up the kill. "Back" disables the policy's deadline kill and
        // restore-after-kill, so the only verdict left here is a hang.
        if parentDiedAt == nil {
            if policy.action(for: observation(at: t, builtInBack: true)) == .killParent {
                killParent()
                return
            }
            let pastDeadline = deadline.map { t >= $0 + policy.deadlineGrace } ?? false
            guard pastDeadline || killedParent else { return }
        }

        var action = policy.action(for: observation(at: t, builtInBack: builtInBack(armed)))
        if action == .exit, parentDiedAt != nil, armed.method == .disconnect, !enabledSinceDeath {
            // The list may still show the panel from before the parent died.
            // One session enable is harmless if it is on and makes sure it stays.
            action = .restore
        }
        switch action {
        case .none:
            break
        case .killParent:
            killParent()
        case .restore:
            restore(armed, at: t)
        case .exit:
            log.info("Built-in screen is back; exiting")
            exit(0)
        }
    }

    private func observation(at t: TimeInterval, builtInBack: Bool) -> WatchdogPolicy.Observation {
        WatchdogPolicy.Observation(
            now: t,
            armed: !saidBye,
            saidBye: saidBye,
            lastHeartbeat: lastHeartbeat,
            deadline: deadline,
            parentDiedAt: parentDiedAt,
            killedParent: killedParent,
            builtInBack: builtInBack
        )
    }

    /// Black out's cover window dies with the app, so there the parent's death
    /// is the panel's return. Disconnect: the panel is in the online list.
    private func builtInBack(_ armed: (displayID: CGDirectDisplayID, method: DeskModeMethod, uuid: String?)) -> Bool {
        if armed.method == .blackout { return parentDiedAt != nil }
        guard let id = DisplayConfigTransaction.findBuiltIn(uuid: armed.uuid, fallbackID: armed.displayID) else { return false }
        return DisplayConfigTransaction.isOnline(id)
    }

    private func killParent() {
        killedParent = true
        // After the parent dies we are reparented to launchd, so a reused PID
        // can never be ours to kill.
        guard parentAlive else {
            parentDied("gone before SIGKILL")
            return
        }
        log.error("Parent \(self.parentPID) is hung or stopped; sending SIGKILL")
        if kill(parentPID, SIGKILL) != 0 {
            log.error("SIGKILL failed: \(errno)")
        }
    }

    // MARK: - Restore

    private func restore(_ armed: (displayID: CGDirectDisplayID, method: DeskModeMethod, uuid: String?), at t: TimeInterval) {
        let started = restoreStartedAt ?? t
        restoreStartedAt = started
        guard t - started < restoreGiveUp else {
            log.fault("The built-in screen did not come back after \(Int(self.restoreGiveUp / 60)) min; giving up")
            exit(1)
        }
        let interval = t - started < fastRetryPeriod ? fastRetryInterval : slowRetryInterval
        if let last = lastRestoreAttempt, t - last < interval { return }

        guard armed.method == .disconnect else {
            lastRestoreAttempt = t
            // A black out cover can only go with the app that owns it.
            if parentAlive { kill(parentPID, SIGKILL) }
            return
        }
        // Never two display calls at once; the next tick retries.
        guard callStartedAt == nil else { return }
        lastRestoreAttempt = t
        restoreAttempts += 1
        guard let id = DisplayConfigTransaction.findBuiltIn(uuid: armed.uuid, fallbackID: armed.displayID) else {
            // Never enable a guessed ID: it may be one of SkyLight's phantoms.
            log.error("Attempt \(self.restoreAttempts): the built-in screen isn't in any display list")
            return
        }
        if failedEnables >= permanentAfterFailures,
           lastPermanentRestore.map({ t - $0 >= permanentInterval }) ?? true {
            lastPermanentRestore = t
            failedEnables = 0
            call("Restoring the permanent configuration", enable: false, at: t) {
                DisplayConfigTransaction.restorePermanentConfiguration()
                return true
            }
            return
        }
        let attempt = restoreAttempts
        call("Enabling display \(id) (attempt \(attempt))", enable: true, at: t) {
            DisplayConfigTransaction.setEnabled(id, true, scope: .session)
        }
    }

    /// Runs one display call on `enableQueue` and reports back on `queue`.
    private func call(_ what: String, enable: Bool, at t: TimeInterval, _ body: @escaping @Sendable () -> Bool) {
        callStartedAt = t
        callIsEnable = enable
        callTimedOut = false
        log.error("\(what, privacy: .public)")
        enableQueue.async { @Sendable [self] in
            let ok = body()
            queue.async { @Sendable [self] in
                log.notice("\(what, privacy: .public): \(ok ? "accepted" : "failed", privacy: .public)")
                if !callTimedOut { finishCall() }
                callStartedAt = nil
            }
        }
    }

    /// A call past `callTimeout` counts as done (and failed) for the retry
    /// ladder, but the next one still waits for it to return.
    private func checkCall(at t: TimeInterval) {
        guard let started = callStartedAt, !callTimedOut, t - started >= callTimeout else { return }
        callTimedOut = true
        log.fault("A display call has been running for \(Int(t - started)) s")
        finishCall()
    }

    /// Whether an enable worked is read from the online list on the next tick;
    /// if another restore follows, the panel is still off and this one failed.
    private func finishCall() {
        guard callIsEnable else { return }
        failedEnables += 1
        if let died = parentDiedAt, let started = callStartedAt, started >= died {
            enabledSinceDeath = true
        }
    }
}
