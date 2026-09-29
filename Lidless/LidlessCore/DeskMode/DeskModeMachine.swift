import Foundation

/// Something that happened, fed to `DeskModeMachine.handle(_:now:)`.
public enum DeskModeEvent: Sendable, Equatable {
    /// The popover switch, the Desk Mode shortcut, an App Intent or the plug-in rule.
    case turnOn(trigger: DeskModeState.Trigger)
    /// The popover switch, the shortcut or an App Intent turned Desk Mode off.
    case turnOff
    /// The panic key or its menu equivalent. Always sends an enable at once, whatever
    /// the phase (only an asleep Mac holds it back). While Desk Mode is on or switching,
    /// it restores like any other reason, without a notification: the user is looking.
    /// From `.idle` it is one enable to the best-known panel and nothing else: the machine
    /// stays idle, with no retries and no notification.
    case panic
    /// Launch recovery or a restore at log out failed to bring the panel back: keep
    /// trying from here. From `.idle` it starts a `.recovery` restore for this panel
    /// (guarded by the watchdog and the crash marker, retried like any restore); an
    /// existing restore carries on, and learns the panel if it had lost track of it.
    case resumeRestore(displayID: UInt32, uuid: String?, method: DeskModeMethod)
    /// Whether Desk Mode can be offered at all (model, macOS, lid, externals), from
    /// `DeskModeAvailability`. nil means available.
    case availability(DeskModeState.UnavailableReason?)
    /// A fresh reading after any display or system change.
    case snapshot(DeskModeSnapshot)
    /// The controller finished a `.disable` command and checked the display list.
    /// `succeeded` is true only when the list shows the panel gone (disconnect)
    /// or the cover window is up (black out).
    case disableFinished(succeeded: Bool)
    /// The controller finished an `.enable` command and checked the display list.
    case enableFinished(succeeded: Bool)
    /// "Keep Off" in the keep-or-revert prompt.
    case keep
    /// "Turn Back On" in the prompt, or Escape.
    case revert
    /// About once a second while the phase is not `.idle`, and once right after
    /// any command the controller could not finish.
    case tick
    /// `NSWorkspace.willSleepNotification`. The machine sends no display command until `didWake`.
    case willSleep
    /// `NSWorkspace.didWakeNotification`.
    case didWake
    /// Quit, SIGTERM/SIGINT/SIGHUP, log out or power off.
    case willTerminate
}

/// Why the built-in screen came back. Drives the notification and the log.
public enum DeskModeRestoreReason: Sendable, Equatable {
    /// The user switched Desk Mode off.
    case user
    /// The panic key. Never notified: the user pressed it and sees the result.
    case panic
    /// The last external display disconnected; its name, when known.
    case externalLost(displayName: String?)
    /// Nobody answered the keep-or-revert prompt in time.
    case confirmationTimedOut
    /// "Turn Back On" in the prompt.
    case declined
    /// The system went to sleep while the prompt was up, or woke without "Keep Desk Mode after wake".
    case sleep
    /// Fast user switching or a lock of the console session.
    case sessionChanged
    /// The disable failed or could not be verified.
    case engageFailed
    /// Debug builds end Desk Mode after `Configuration.maxDuration`.
    case timeLimit
    /// The app is quitting.
    case terminating
    /// Carrying on after launch recovery or a restore at log out failed
    /// (`DeskModeEvent.resumeRestore`). Never notified.
    case recovery
}

/// Why a `turnOn` was refused. The machine stays `.idle`.
public enum DeskModeRefusal: Sendable, Equatable {
    case unavailable(DeskModeState.UnavailableReason)
    /// Lid closed, no usable external, built-in offline or mirrored, session
    /// inactive or asleep: something the snapshot says right now.
    case notReady
    /// Two failed engages in a row: Desk Mode rests for `Configuration.failureLatch`.
    case latched(until: TimeInterval)
    /// Already switching.
    case busy
}

