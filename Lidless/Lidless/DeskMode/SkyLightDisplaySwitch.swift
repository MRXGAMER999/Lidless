import CoreGraphics
import Foundation
import os

/// Desk Mode's disconnect method: SkyLight's enable bit, one transaction at a
/// time on a private serial queue.
///
/// Every CoreGraphics call gets 10 s. One that is still stuck by then (the
/// commit can hold for about 30 s) reports failure; the queue stays serial, so
/// a later request runs after it. Success is decided by list membership, never
/// by return codes.
///
/// A timeout only ever suppresses a completion. Enable work always runs, even
/// after its request timed out. A disable that timed out while queued never
/// starts; one whose call returns after its timeout is undone at once with a
/// session-scope enable, because the machine has already moved on.
final class SkyLightDisplaySwitch: BuiltInSwitch {
    private let queue = DispatchQueue(label: "io.github.mrxgamer999.Lidless.display", qos: .userInitiated)
    private var completions: [UInt64: @MainActor (Bool) -> Void] = [:]
    private var lastToken: UInt64 = 0
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "DeskMode")

    init() {}

    func disable(displayID: CGDirectDisplayID, uuid: String?, completion: @escaping @MainActor (Bool) -> Void) {
        log.notice("Disable requested for display \(displayID, privacy: .public)")
        submit("disable", completion) { @Sendable request in
            DisplayWork.disable(displayID, uuid: uuid, request)
        }
    }

    func enable(displayID: CGDirectDisplayID?, uuid: String?, completion: @escaping @MainActor (Bool) -> Void) {
        log.notice("Enable requested for display \(displayID.map { String($0) } ?? "unknown", privacy: .public)")
        submit("enable", completion) { @Sendable request in
            DisplayWork.enable(displayID, uuid: uuid, request)
        }
    }

    /// Stronger than the protocol asks: true only when the re-found built-in is
    /// in the online list before `timeout` runs out (already online counts, and
    /// then no transaction is sent). CoreGraphics' answer alone never counts.
    func enableNow(displayID: CGDirectDisplayID?, uuid: String?, timeout: TimeInterval) -> Bool {
        let wait = max(0, timeout)
        let deadline = ProcessInfo.processInfo.systemUptime + wait
        let result = LockedFlag()
        let done = DispatchSemaphore(value: 0)
        queue.async { @Sendable in
            result.set(DisplayWork.enableNow(displayID, uuid: uuid, until: deadline))
            done.signal()
        }
        // Called on the main thread while quitting: never wait past `timeout`.
        // Work still queued by then runs later anyway; the enable is still wanted.
        guard done.wait(timeout: .now() + wait) == .success else {
            log.error("Enable on quit was not verified within \(timeout, privacy: .public) s")
            return false
        }
        return result.value
    }

    /// Queues `work` and arms the first call's timeout now, so it also covers
    /// time spent waiting behind a stuck transaction.
    private func submit(_ label: String, _ completion: @escaping @MainActor (Bool) -> Void, work: @escaping @Sendable (DisplayRequest) -> Bool) {
        lastToken &+= 1
        let token = lastToken
        completions[token] = completion
        let request = DisplayRequest(label) { @Sendable [self] ok in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.complete(token, ok) }
            }
        }
        request.armTimeout()
        // Always runs: each kind of work decides what a timeout means for it.
        queue.async { @Sendable in
            request.finish(work(request))
        }
    }

    private func complete(_ token: UInt64, _ ok: Bool) {
        guard let completion = completions.removeValue(forKey: token) else { return }
        completion(ok)
    }
}

