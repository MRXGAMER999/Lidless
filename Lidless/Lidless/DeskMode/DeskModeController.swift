import Combine
import CoreGraphics
import Darwin
import Foundation
import LidlessCore
import os

/// A switch that serves both methods and must be pointed at one before a disable.
protocol DeskModeMethodSelecting: AnyObject {
    var method: DeskModeMethod { get set }
}

extension CompositeBuiltInSwitch: DeskModeMethodSelecting {}

/// Runs Desk Mode in a normal launch. `DeskModeMachine` decides everything;
/// this class only turns readings and user actions into the machine's events,
/// runs the commands it returns in order through the services, and publishes
/// the machine's state to the popover.
///
/// It never calls a display API on its own: every enable and disable is a
/// machine command, so the sleep gate and the other guards have no side path.
final class DeskModeController {
    /// Everything that touches the system, so tests can swap in fakes.
    struct Services {
        var builtIn: any BuiltInSwitch
        var confirmation: any ConfirmationPresenter
        var watchdog: any WatchdogLink
        var marker: any CrashMarkerStore
        var notifier: any DeskModeNotifier
        var activity: any ActivityHolder
        var hang: any HangWatchdogControl
        var modeWatch: any DisplayModeWatching = NoDisplayModeWatch()
    }

    /// Snapshots this soon after a wake re-baseline the plug-in rule: displays
    /// coming back from sleep are not newly plugged in.
    static let ruleWakeGrace: TimeInterval = 5
    /// The longest the quit, signal and power-off paths wait for the panel.
    static let exitRestoreTimeout: TimeInterval = 3
    /// Debug builds only: seconds after which Desk Mode ends by itself, from the
    /// launch argument `-LidlessDeskModeTimeLimit 300` or the same defaults key.
    static let debugTimeLimitKey = "LidlessDeskModeTimeLimit"