/// Something the controller must do, in order. The machine never touches the system.
public enum DeskModeCommand: Sendable, Equatable {
    /// Start the sidecar watchdog (if not running) and hand it what to restore.
    case armWatchdog(displayID: UInt32, uuid: String?, method: DeskModeMethod)
    /// Tell the watchdog the prompt's deadline (monotonic seconds), or nil when kept.
    case watchdogDeadline(TimeInterval?)
    /// Say "bye" to the watchdog so it exits without restoring.
    case disarmWatchdog
    /// Write the crash marker before a disable (`engaging`) and once confirmed (`active`).
    case writeMarker(CrashMarker.Stage)
    case clearMarker
    /// Hold (true) or end (false) the App Nap activity.
    case holdActivity(Bool)
    /// Turn the built-in off. Answer with `.disableFinished`.
    case disable(displayID: UInt32, uuid: String?, method: DeskModeMethod)
    /// Turn the built-in on. Answer with `.enableFinished`. Safe to send at any
    /// time, also when the panel is already on.
    case enable(displayID: UInt32?, uuid: String?, method: DeskModeMethod)
    /// Show the keep-or-revert prompt on this external (UUID; nil = main display).
    case showConfirmation(deadline: TimeInterval, onDisplayUUID: String?)
    case hideConfirmation
    /// Post a notification (informational only).
    case notifyRestored(DeskModeRestoreReason)
    /// A `turnOn` was refused.
    case refused(DeskModeRefusal)
}

/// Desk Mode's safety state machine. Pure and deterministic: the controller
/// feeds it events with a monotonic `now` and runs the commands it returns.
///
/// The asymmetry is deliberate: enabling is never refused and is retried until
/// the display list shows the panel; disabling must pass every guard.
public struct DeskModeMachine: Sendable, Equatable {
    public struct Configuration: Sendable, Equatable {
        public var method: DeskModeMethod
        /// Settings › "Ask before keeping it off". Automatic engages always ask.
        public var askBeforeKeeping: Bool
        /// Length of the keep-or-revert prompt.
        public var confirmationSeconds: TimeInterval
        /// Re-apply Desk Mode after wake instead of leaving the panel on.
        public var keepAfterWake: Bool
        /// Debug builds: end Desk Mode after this long. nil in release.
        public var maxDuration: TimeInterval?
        /// A disable that hasn't finished after this long counts as failed.
        public var engageTimeout: TimeInterval
        /// After a disable, display churn from our own transaction is ignored for this long.
        public var settleTime: TimeInterval
        /// An empty list of present externals must hold this long, confirmed by a later
        /// reading or tick, before it counts as the external lost. One reading taken
        /// mid-reconfiguration can miss a display that is still there.
        public var lossConfirmTime: TimeInterval
        /// After the screens wake (display sleep or system sleep), an external
        /// missing from the list gets this long to come back before it counts as
        /// lost. A monitor leaving standby can take a few seconds to resync its
        /// signal and reappear (HDMI drops out of the list while it does); a real
        /// unplug found at wake still restores, this much later.
        public var screenWakeGrace: TimeInterval
        /// After wake, wait this long for a stable reading before deciding.
        public var wakeSettleTime: TimeInterval
        /// Retry a failed enable this often, forever (while the lid is open and the panel is known).
        public var restoreRetryInterval: TimeInterval
        /// Rest after two failed engages within `failureWindow`.
        public var failureLatch: TimeInterval
        public var failureWindow: TimeInterval

        public init(
            method: DeskModeMethod = .disconnect,
            askBeforeKeeping: Bool = true,
            confirmationSeconds: TimeInterval = 15,
            keepAfterWake: Bool = false,
            maxDuration: TimeInterval? = nil,
            engageTimeout: TimeInterval = 12,
            settleTime: TimeInterval = 2,
            lossConfirmTime: TimeInterval = 1,
            screenWakeGrace: TimeInterval = 6,
            wakeSettleTime: TimeInterval = 2,
            restoreRetryInterval: TimeInterval = 1,
            failureLatch: TimeInterval = 300,
            failureWindow: TimeInterval = 60
        ) {
            self.method = method
            self.askBeforeKeeping = askBeforeKeeping
            self.confirmationSeconds = confirmationSeconds
            self.keepAfterWake = keepAfterWake
            self.maxDuration = maxDuration
            self.engageTimeout = engageTimeout
            self.settleTime = settleTime
            self.lossConfirmTime = lossConfirmTime
            self.screenWakeGrace = screenWakeGrace
            self.wakeSettleTime = wakeSettleTime
            self.restoreRetryInterval = restoreRetryInterval
            self.failureLatch = failureLatch
            self.failureWindow = failureWindow
        }
    }