/// The work run on the display queue. Nonisolated: the app target defaults to
/// the main actor, and main-actor code run on this queue traps.
private nonisolated enum DisplayWork {
    static let verifyTimeout: TimeInterval = 4
    static let pollInterval: TimeInterval = 0.1
    static let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "DeskMode")

    /// App-only scope, then waits for the panel to leave the online list.
    static func disable(_ id: CGDirectDisplayID, uuid: String?, _ request: DisplayRequest) -> Bool {
        // Its failure is already reported: turning the panel off now would
        // surprise a machine that has moved on.
        guard !request.isFinished else {
            log.notice("Disable skipped: it timed out while queued")
            return false
        }
        let target = uuid == nil ? id : (DisplayConfigTransaction.findBuiltIn(uuid: uuid, fallbackID: id) ?? id)
        // Never turn off anything but an online built-in panel.
        guard DisplayConfigTransaction.isAvailable,
              DisplayConfigTransaction.isOnline(target),
              CGDisplayIsBuiltin(target) == 1 else {
            log.error("Disable refused: display \(target, privacy: .public) is not an online built-in panel, or SkyLight is missing")
            return false
        }
        let reported = DisplayConfigTransaction.setEnabled(target, false, scope: .appOnly)
        guard request.callReturned() else {
            // The controller was told it failed and is restoring: put the panel back now.
            log.error("Disable of display \(target, privacy: .public) returned after its timeout; enabling it again")
            let back = enableNow(target, uuid: uuid, until: ProcessInfo.processInfo.systemUptime + verifyTimeout)
            log.notice("Undo of the late disable: verified \(back, privacy: .public)")
            return false
        }
        let gone = waitUntil(ProcessInfo.processInfo.systemUptime + verifyTimeout) { !DisplayConfigTransaction.isOnline(target) }
        log.notice("Disable of display \(target, privacy: .public): reported \(reported, privacy: .public), verified \(gone, privacy: .public)")
        return gone
    }

    /// Session scope, retried once, with the permanent configuration as the
    /// last step. Never refused; a panel already online is a success without
    /// a transaction. Runs to the end even after its request timed out: only
    /// the completion is dropped then.
    static func enable(_ displayID: CGDirectDisplayID?, uuid: String?, _ request: DisplayRequest) -> Bool {
        if builtInIsOnline(displayID, uuid: uuid) {
            log.notice("Enable: the built-in panel is already online")
            return true
        }
        var sent = false
        for attempt in 1...2 {
            if attempt > 1 { request.armTimeout() }
            let reported = enableOnce(displayID, uuid: uuid)
            request.callReturned()
            sent = sent || reported != nil
            let back = waitUntil(ProcessInfo.processInfo.systemUptime + verifyTimeout) { builtInIsOnline(displayID, uuid: uuid) }
            log.notice("Enable attempt \(attempt, privacy: .public): reported \(reported.map { String($0) } ?? "nothing sent", privacy: .public), verified \(back, privacy: .public)")
            if back { return true }
        }
        // Escalate only after enables that reached a real panel and failed.
        guard sent else {
            log.error("Enable failed: no built-in panel to send it to; not restoring the permanent configuration")
            return false
        }
        guard PermanentRestoreThrottle.shared.claim() else {
            log.notice("Enable failed; the permanent configuration was restored less than \(PermanentRestoreThrottle.interval, privacy: .public) s ago")
            return false
        }
        request.armTimeout()
        DisplayConfigTransaction.restorePermanentConfiguration()
        request.callReturned()
        let back = waitUntil(ProcessInfo.processInfo.systemUptime + verifyTimeout) { builtInIsOnline(displayID, uuid: uuid) }
        log.notice("Enable after restoring the permanent configuration: verified \(back, privacy: .public)")
        return back
    }

    /// One session-scope enable (skipped when the panel is already online),
    /// then polls the online list until `deadline`.
    static func enableNow(_ displayID: CGDirectDisplayID?, uuid: String?, until deadline: TimeInterval) -> Bool {
        if builtInIsOnline(displayID, uuid: uuid) {
            log.notice("Enable now: the built-in panel is already online")
            return true
        }
        let reported = enableOnce(displayID, uuid: uuid)
        let back = waitUntil(deadline) { builtInIsOnline(displayID, uuid: uuid) }
        log.notice("Enable now: reported \(reported.map { String($0) } ?? "nothing sent", privacy: .public), verified \(back, privacy: .public)")
        return back
    }

    /// One session-scope enable of the re-found panel: CoreGraphics' answer,
    /// or nil when no built-in panel was found and nothing was sent.
    private static func enableOnce(_ displayID: CGDirectDisplayID?, uuid: String?) -> Bool? {
        guard let id = DisplayConfigTransaction.findBuiltIn(uuid: uuid, fallbackID: displayID) else {
            log.error("Enable skipped: no built-in panel in the display lists")
            return nil
        }
        return DisplayConfigTransaction.setEnabled(id, true, scope: .session)
    }

    private static func builtInIsOnline(_ displayID: CGDirectDisplayID?, uuid: String?) -> Bool {
        DisplayConfigTransaction.findBuiltIn(uuid: uuid, fallbackID: displayID).map(DisplayConfigTransaction.isOnline) ?? false
    }

    /// Polls every 100 ms until `deadline` (system uptime), checking at least
    /// once: link training can take seconds after CoreGraphics returns, and its
    /// return code can be wrong either way.
    private static func waitUntil(_ deadline: TimeInterval, _ condition: () -> Bool) -> Bool {
        while !condition() {
            let left = deadline - ProcessInfo.processInfo.systemUptime
            guard left > 0 else { return false }
            Thread.sleep(forTimeInterval: min(pollInterval, left))
        }
        return true
    }
}