    private(set) var machine: DeskModeMachine
    private var rules = DeskModeRuleEngine()
    private let model: AppModel
    private let services: Services
    private let names: DisplayNames
    private let clock: () -> TimeInterval
    private let date: () -> Date
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "DeskMode")

    // What the next snapshot is built from.
    private var facts: [DisplayFacts]?
    private var lid: LidState
    private var power: PowerSource
    private var screensAsleep = false
    private var systemSleeping = false
    private var sessionActive = true
    private var lastSnapshot: DeskModeSnapshot?
    /// Until this time, snapshots re-baseline the rule instead of firing it.
    private var ruleBaselineUntil: TimeInterval?

    /// Events raised while commands run (a completion that calls back at once)
    /// wait here, so commands always run in the order the machine gave them.
    private var pending: [DeskModeEvent] = []
    private var isProcessing = false
    /// The quit, signal and power-off paths enable synchronously.
    private var isExiting = false
    /// That enable wasn't reported done (a transaction was still running): the
    /// sidecar stays armed and the marker stays, so the sidecar restores once
    /// this process is gone and the next launch recovers.
    private var exitRestoreFailed = false
    private(set) var hasTerminated = false
    private var hangArmed = false
    /// `requestTurnOn(forcePrompt: true)` ("Test the safety net", an intent
    /// before onboarding): the engage in flight asks before keeping the panel
    /// off whatever the setting says. Cleared once it leaves `.engaging`.
    private var forcesPrompt = false
    /// "Try It" and onboarding's "Try it now", told about the next panic key press.
    let panicKeyWaiters = PanicKeyWaiters()
    /// The panic key Carbon holds now, put back when a new one can't be registered.
    private var registeredPanic: KeyShortcut?
    /// The panel the current session turns off, for the crash marker.
    private var target: (displayID: UInt32, uuid: String?, method: DeskModeMethod)?
    /// The panel the exit path couldn't confirm back, for a power off that
    /// turns out not to be one.
    private var unconfirmedExitTarget: (displayID: UInt32, uuid: String?, method: DeskModeMethod)?
    /// A sidecar was armed and not sent away since. Nothing turns the panel
    /// off without one.
    private var isWatchdogArmed = false
    /// What the machine last asked of the activity holder.
    private var wantsActivity = false
    private var isHoldingActivity = false
    /// The deadline the sidecar holds.
    private var watchdogDeadline: TimeInterval?

    /// Set by `SystemController`: re-reads the displays, whose facts then
    /// arrive through `displaysDidChange`.
    var readDisplays: (() -> Void)?

    /// Boost hears when Desk Mode leaves idle (before the disable runs) and
    /// returns to it, and gets the panic key. Set by the app delegate.
    weak var boost: (any DeskModeBoostInterlock)?
    /// What Boost was last told: (engaged, switching).
    private var reportedToBoost = (engaged: false, switching: false)

    nonisolated(unsafe) private var tickTimer: Timer?
    /// Fires just after the prompt's deadline, so the screen comes back as the
    /// countdown reaches 0 rather than on the next 1 s tick.
    nonisolated(unsafe) private var deadlineTimer: Timer?
    private var hotKeys: HotKeyCenter?
    private var subscriptions: Set<AnyCancellable> = []

    /// - Parameters:
    ///   - configuration: Timings; the method and the two switches come from
    ///     `model.preferences`. Debug builds end Desk Mode after
    ///     `debugTimeLimitKey` seconds when that is set (off by default).
    ///   - clock: Monotonic seconds, the clock the sidecar and the prompt share.
    init(
        model: AppModel,
        services: Services,
        configuration: DeskModeMachine.Configuration = .init(),
        names: DisplayNames = .localized,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        date: @escaping () -> Date = { Date() }
    ) {
        self.model = model
        self.services = services
        self.names = names
        self.clock = clock
        self.date = date
        lid = model.system.lid
        power = model.system.power
        var configuration = configuration
        #if DEBUG
        if configuration.maxDuration == nil { configuration.maxDuration = Self.debugTimeLimit() }
        #endif
        Self.apply(model.preferences.deskMode, forcingPrompt: false, to: &configuration)
        machine = DeskModeMachine(configuration: configuration, availability: model.deskMode.unavailableReason)
    }

    deinit {
        tickTimer?.invalidate()
        deadlineTimer?.invalidate()
    }

    /// The Debug time limit, or nil (the default): no limit. It used to be 5
    /// minutes in every Debug build, which ended hands-on sessions run from
    /// Xcode by itself. A breakpoint or a hang doesn't need it: the sidecar
    /// kills a stopped app after its hang timeout and restores the panel.
    static func debugTimeLimit(_ defaults: UserDefaults = .standard) -> TimeInterval? {
        let seconds = defaults.double(forKey: debugTimeLimitKey)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    /// Takes over the popover switch and follows the preferences. Call before
    /// `SystemController.start()`, so the first reading arrives here.
    func start() {
        model.deskMode.requestHandler = { [weak self] on in self?.setOn(on) }
        let preferences = model.preferences
        // @Published sends the new value before it is stored: use the value.
        preferences.$deskMode
            .removeDuplicates()
            .sink { [weak self] settings in self?.settingsDidChange(settings) }
            .store(in: &subscriptions)
        preferences.$shortcuts
            .removeDuplicates()
            .sink { [weak self] shortcuts in self?.shortcutsDidChange(shortcuts) }
            .store(in: &subscriptions)
        publish()
    }

    /// Registers the panic key (always) and the Desk Mode key (when set), and
    /// re-registers them whenever the shortcuts change.
    func bindHotKeys(_ center: HotKeyCenter) {
        hotKeys = center
        registerHotKeys(model.preferences.shortcuts)
    }

    // MARK: Readings from SystemController

    /// After every display refresh, with the same facts the popover got.
    func displaysDidChange(facts: [DisplayFacts], lid: LidState, power: PowerSource) {
        self.facts = facts
        self.lid = lid
        self.power = power
        pushSnapshot()
    }

    /// Lid or power changed without a display refresh.
    func systemDidChange(lid: LidState, power: PowerSource) {
        guard lid != self.lid || power != self.power else { return }
        self.lid = lid
        self.power = power
        pushSnapshot()
    }

    func availabilityDidChange(_ reason: DeskModeState.UnavailableReason?) {
        guard reason != machine.availability else { return }
        send(.availability(reason))
    }

    /// System events. Readings that follow an event (after wake, screen wake,
    /// session return) arrive through `displaysDidChange` right after, so
    /// nothing here re-reads the displays; during `willSleep` nothing may.
    func handle(_ event: SystemEvent) {
        switch event {
        case .willSleep:
            systemSleeping = true
            send(.willSleep)
            pushSnapshot()
        case .didWake:
            systemSleeping = false
            ruleBaselineUntil = clock() + Self.ruleWakeGrace
            send(.didWake)
        case .screensDidSleep:
            if machine.phase != .idle { log.notice("Screens asleep with Desk Mode on; loss checks wait for them to wake") }
            screensAsleep = true
            pushSnapshot()
        case .screensDidWake:
            if machine.phase != .idle { log.notice("Screens awake with Desk Mode on") }
            screensAsleep = false
            ruleBaselineUntil = clock() + Self.ruleWakeGrace
        case .sessionDidResignActive:
            sessionActive = false
            pushSnapshot()
        case .sessionDidBecomeActive:
            sessionActive = true
        case .willPowerOff:
            // Logging out may still be cancelled, so this is not a quit: the
            // panel comes back and Desk Mode can be turned on again.
            log.notice("Power off or log out: restoring the built-in screen")
            if let target = restoreForExit() {
                // Still off, and this process may live on: keep trying, as any restore does.
                resumeRestore(displayID: target.displayID, uuid: target.uuid, method: target.method)
            }
        case .lid, .power, .thermal:
            // Readings arrive through `systemDidChange`.
            break
        }
    }

    // MARK: User actions

    /// The popover switch, through `DeskModeStore.setOn`.
    func setOn(_ on: Bool) {
        if on {
            send(.turnOn(trigger: .manual))
        } else {
            declineRule()
            send(.turnOff)
        }
    }

    /// The Desk Mode shortcut.
    func toggle() {
        setOn(!machine.state.isOn)
    }

    /// Turns Desk Mode on like the popover switch. With `forcePrompt`, the
    /// keep-or-revert prompt shows even with "Ask before keeping it off"
    /// switched off, so the user sees the screen come back and can answer
    /// ("Test the safety net"; an intent before onboarding finished). Every
    /// guard of a normal turn-on applies; the force lasts for this engage only
    /// and is dropped when the turn-on is refused.
    func requestTurnOn(forcePrompt: Bool) {
        // Not idle: the machine refuses it as busy, and an engage already in
        // flight keeps the prompt setting it started with.
        if forcePrompt, machine.phase == .idle {
            forcesPrompt = true
            Self.apply(model.preferences.deskMode, forcingPrompt: true, to: &machine.configuration)
        }
        send(.turnOn(trigger: .manual))
    }

    /// Settings › "Test the safety net": Desk Mode on with the prompt forced.
    func testSafetyNet() {
        log.notice("Testing the safety net")
        requestTurnOn(forcePrompt: true)
    }

    /// The panic key's action (also the intent's): always sends an enable,
    /// whatever the machine thinks, and ends Boost and the external shades.
    func panic() {
        log.notice("Panic key")
        boost?.panic()
        declineRule()
        send(.panic)
    }

    /// A press of the panic key itself (Carbon, or the menu-tracking monitor):
    /// the full `panic()`, then whoever waits for the key hears about it. The
    /// waiters only watch: nothing skips the panic.
    func panicKeyPressed() {
        panic()
        panicKeyWaiters.fire()
    }

    /// "Try It" / onboarding: `pressed` runs once, at the next press of the
    /// panic key, after that press's `panic()`. Survives shortcut changes.
    func awaitPanicKey(_ pressed: @escaping @MainActor () -> Void) {
        panicKeyWaiters.add(pressed)
    }

    /// Stops every wait. Limitation: waits aren't told apart, so when two
    /// screens wait at once (Settings' Try It and onboarding), either one
    /// cancelling cancels both; a screen that still wants the key asks again.
    func cancelAwaitPanicKey() {
        panicKeyWaiters.cancelAll()
    }

    /// Launch recovery (or a power off that wasn't) couldn't confirm the panel
    /// back: the machine retries the enable until it is, and the crash marker
    /// stays until then.
    func resumeRestore(displayID: UInt32, uuid: String?, method: DeskModeMethod) {
        send(.resumeRestore(displayID: displayID, uuid: uuid, method: method))
    }

    /// Black out's cover removed itself (its screen went away or changed):
    /// the panel is back, so Desk Mode ends without a notification.
    func coverLost() {
        if machine.phase != .idle { log.notice("Black out's cover removed itself; ending Desk Mode") }
        send(.turnOff)
    }

    /// Quit or a signal: brings the panel back synchronously, clears the
    /// marker, sends the sidecar away and stops everything. Idempotent.
    func terminate() {
        guard !hasTerminated else { return }
        restoreForExit()
        hasTerminated = true
        stopTicking()
        cancelDeadlineTick()
        hotKeys?.unregisterAll()
        registeredPanic = nil
        panicKeyWaiters.cancelAll()
        subscriptions.removeAll()
        // The switch handler stays: flips after this are ignored rather than
        // changing the store as a sample launch would.
    }

    // MARK: Ticks

    /// True while the 1 s tick runs.
    var isTicking: Bool { tickTimer != nil }

    /// One tick: the machine's deadlines and retries, then the plug-in rule.
    /// The timer calls it; tests call it directly.
    func tick() {
        // While the panel is off or switching, a missed display callback must
        // not delay loss detection: read the list again. Never during sleep.
        if machine.needsTicks, !systemSleeping { readDisplays?() }
        if machine.needsTicks { send(.tick) }
        let now = clock()
        if let name = rules.due(now: now, snapshot: machine.snapshot, rule: model.preferences.deskMode.rule) {
            log.info("Plug-in rule fired")
            send(.turnOn(trigger: .automatic(displayName: name)))
        }
        updateTicking()
    }

    private func updateTicking() {
        if !hasTerminated, machine.needsTicks || rules.pending != nil {
            guard tickTimer == nil else { return }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.1
            // Common modes: keeps ticking while a menu or the slider tracks.
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        } else {
            stopTicking()
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func scheduleDeadlineTick(at deadline: TimeInterval) {
        cancelDeadlineTick()
        let timer = Timer(timeInterval: max(0, deadline - clock()) + 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deadlineTimer = nil
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }

    private func cancelDeadlineTick() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
    }

    /// True while the prompt's deadline tick is scheduled.
    var isWaitingForDeadline: Bool { deadlineTimer != nil }

    // MARK: Machine

    private func pushSnapshot() {
        guard let facts else { return }
        let snapshot = DeskModeSnapshot(
            facts: facts,
            previous: lastSnapshot,
            lid: lid,
            screensAsleep: screensAsleep,
            systemSleeping: systemSleeping,
            sessionActive: sessionActive,
            power: power,
            names: names
        )
        lastSnapshot = snapshot
        send(.snapshot(snapshot))
        observeRule(snapshot)
    }

    private func observeRule(_ snapshot: DeskModeSnapshot) {
        // Asleep displays can drop out of the list; they aren't unplugged.
        guard !screensAsleep else { return }
        let now = clock()
        if let until = ruleBaselineUntil, now < until {
            rules.baseline(snapshot)
        } else {
            ruleBaselineUntil = nil
            rules.observe(snapshot, rule: model.preferences.deskMode.rule, now: now)
        }
        updateTicking()
    }

    /// The user took the screen back: the rule doesn't fire again for the
    /// displays connected now until they reconnect.
    private func declineRule() {
        rules.userDeclined(currentExternals: machine.snapshot.externals)
    }

    /// Returns the panel when its enable couldn't be confirmed.
    @discardableResult
    private func restoreForExit() -> (displayID: UInt32, uuid: String?, method: DeskModeMethod)? {
        isExiting = true
        exitRestoreFailed = false
        unconfirmedExitTarget = nil
        send(.willTerminate)
        isExiting = false
        exitRestoreFailed = false
        let unconfirmed = unconfirmedExitTarget
        unconfirmedExitTarget = nil
        return unconfirmed
    }

    private func send(_ event: DeskModeEvent) {
        guard !hasTerminated else { return }
        pending.append(event)
        guard !isProcessing else { return }
        isProcessing = true
        while !pending.isEmpty {
            let event = pending.removeFirst()
            let before = machine.phase
            let now = clock()
            let commands = machine.handle(event, now: now, date: date())
            if machine.phase != before {
                log.info("\(Self.describe(before), privacy: .public) → \(Self.describe(self.machine.phase), privacy: .public) on \(Self.describe(event), privacy: .public)")
                logEnding(from: before, on: event, now: now)
            }
            // Before the commands: the Boost overlay must be gone before a disable starts.
            reportToBoost()
            for command in commands { run(command) }
        }
        isProcessing = false
        endForcedPromptIfDone()
        publish()
        let armHang = machine.phase != .idle
        if armHang != hangArmed {
            hangArmed = armHang
            services.hang.setArmed(armHang)
        }
        updateTicking()
    }

    /// One notice-level line for every path that ends Desk Mode, and one when
    /// the panel is verified back, so `log stream` (which leaves out info
    /// lines) always shows why the built-in screen came back.
    private func logEnding(from before: DeskModeMachine.Phase, on event: DeskModeEvent, now: TimeInterval) {
        let after = machine.phase
        if let end = DeskModeEnd.detect(from: before, to: after, on: event) {
            let length = DeskModeEnd.sessionLength(of: before, now: now, confirmationSeconds: machine.configuration.confirmationSeconds)
            let seconds = length.map { String(format: "%.0f", $0) } ?? "?"
            log.notice("Desk Mode ending [\(end.key, privacy: .public)] after \(seconds, privacy: .public) s in \(Self.describe(before), privacy: .public), on \(Self.describe(event), privacy: .public): \(end.explanation, privacy: .public)")
        } else if case .restoring(let reason, _, _) = before, after == .idle {
            log.notice("Built-in screen back on [\(reason.logKey, privacy: .public)]; Desk Mode is off")
        } else if case .restoring(let reason, _, _) = after, before == .idle {
            log.notice("Restoring the built-in screen from idle [\(reason.logKey, privacy: .public)] on \(Self.describe(event), privacy: .public)")
        }
    }

    /// The machine reads `askBeforeKeeping` when the disable lands, so the
    /// forced prompt lasts until the engage is over (prompt shown, refused or failed).
    private func endForcedPromptIfDone() {
        guard forcesPrompt else { return }
        if case .engaging = machine.phase { return }
        forcesPrompt = false
        Self.apply(model.preferences.deskMode, forcingPrompt: false, to: &machine.configuration)
    }

    private func run(_ command: DeskModeCommand) {
        switch command {
        case let .armWatchdog(displayID, uuid, method):
            target = (displayID, uuid, method)
            if services.watchdog.arm(displayID: displayID, method: method, uuid: uuid) {
                isWatchdogArmed = true
            } else {
                log.error("The watchdog isn't running; Desk Mode won't turn the built-in screen off without it")
            }
        case let .watchdogDeadline(deadline):
            setWatchdogDeadline(deadline)
        case .disarmWatchdog:
            guard !exitRestoreFailed else { return log.error("Leaving the sidecar armed: the panel may still be off") }
            services.watchdog.disarm()
            isWatchdogArmed = false
            watchdogDeadline = nil
            updateActivity()
        case let .writeMarker(stage):
            writeMarker(stage)
        case .clearMarker:
            guard !exitRestoreFailed else { return log.error("Keeping the crash marker for the next launch") }
            services.marker.clear()
        case let .holdActivity(on):
            wantsActivity = on
            updateActivity()
        case let .disable(displayID, uuid, method):
            guard isWatchdogArmed else {
                // Answered as a failed disable, so the machine restores and counts it.
                pending.append(.disableFinished(succeeded: false))
                return
            }
            target = (displayID, uuid, method)
            (services.builtIn as? DeskModeMethodSelecting)?.method = method
            log.info("Turning the built-in screen off (\(method.rawValue, privacy: .public))")
            services.modeWatch.willSwitch()
            services.builtIn.disable(displayID: displayID, uuid: uuid) { [weak self] ok in
                if ok { self?.services.modeWatch.didSwitch() }
                self?.send(.disableFinished(succeeded: ok))
            }
        case let .enable(displayID, uuid, method):
            if isExiting {
                let ok = services.builtIn.enableNow(displayID: displayID, uuid: uuid, timeout: Self.exitRestoreTimeout)
                exitRestoreFailed = !ok
                if ok {
                    log.notice("Turned the built-in screen back on before exit")
                } else {
                    log.error("Couldn't confirm the built-in screen is back before exit; the sidecar and the next launch take over")
                    if let displayID = displayID ?? target?.displayID {
                        unconfirmedExitTarget = (displayID, uuid ?? target?.uuid, method)
                    }
                }
            } else {
                log.info("Turning the built-in screen on")
                services.modeWatch.willSwitch()
                services.builtIn.enable(displayID: displayID, uuid: uuid) { [weak self] ok in
                    if ok { self?.services.modeWatch.didSwitch() }
                    self?.send(.enableFinished(succeeded: ok))
                }
            }
        case let .showConfirmation(deadline, displayUUID):
            services.confirmation.show(
                deadline: deadline,
                total: machine.configuration.confirmationSeconds,
                onDisplayUUID: displayUUID,
                keep: { [weak self] in self?.send(.keep) },
                revert: { [weak self] in
                    self?.declineRule()
                    self?.send(.revert)
                }
            )
            scheduleDeadlineTick(at: deadline)
        case .hideConfirmation:
            cancelDeadlineTick()
            services.confirmation.hide()
            // The sidecar's deadline belongs to the prompt: past it the sidecar
            // kills the app, which must not happen once nobody is asked.
            setWatchdogDeadline(nil)
        case let .notifyRestored(reason):
            services.notifier.restored(reason)
        case let .refused(refusal):
            log.notice("Desk Mode refused: \(Self.describe(refusal), privacy: .public)")
        }
    }

    private func reportToBoost() {
        // The keep-or-revert prompt counts as switching: its Revert (or the
        // deadline) enables the panel again at any moment, so DDC stays quiet.
        let switching: Bool
        switch machine.phase {
        case .engaging, .confirming, .restoring: switching = true
        case .idle, .active: switching = false
        }
        let state = (engaged: machine.phase != .idle, switching: switching)
        guard state != reportedToBoost else { return }
        reportedToBoost = state
        boost?.deskModeDidChange(engaged: state.engaged, switching: state.switching)
    }

    private func setWatchdogDeadline(_ deadline: TimeInterval?) {
        guard deadline != watchdogDeadline else { return }
        watchdogDeadline = deadline
        services.watchdog.setDeadline(deadline)
    }

    /// App Nap stays held off while the sidecar is armed, even after the
    /// machine let go (an exit restore that failed leaves it armed): coalesced
    /// heartbeats would read as a hang and get this process killed.
    private func updateActivity() {
        let hold = wantsActivity || isWatchdogArmed
        guard hold != isHoldingActivity else { return }
        isHoldingActivity = hold
        services.activity.hold(hold)
    }

    private func writeMarker(_ stage: CrashMarker.Stage) {
        let snapshot = machine.snapshot
        guard let target = target ?? snapshot.builtInDisplayID.map({ (displayID: $0, uuid: snapshot.builtInUUID, method: machine.configuration.method) }) else {
            log.error("No built-in display to write a crash marker for")
            return
        }
        services.marker.write(CrashMarker(
            stage: stage,
            method: target.method,
            builtInDisplayID: target.displayID,
            builtInUUID: target.uuid,
            pid: getpid(),
            bootSessionUUID: services.marker.currentBootSession,
            writtenAt: date()
        ))
    }

    private func publish() {
        // Before the state: whoever reacts to `.on` reads whether it asks.
        let confirming = if case .confirming = machine.phase { true } else { false }
        model.deskMode.setConfirming(confirming)
        model.deskMode.update(machine.state)
    }

    // MARK: Preferences

    /// A new method applies from the next disable; an enable always goes to
    /// both switches (`CompositeBuiltInSwitch`), so a change mid-session can't
    /// strand the panel.
    private func settingsDidChange(_ settings: DeskModeSettings) {
        Self.apply(settings, forcingPrompt: forcesPrompt, to: &machine.configuration)
    }

    private static func apply(_ settings: DeskModeSettings, forcingPrompt: Bool, to configuration: inout DeskModeMachine.Configuration) {
        configuration.method = settings.method
        configuration.askBeforeKeeping = settings.askBeforeKeeping || forcingPrompt
        configuration.keepAfterWake = settings.keepAfterWake
    }

    private func shortcutsDidChange(_ shortcuts: ShortcutSet) {
        if model.deskMode.panicShortcut != shortcuts.panic {
            model.deskMode.panicShortcut = shortcuts.panic
        }
        registerHotKeys(shortcuts)
    }

    private func registerHotKeys(_ shortcuts: ShortcutSet) {
        guard let hotKeys, !hasTerminated else { return }
        registerPanicKey(shortcuts.panic, in: hotKeys)
        if let key = shortcuts.toggleDeskMode {
            // Held back while the shortcut recorder listens: registered on resume, nothing to report.
            let toggle = hotKeys.register(key, for: .toggleDeskMode, handler: { [weak self] in self?.toggle() })
            if case .failed(let status) = toggle {
                log.error("Couldn't register the Desk Mode key: \(status, privacy: .public)")
            }
        } else {
            hotKeys.unregister(.toggleDeskMode)
        }
    }

    /// The panic key must always be held. A new combination Carbon refuses
    /// puts the one that worked back, and the saved shortcut follows.
    private func registerPanicKey(_ shortcut: KeyShortcut, in hotKeys: HotKeyCenter) {
        let handler: @MainActor () -> Void = { [weak self] in self?.panicKeyPressed() }
        switch hotKeys.register(shortcut, for: .panic, handler: handler) {
        case .exclusive, .deferred:
            registeredPanic = shortcut
        case .shared:
            // Once per combination: other shortcut changes re-register it too.
            guard registeredPanic != shortcut else { return }
            registeredPanic = shortcut
            log.error("Another app holds the panic key \(Self.describe(shortcut), privacy: .public) too and may receive the presses instead; choose another one in Settings › Keys & App")
        case .failed(let status):
            guard let previous = registeredPanic, previous != shortcut else {
                log.fault("Couldn't register the panic key \(Self.describe(shortcut), privacy: .public): \(status, privacy: .public); it won't work until it can be")
                return
            }
            log.error("Couldn't register the new panic key \(Self.describe(shortcut), privacy: .public): \(status, privacy: .public); keeping \(Self.describe(previous), privacy: .public)")
            let restored = hotKeys.register(previous, for: .panic, handler: handler)
            if !restored.isRegistered {
                registeredPanic = nil
                log.fault("Couldn't register the previous panic key again either: \(String(describing: restored), privacy: .public)")
            }
            // Not from inside this `$shortcuts` sink: the assignment in progress
            // would store the refused key over the revert.
            DispatchQueue.main.async { [weak self] in self?.revertPanicShortcut(from: shortcut, to: previous) }
        }
    }

    /// Puts the saved panic key back to the one Carbon holds, unless the user
    /// changed it again meanwhile. The change lands through `shortcutsDidChange`.
    private func revertPanicShortcut(from refused: KeyShortcut, to previous: KeyShortcut) {
        let preferences = model.preferences
        guard !hasTerminated, preferences.shortcuts.panic == refused else { return }
        var shortcuts = preferences.shortcuts
        shortcuts.panic = previous
        // The recorder never saves a combination twice, so this only guards a
        // slot that picked up the old panic key in the same change.
        if shortcuts.toggleDeskMode == previous { shortcuts.toggleDeskMode = nil }
        if shortcuts.toggleBoost == previous { shortcuts.toggleBoost = nil }
        preferences.shortcuts = shortcuts
    }

    // MARK: Logging

    private static func describe(_ phase: DeskModeMachine.Phase) -> String {
        switch phase {
        case .idle: "idle"
        case .engaging(_, let method, _): "engaging(\(method.rawValue))"
        case .confirming(_, let method, _, _): "confirming(\(method.rawValue))"
        case .active(_, let method, _, _): "active(\(method.rawValue))"
        case .restoring(let reason, _, _): "restoring(\(describe(reason)))"
        }
    }

    /// Display names stay out of the log.
    private static func describe(_ reason: DeskModeRestoreReason) -> String {
        switch reason {
        case .externalLost: "externalLost"
        default: String(describing: reason)
        }
    }

    private static func describe(_ event: DeskModeEvent) -> String {
        switch event {
        case .turnOn(.manual): "turnOn(manual)"
        case .turnOn(.automatic): "turnOn(automatic)"
        case .snapshot: "snapshot"
        default: String(describing: event)
        }
    }

    /// "⌃⌥⌘B".
    private static func describe(_ shortcut: KeyShortcut) -> String {
        shortcut.keycaps.joined()
    }

    private static func describe(_ refusal: DeskModeRefusal) -> String {
        switch refusal {
        case .unavailable(let reason): "unavailable(\(reason))"
        case .notReady: "notReady"
        case .latched: "latched"
        case .busy: "busy"
        }
    }
}

/// Who waits for the next press of the panic key ("Try It", onboarding's
/// "Try it now"). They only watch: the press has already run the full panic.
///
/// Waits aren't told apart (the `SettingsActions` contract has no tokens), so
/// `cancelAll` ends every one of them.
final class PanicKeyWaiters {
    private var waiters: [@MainActor () -> Void] = []

    var isWaiting: Bool { !waiters.isEmpty }
    var count: Int { waiters.count }

    /// `pressed` runs once, at the next `fire()`.
    func add(_ pressed: @escaping @MainActor () -> Void) {
        waiters.append(pressed)
    }

    func cancelAll() {
        waiters.removeAll()
    }

    /// Runs every waiter once, in the order they came. A waiter that waits
    /// again from inside its callback waits for the press after this one.
    func fire() {
        let pressed = waiters
        waiters.removeAll()
        for waiter in pressed { waiter() }
    }
}