    public enum Phase: Sendable, Equatable {
        case idle
        /// A disable is in flight.
        case engaging(trigger: DeskModeState.Trigger, method: DeskModeMethod, startedAt: TimeInterval)
        /// The panel is off and the prompt is counting down.
        case confirming(trigger: DeskModeState.Trigger, method: DeskModeMethod, since: Date, deadline: TimeInterval)
        /// The panel is off and kept off.
        case active(trigger: DeskModeState.Trigger, method: DeskModeMethod, since: Date, engagedAt: TimeInterval)
        /// An enable is in flight or waiting to be retried.
        case restoring(reason: DeskModeRestoreReason, method: DeskModeMethod, lastAttempt: TimeInterval)
    }


    public var configuration: Configuration
    public private(set) var phase: Phase
    public private(set) var snapshot: DeskModeSnapshot
    public private(set) var availability: DeskModeState.UnavailableReason?

    // Bookkeeping the phase doesn't carry. Plain values, so the machine stays Equatable.

    /// Where the enable stands while `.restoring`.
    private enum EnableAttempt: Sendable, Equatable {
        /// Not sent yet: the sleep gate is closed, the lid is closed or no panel is known.
        /// Sent once that clears, not retried meanwhile.
        case pending
        case inFlight
        /// Failed; sent again `restoreRetryInterval` after `lastAttempt`.
        case failed
    }

    /// The panel `turnOn` switched off (or `resumeRestore` named). A restore targets
    /// it even if a later snapshot lost track of it.
    private var targetDisplayID: UInt32?
    private var targetUUID: String?
    /// When the disable was verified. The settle window and `maxDuration` count from here.
    private var disabledAt: TimeInterval?
    /// A disable was sent and hasn't answered, so the panel may still go dark.
    /// Blocks a new engage and the snapshot shortcut out of `.restoring`.
    private var disableInFlight = false
    private var enableAttempt = EnableAttempt.inFlight
    /// Between `willSleep` and `didWake`: no display command at all.
    private var sleeping = false
    /// After `didWake`, automatic decisions and restores wait until this uptime.
    private var wakeSettleUntil: TimeInterval?
    /// A prompt (or an engage that would lead to one) was pending at sleep: restore `.sleep` after wake.
    private var restoreAfterWake = false
    /// Desk Mode was active at sleep: after wake, check the built-in and `keepAfterWake`.
    private var checkAfterWake = false
    /// The last failed engage, for the latch. Cleared by a successful one.
    private var lastFailureAt: TimeInterval?
    private var latchedUntil: TimeInterval?
    /// The last external seen present, named in `.externalLost`.
    private var lastExternalName: String?
    /// The first trusted reading with no present external, while confirming or active.
    /// The loss counts once it holds for `lossConfirmTime`.
    private var lossSince: TimeInterval?
    /// When the screens last woke (the first awake reading after an asleep one,
    /// or `didWake`). Loss waits `screenWakeGrace` from here.
    private var screensWokeAt: TimeInterval?

    public init(configuration: Configuration = .init(), snapshot: DeskModeSnapshot = .init(), availability: DeskModeState.UnavailableReason? = nil) {
        self.configuration = configuration
        self.snapshot = snapshot
        self.availability = availability
        phase = .idle
    }

    /// What the popover shows: `.on` while confirming or active, `.switching`
    /// while a command is in flight, otherwise `.off` or `.unavailable`.
    public var state: DeskModeState {
        switch phase {
        case .idle: availability.map(DeskModeState.unavailable) ?? .off
        case .engaging: .switching(toOn: true)
        case .confirming(let trigger, _, let since, _), .active(let trigger, _, let since, _): .on(since: since, trigger: trigger)
        case .restoring: .switching(toOn: false)
        }
    }

    /// True when the machine wants `.tick` about once a second.
    public var needsTicks: Bool { phase != .idle }