/// `CGRestorePermanentDisplayConfiguration` resets every display, so the
/// enable ladder uses it at most once a minute however often restores fail.
private nonisolated final class PermanentRestoreThrottle: @unchecked Sendable {
    static let shared = PermanentRestoreThrottle()
    static let interval: TimeInterval = 60

    private let lock = NSLock()
    private var last: TimeInterval?

    /// True, and starts a new interval, when the last restore is at least `interval` old.
    func claim() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        defer { lock.unlock() }
        if let last, now - last < Self.interval { return false }
        last = now
        return true
    }
}

/// One disable or enable: its result is delivered exactly once, either by the
/// work or by a timeout that fires while a CoreGraphics call is still stuck.
private nonisolated final class DisplayRequest: @unchecked Sendable {
    static let callTimeout: TimeInterval = 10

    private let lock = NSLock()
    private let label: String
    private let deliver: @Sendable (Bool) -> Void
    private var finished = false
    /// CoreGraphics calls that have returned; a timeout only fires if none has since it was armed.
    private var returnedCalls = 0

    init(_ label: String, deliver: @escaping @Sendable (Bool) -> Void) {
        self.label = label
        self.deliver = deliver
    }

    var isFinished: Bool { locked { finished } }

    /// Gives the next CoreGraphics call `callTimeout` seconds to return.
    func armTimeout() {
        let armedAt = locked { returnedCalls }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.callTimeout) { @Sendable [self] in
            let expired = locked { () -> Bool in
                guard !finished, returnedCalls == armedAt else { return false }
                finished = true
                return true
            }
            guard expired else { return }
            DisplayWork.log.error("\(self.label, privacy: .public) timed out after \(Self.callTimeout, privacy: .public) s; reported as failed")
            deliver(false)
        }
    }

    /// Call after each CoreGraphics call. False when the request already timed
    /// out, so its completion has been delivered as a failure.
    @discardableResult
    func callReturned() -> Bool {
        let live = locked { () -> Bool in
            returnedCalls += 1
            return !finished
        }
        if !live {
            DisplayWork.log.notice("\(self.label, privacy: .public) returned after its timeout; its completion was already delivered")
        }
        return live
    }

    func finish(_ ok: Bool) {
        let first = locked { () -> Bool in
            guard !finished else { return false }
            finished = true
            return true
        }
        if first { deliver(ok) }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// `enableNow`'s result, handed from the display queue to the waiting thread.
private nonisolated final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Bool) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}