    /// Feeds one event. `now` is monotonic seconds (system uptime); `date` is
    /// wall-clock time, used only for the `since` shown to the user.
    public mutating func handle(_ event: DeskModeEvent, now: TimeInterval, date: Date = Date()) -> [DeskModeCommand] {
        var commands: [DeskModeCommand]
        switch event {
        case .turnOn(let trigger): commands = turnOn(trigger, now: now)
        case .turnOff: commands = turnOff(now: now)
        case .panic: commands = panic(now: now)
        case let .resumeRestore(displayID, uuid, method):
            commands = resumeRestore(displayID: displayID, uuid: uuid, method: method, now: now)
        case .availability(let reason):
            availability = reason
            commands = []
        case .snapshot(let snapshot): commands = receive(snapshot, now: now)
        case .disableFinished(let succeeded): commands = disableFinished(succeeded, now: now, date: date)
        case .enableFinished(let succeeded): commands = enableFinished(succeeded, now: now)
        case .keep: commands = keep(now: now)
        case .revert:
            guard case .confirming = phase else { commands = []; break }
            commands = restore(.declined, now: now)
        case .tick: commands = []
        case .willSleep: return willSleep()
        case .didWake: commands = didWake(now: now)
        case .willTerminate: return willTerminate()
        }
        return commands + reconcile(now: now)
    }

    // MARK: - Events

    private mutating func turnOn(_ trigger: DeskModeState.Trigger, now: TimeInterval) -> [DeskModeCommand] {
        guard phase == .idle, !disableInFlight else { return [.refused(.busy)] }
        if let availability { return [.refused(.unavailable(availability))] }
        if let until = latchedUntil, now < until { return [.refused(.latched(until: until))] }
        guard isReadyToEngage(now: now), let displayID = snapshot.builtInDisplayID else { return [.refused(.notReady)] }
        let method = configuration.method
        let uuid = snapshot.builtInUUID
        targetDisplayID = displayID
        targetUUID = uuid
        lastExternalName = snapshot.usableExternals.first?.name
        disableInFlight = true
        phase = .engaging(trigger: trigger, method: method, startedAt: now)
        return [
            .holdActivity(true),
            .armWatchdog(displayID: displayID, uuid: uuid, method: method),
            .writeMarker(.engaging),
            .disable(displayID: displayID, uuid: uuid, method: method),
        ]
    }

    private func isReadyToEngage(now: TimeInterval) -> Bool {
        snapshot.lid == .open && snapshot.builtInOnline && !snapshot.builtInMirrored
            && !snapshot.usableExternals.isEmpty && snapshot.sessionActive
            && !snapshot.systemSleeping && !isGated(now: now)
    }

    private mutating func turnOff(now: TimeInterval) -> [DeskModeCommand] {
        switch phase {
        case .idle: return []
        // Already on its way back; a failed enable is retried right away.
        case .restoring: return enableAttempt == .failed ? sendEnable(now: now) : []
        case .engaging, .confirming, .active: return restore(.user, now: now)
        }
    }

    private mutating func receive(_ snapshot: DeskModeSnapshot, now: TimeInterval) -> [DeskModeCommand] {
        if self.snapshot.screensAsleep && !snapshot.screensAsleep { screensWokeAt = now }
        self.snapshot = snapshot
        if let name = snapshot.presentExternals.first?.name { lastExternalName = name }
        // Black out never takes the panel out of the list, so only the enable's answer counts there.
        guard case .restoring(let reason, .disconnect, _) = phase, snapshot.builtInOnline,
              !disableInFlight, !isGated(now: now) else { return [] }
        return finish(reason)
    }

    private mutating func disableFinished(_ succeeded: Bool, now: TimeInterval, date: Date) -> [DeskModeCommand] {
        disableInFlight = false
        switch phase {
        case .engaging(let trigger, let method, _):
            guard succeeded else {
                recordFailure(at: now)
                return restore(.engageFailed, now: now)
            }
            lastFailureAt = nil
            disabledAt = now
            if restoreAfterWake {
                restoreAfterWake = false
                return restore(.sleep, now: now)
            }
            // Unplugged while the disable ran: no prompt on a display that's gone, and no
            // settle window to wait out. Asleep readings can drop displays, so those wait.
            if snapshot.presentExternals.isEmpty && !snapshot.screensAsleep && !snapshot.systemSleeping {
                return restore(.externalLost(displayName: lastExternalName), now: now)
            }
            if configuration.askBeforeKeeping || trigger.isAutomatic {
                let deadline = now + configuration.confirmationSeconds
                phase = .confirming(trigger: trigger, method: method, since: date, deadline: deadline)
                return [
                    .watchdogDeadline(deadline),
                    .showConfirmation(deadline: deadline, onDisplayUUID: snapshot.usableExternals.first?.uuid),
                ]
            }
            phase = .active(trigger: trigger, method: method, since: date, engagedAt: now)
            return [.writeMarker(.active)]
        case .restoring:
            // The disable landed after the restore began, maybe after its enable ran.
            return succeeded ? sendEnable(now: now) : []
        case .idle:
            // A disable that outlived its timeout took the panel off after all:
            // guard it again and bring it back.
            guard succeeded else { return [] }
            let method = configuration.method
            var commands: [DeskModeCommand] = [.holdActivity(true)]
            if let displayID = targetDisplayID ?? snapshot.builtInDisplayID {
                commands.append(.armWatchdog(displayID: displayID, uuid: targetUUID ?? snapshot.builtInUUID, method: method))
            }
            commands.append(.writeMarker(.engaging))
            return commands + restore(.engageFailed, now: now)
        case .confirming, .active:
            return []
        }
    }

    private mutating func enableFinished(_ succeeded: Bool, now: TimeInterval) -> [DeskModeCommand] {
        guard case .restoring(let reason, let method, _) = phase else { return [] }
        if succeeded { return finish(reason) }
        enableAttempt = .failed
        phase = .restoring(reason: reason, method: method, lastAttempt: now)
        return []
    }

    private mutating func keep(now: TimeInterval) -> [DeskModeCommand] {
        // Too late once the deadline passed (the sidecar restores then too), or once sleep ended the prompt.
        guard case .confirming(let trigger, let method, let since, let deadline) = phase,
              now < deadline, !restoreAfterWake else { return [] }
        phase = .active(trigger: trigger, method: method, since: since, engagedAt: disabledAt ?? now)
        return [.hideConfirmation, .watchdogDeadline(nil), .writeMarker(.active)]
    }

    /// From idle, one enable and nothing else: Desk Mode isn't on as far as the machine
    /// knows, so there is nothing to guard, retry or announce. An asleep Mac drops it
    /// (no display call before `didWake`, and nobody presses keys on a sleeping Mac).
    private mutating func panic(now: TimeInterval) -> [DeskModeCommand] {
        guard phase == .idle else { return restore(.panic, now: now, pressed: true) }
        if sleeping { return [] }
        return [.enable(displayID: targetDisplayID ?? snapshot.builtInDisplayID, uuid: targetUUID ?? snapshot.builtInUUID, method: configuration.method)]
    }

    private mutating func resumeRestore(displayID: UInt32, uuid: String?, method: DeskModeMethod, now: TimeInterval) -> [DeskModeCommand] {
        if targetDisplayID == nil && targetUUID == nil {
            targetDisplayID = displayID
            targetUUID = uuid
        }
        switch phase {
        case .idle:
            // Guard it like an engage: the sidecar and the next launch take over if we die.
            phase = .restoring(reason: .recovery, method: method, lastAttempt: now)
            return [
                .holdActivity(true),
                .armWatchdog(displayID: displayID, uuid: uuid, method: method),
                .writeMarker(.engaging),
            ] + sendEnable(now: now)
        case .engaging, .confirming, .active:
            // Enabling always wins over Desk Mode.
            return restore(.recovery, now: now)
        case .restoring:
            // Already on its way back; `reconcile` sends an enable that waited for a panel.
            return []
        }
    }

    /// Only bookkeeping: no display call may run inside `willSleep`.
    private mutating func willSleep() -> [DeskModeCommand] {
        sleeping = true
        wakeSettleUntil = nil
        lossSince = nil
        switch phase {
        case .engaging:
            restoreAfterWake = true
            return []
        case .confirming:
            // Nobody can answer while asleep; the restore follows after wake. Uptime stops
            // during sleep, so the sidecar's deadline would pass while the enable verifies
            // after wake and it would kill a healthy app: clear it.
            restoreAfterWake = true
            return [.hideConfirmation, .watchdogDeadline(nil)]
        case .active:
            checkAfterWake = true
            return []
        case .idle, .restoring:
            return []
        }
    }

    private mutating func didWake(now: TimeInterval) -> [DeskModeCommand] {
        sleeping = false
        wakeSettleUntil = now + configuration.wakeSettleTime
        lossSince = nil
        // The displays wake with the Mac, and their readings may lag behind.
        screensWokeAt = now
        // Covers a missed willSleep.
        switch phase {
        case .confirming: restoreAfterWake = true
        case .active: checkAfterWake = true
        case .idle, .engaging, .restoring: break
        }
        return []
    }

    private mutating func willTerminate() -> [DeskModeCommand] {
        guard phase != .idle || disableInFlight else { return [] }
        let commands: [DeskModeCommand] = [
            .hideConfirmation,
            .enable(displayID: targetDisplayID ?? snapshot.builtInDisplayID, uuid: targetUUID ?? snapshot.builtInUUID, method: currentMethod),
            .disarmWatchdog,
            .clearMarker,
            .holdActivity(false),
        ]
        resetEngagement()
        disableInFlight = false
        phase = .idle
        return commands
    }

    // MARK: - Time and state rules

    /// Runs after every event: the sleep gate, deadlines, loss detection and retries.
    private mutating func reconcile(now: TimeInterval) -> [DeskModeCommand] {
        if sleeping { return [] }
        var commands: [DeskModeCommand] = []
        if let until = wakeSettleUntil {
            guard now >= until else {
                // Only the panic key's enable goes ahead before the reading settles.
                guard case .restoring(.panic, _, _) = phase else { return [] }
                return retryEnable(now: now)
            }
            wakeSettleUntil = nil
            commands += decideAfterWake(now: now)
        }
        switch phase {
        case .idle:
            break
        case .engaging(_, _, let startedAt):
            if now - startedAt >= configuration.engageTimeout {
                recordFailure(at: now)
                commands += restore(.engageFailed, now: now)
            }
        case .confirming(_, _, _, let deadline):
            commands += now >= deadline ? restore(.confirmationTimedOut, now: now) : watch(now: now)
        case .active(_, _, _, let engagedAt):
            if let limit = configuration.maxDuration, now - engagedAt >= limit {
                commands += restore(.timeLimit, now: now)
            } else {
                commands += watch(now: now)
            }
        case .restoring:
            commands += retryEnable(now: now)
        }
        return commands
    }

    /// Sends a held-back enable once nothing holds it, retries a failed one, and asks
    /// again when an answer never came.
    private mutating func retryEnable(now: TimeInterval) -> [DeskModeCommand] {
        guard case .restoring(_, _, let lastAttempt) = phase else { return [] }
        let elapsed = now - lastAttempt
        switch enableAttempt {
        case .pending: return sendEnable(now: now)
        case .failed where elapsed >= configuration.restoreRetryInterval: return sendEnable(now: now)
        case .inFlight where elapsed >= configuration.engageTimeout: return sendEnable(now: now)
        case .failed, .inFlight: return []
        }
    }

    /// Loss detection while the panel is off (confirming or active).
    private mutating func watch(now: TimeInterval) -> [DeskModeCommand] {
        if !snapshot.sessionActive { return restore(.sessionChanged, now: now) }
        // Our own transaction shuffles the display list for a moment.
        if let disabledAt, now < disabledAt + configuration.settleTime {
            lossSince = nil
            return []
        }
        // Display sleep makes every display inactive and system sleep makes readings stale:
        // decide once they wake.
        if snapshot.screensAsleep || snapshot.systemSleeping {
            lossSince = nil
            return []
        }
        if snapshot.presentExternals.isEmpty {
            // The controller reads the list again every tick, so a real unplug is confirmed
            // within about a second; a glitch in one reading is not.
            let since = lossSince ?? now
            lossSince = since
            guard now - since >= configuration.lossConfirmTime else { return [] }
            // A monitor coming out of standby may still be resyncing: give it
            // the grace before calling it unplugged.
            if let woke = screensWokeAt, now < woke + configuration.screenWakeGrace { return [] }
            return restore(.externalLost(displayName: lastExternalName), now: now)
        }
        lossSince = nil
        // A lid cycle or another tool brought the panel back: Desk Mode is over, never re-disable.
        if currentMethod == .disconnect && snapshot.builtInOnline { return settleQuietly() }
        return []
    }

    private mutating func decideAfterWake(now: TimeInterval) -> [DeskModeCommand] {
        let restorePending = restoreAfterWake, checkPending = checkAfterWake
        checkAfterWake = false
        // An engage in flight at sleep keeps the flag until its disable answers.
        if case .engaging = phase {} else { restoreAfterWake = false }
        switch phase {
        case .confirming where restorePending:
            return restore(.sleep, now: now)
        case .active(_, let method, _, _) where checkPending:
            if method == .disconnect && snapshot.builtInOnline { return settleQuietly() }
            return configuration.keepAfterWake ? [] : restore(.sleep, now: now)
        default:
            return []
        }
    }

    // MARK: - Restoring

    /// Hides the prompt and sends the enable, or holds it (see `sendEnable`). Leaving the
    /// prompt also clears the sidecar's deadline: past it (plus grace) the sidecar kills
    /// the app, which must not happen while the enable is still verifying.
    /// `pressed`: the panic key, whose first enable goes out whatever the lid or reading say.
    private mutating func restore(_ reason: DeskModeRestoreReason, now: TimeInterval, pressed: Bool = false) -> [DeskModeCommand] {
        var commands: [DeskModeCommand] = [.hideConfirmation]
        if case .confirming = phase { commands.append(.watchdogDeadline(nil)) }
        phase = .restoring(reason: reason, method: currentMethod, lastAttempt: now)
        return commands + sendEnable(now: now, pressed: pressed)
    }

    /// Sends the enable, or marks it pending (sent once that clears, never retried meanwhile):
    /// - between `willSleep` and `didWake`, always;
    /// - inside the wake settle time, except for the panic key: the user is there;
    /// - with the lid closed: the panel can't come online in clamshell, and an enable a
    ///   second would only churn the display configuration. It goes once the lid opens;
    /// - with no panel known (no ID and no UUID): there is nothing to address yet.
    /// `pressed` lets the panic key's first enable past the last two.
    private mutating func sendEnable(now: TimeInterval, pressed: Bool = false) -> [DeskModeCommand] {
        guard case .restoring(let reason, let method, _) = phase else { return [] }
        let displayID = targetDisplayID ?? snapshot.builtInDisplayID
        let uuid = targetUUID ?? snapshot.builtInUUID
        let unreachable = snapshot.lid == .closed || (displayID == nil && uuid == nil)
        if sleeping || (reason != .panic && isGated(now: now)) || (!pressed && unreachable) {
            enableAttempt = .pending
            return []
        }
        enableAttempt = .inFlight
        phase = .restoring(reason: reason, method: method, lastAttempt: now)
        return [.enable(displayID: displayID, uuid: uuid, method: method)]
    }

    /// The panel is verified back on.
    private mutating func finish(_ reason: DeskModeRestoreReason) -> [DeskModeCommand] {
        var commands: [DeskModeCommand] = [.disarmWatchdog, .clearMarker, .holdActivity(false)]
        if reason.isAnnounced { commands.append(.notifyRestored(reason)) }
        resetEngagement()
        phase = .idle
        return commands
    }

    /// The panel came back without us: stand down silently.
    private mutating func settleQuietly() -> [DeskModeCommand] {
        var commands: [DeskModeCommand] = []
        if case .confirming = phase { commands.append(.hideConfirmation) }
        commands += [.disarmWatchdog, .clearMarker, .holdActivity(false)]
        resetEngagement()
        phase = .idle
        return commands
    }

    private mutating func resetEngagement() {
        targetDisplayID = nil
        targetUUID = nil
        disabledAt = nil
        lossSince = nil
        enableAttempt = .inFlight
        restoreAfterWake = false
        checkAfterWake = false
    }

    /// Two failed engages within `failureWindow` latch Desk Mode off for `failureLatch`.
    private mutating func recordFailure(at now: TimeInterval) {
        if let last = lastFailureAt, now - last <= configuration.failureWindow {
            latchedUntil = now + configuration.failureLatch
            lastFailureAt = nil
        } else {
            lastFailureAt = now
        }
    }

    private func isGated(now: TimeInterval) -> Bool {
        sleeping || wakeSettleUntil.map { now < $0 } == true
    }

    private var currentMethod: DeskModeMethod {
        switch phase {
        case .idle: configuration.method
        case .engaging(_, let method, _), .confirming(_, let method, _, _),
             .active(_, let method, _, _), .restoring(_, let method, _): method
        }
    }
}

private extension DeskModeRestoreReason {
    /// The user asked for it (off, panic, quit) or it's carrying on a failed restore: no notification.
    var isAnnounced: Bool {
        switch self {
        case .user, .panic, .terminating, .recovery: false
        case .externalLost, .confirmationTimedOut, .declined, .sleep, .sessionChanged, .engageFailed, .timeLimit: true
        }
    }
}

private extension DeskModeState.Trigger {
    var isAutomatic: Bool {
        if case .automatic = self { return true }
        return false
    }
}
