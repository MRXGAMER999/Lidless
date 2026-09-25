import AppKit
import Combine
import CoreGraphics
import Foundation
import LidlessCore
import os

/// Posts "Brightness Boost paused". `UserNotifier` is the live one.
protocol BoostNotifier: AnyObject {
    func boostPaused(hot: Bool)
}

extension UserNotifier: BoostNotifier {}

/// What Desk Mode tells Boost, so the overlay is gone before the built-in
/// switches and DDC stays quiet while displays change.
protocol DeskModeBoostInterlock: AnyObject {
    /// `engaged`: Desk Mode is anything but idle (the built-in is off or
    /// switching). `switching`: turning the built-in off or on right now, or
    /// the keep-or-revert prompt is up (it can turn the built-in on at any moment).
    func deskModeDidChange(engaged: Bool, switching: Bool)
    /// The panic key.
    func panic()
}

/// Changes Boost hears about outside `SystemEvent`.
enum BoostSignal: Sendable, Equatable {
    /// `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`.
    case screenLocked(Bool)
    /// Low Power Mode turned on or off.
    case lowPowerMode(Bool)
    /// macOS asks apps to stop (or may start again) showing HDR (macOS 26+).
    /// Logged only: it never blocks Boost (see `BoostGuard.block`).
    case hdrSuppressed(Bool)
    /// A CoreGraphics reconfiguration pass began (`beginConfigurationFlag`).
    case reconfigurationBegan
    /// A CoreGraphics reconfiguration pass reported its changes.
    case reconfigurationEnded
}

/// Lock, Low Power Mode, HDR suppression and display reconfiguration.
/// `BoostSignalMonitor` is the live one.
protocol BoostSignalSource: AnyObject {
    var isScreenLocked: Bool { get }
    var isLowPowerModeEnabled: Bool { get }
    var isHDRSuppressed: Bool { get }
    /// `handler` runs on the main actor. Starting twice is a no-op.
    func start(handler: @escaping @MainActor (BoostSignal) -> Void)
    func stop()
}

/// Runs Brightness Boost and external brightness in a normal launch.
///
/// - The popover slider's normal part (0...100) becomes native brightness
///   through `BuiltInBrightnessWriter`; above 100 native stays at full and the
///   Boost factor goes to `BoostMachine`, whose commands drive the overlay.
/// - Guard rails reach the machine as `BoostConditions`: readings from
///   `SystemController`, Desk Mode through `DeskModeBoostInterlock`, lock,
///   Low Power Mode and reconfiguration through `BoostSignalSource`
///   (which also reports HDR suppression, logged only). Blocks hide the overlay at once (a fade already
///   under way included); the panic key tears it down and leaves Boost.
/// - External sliders go to `ExternalBrightnessControl`, which is paused while
///   displays reconfigure, Desk Mode switches or the Mac sleeps.
///
/// It never writes gamma and never writes native brightness as part of Boost.
final class BoostController: DeskModeBoostInterlock {
    struct Services {
        var overlay: any BoostOverlay
        var writer: any BuiltInBrightnessWriter
        var externals: any ExternalBrightnessControl
        var keys: any BrightnessKeySource
        var notifier: any BoostNotifier
        var signals: any BoostSignalSource
    }

    /// The machine's tick while it engages, backs off or coalesces.
    static let tickInterval: TimeInterval = 0.25
    /// Boost stays suspended this long after a reconfiguration or a wake.
    static let settleTime: TimeInterval = 3
    /// A reconfiguration whose end never arrived stops suspending after this.
    static let reconfigurationLimit: TimeInterval = 15
    /// DDC waits this long after displays change (research §3.4).
    static let externalsResumeDelay: TimeInterval = 1
    static let externalsWakeDelay: TimeInterval = 3
    /// macOS applies a brightness key itself; read the level after this.
    static let keyFollowDelay: TimeInterval = 0.15
    /// A lost overlay counts as a failure only if no reconfiguration begins
    /// within this: the window can go before the reconfiguration signal arrives.
    static let lossGrace: TimeInterval = 0.5

    private(set) var machine: BoostMachine
    private let model: AppModel
    private let services: Services
    private let clock: () -> TimeInterval
    private let isInMirrorSet: (CGDirectDisplayID) -> Bool
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Boost")

    private var conditions = BoostConditions()
    private var settings: BoostSettings
    private var sentConditions: (BoostConditions, BoostSettings)?
    private var builtInID: CGDirectDisplayID?
    /// A reference preset: BezelServices owns the level, so nothing is written.
    private var presetLocksBrightness = false
    /// The built-in is in a mirror set (source or follower).
    private var builtInMirrored = false
    /// While asleep, from `willSleep` to the wake.
    private var systemSleeping = false
    private var screensAsleep = false
    /// Between a reconfiguration's begin and end passes.
    private var reconfigurationInProgress = false
    /// When a reconfiguration whose end never came stops counting as one.
    private var reconfigurationDeadline: TimeInterval?
    /// Settle after a reconfiguration's end or a wake: Boost stays suspended
    /// until then. Only ever pushed later, never shortened.
    private var suspendedUntil: TimeInterval?
    /// The last slider position in the Boost range the user settled on (not
    /// the positions a drag passed through), for the toggle key.
    private var lastBoostedPosition: Double?
    /// A native level the guards held back; written when they clear, unless a
    /// read or a newer write replaced it.
    private var skippedNativeLevel: Double?
    /// Whether native writes were held back at the last check; nil before it.
    private var nativeWritesWereBlocked: Bool?
    /// The last position the store reported, to tell a move within Boost.
    private var lastPosition: Double
    private var externalPauses: Set<ExternalPause> = []
    /// The online displays last given to the external controller.
    private var knownDisplays: [DisplayDescriptor] = []
    private var knownExternals: [DisplayDescriptor] = []

    private var pending: [BoostEvent] = []
    private var isProcessing = false
    private(set) var hasTerminated = false
    private var isStarted = false

    nonisolated(unsafe) private var tickTimer: Timer?
    nonisolated(unsafe) private var settleTimer: Timer?
    nonisolated(unsafe) private var keyFollowTimer: Timer?
    nonisolated(unsafe) private var lossTimer: Timer?
    private var hotKeys: HotKeyCenter?
    private var subscriptions: Set<AnyCancellable> = []

    /// Set by `SystemController`: reads the built-in's level now (nil when offline).
    var readBrightness: (() -> BrightnessLevelReading?)?
    /// Set by `SystemController`: runs when the slider enters (true) or leaves
    /// Boost, so macOS's level is followed while boosted with the popover closed.
    var boostedDidChange: ((Bool) -> Void)?

    private enum ExternalPause: Hashable {
        case reconfiguration, deskMode, sleep
    }

    /// - Parameters:
    ///   - clock: Monotonic seconds; tests pass a fake.
    ///   - isInMirrorSet: Whether a display mirrors or is mirrored (the built-in
    ///     as a mirror source isn't in the inventory's roles); tests pass a fake.
    init(
        model: AppModel,
        services: Services,
        configuration: BoostMachine.Configuration = .init(),
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        isInMirrorSet: @escaping (CGDirectDisplayID) -> Bool = { CGDisplayIsInMirrorSet($0) != 0 }
    ) {
        self.model = model
        self.services = services
        self.clock = clock
        self.isInMirrorSet = isInMirrorSet
        machine = BoostMachine(configuration: configuration)
        settings = model.preferences.boost
        lastPosition = model.brightness.position
        // Nothing shows before the first display refresh says the panel is there.
        conditions.builtInOnline = false
        conditions.panelSupportsBoost = false
    }

    deinit {
        tickTimer?.invalidate()
        settleTimer?.invalidate()
        keyFollowTimer?.invalidate()
        lossTimer?.invalidate()
    }

    /// Takes over the brightness stores and starts listening. Call before
    /// `SystemController.start()`, so the first readings arrive here.
    func start() {
        guard !isStarted, !hasTerminated else { return }
        isStarted = true
        let brightness = model.brightness
        lastPosition = brightness.position
        brightness.changeHandler = { [weak self] position, source in
            self?.positionDidChange(position, source: source)
        }
        brightness.trackingHandler = { [weak self] tracking in
            if !tracking { self?.trackingDidEnd() }
        }
        model.externalBrightness.applyHandler = { [weak self] uuid, level in
            self?.services.externals.setLevel(level, for: uuid)
        }

        let overlay = services.overlay
        overlay.onHeadroom = { [weak self] headroom in self?.send(.headroom(headroom)) }
        overlay.onLost = { [weak self] in self?.overlayLost() }
        let externals = services.externals
        externals.onChange = { [weak self] in self?.syncExternals() }

        let signals = services.signals
        conditions.screenLocked = signals.isScreenLocked
        conditions.lowPowerMode = signals.isLowPowerModeEnabled
        log.info("macOS HDR suppression at start: \(signals.isHDRSuppressed, privacy: .public) (ignored)")
        signals.start { [weak self] signal in self?.handle(signal) }

        // @Published sends the new value before it is stored: use the value.
        model.preferences.$boost
            .removeDuplicates()
            .sink { [weak self] settings in self?.settingsDidChange(settings) }
            .store(in: &subscriptions)
        model.preferences.$shortcuts
            .map(\.toggleBoost)
            .removeDuplicates()
            .sink { [weak self] key in self?.registerToggleKey(key) }
            .store(in: &subscriptions)
        brightness.$boostAllowed
            .removeDuplicates()
            .sink { [weak self] allowed in self?.boostAllowedDidChange(allowed) }
            .store(in: &subscriptions)
        // The panel or Settings › Brightness changed the ceiling (SystemController
        // applies it after the `$boost` sink above has run): the factor follows.
        brightness.$scale
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] scale in self?.scaleDidChange(scale) }
            .store(in: &subscriptions)

        pushConditions()
        requestFactor(for: brightness.position)
        updateKeyTap()
    }

    /// Registers the Boost key (when set). Re-registered when shortcuts change.
    func bindHotKeys(_ center: HotKeyCenter) {
        hotKeys = center
        registerToggleKey(model.preferences.shortcuts.toggleBoost)
    }

    /// Quit or a signal: the overlay, shades and key tap go now. Idempotent.
    func terminate() {
        guard !hasTerminated else { return }
        send(.teardown)
        hasTerminated = true
        services.overlay.hide(rampSeconds: 0)
        services.externals.removeAllShades()
        services.keys.stop()
        isKeyTapRunning = false
        services.signals.stop()
        hotKeys?.unregister(.toggleBoost)
        stopTicking()
        settleTimer?.invalidate()
        settleTimer = nil
        keyFollowTimer?.invalidate()
        keyFollowTimer = nil
        cancelPendingLoss()
        services.writer.cancelPending()
        subscriptions.removeAll()
        model.brightness.changeHandler = nil
        model.brightness.trackingHandler = nil
        model.externalBrightness.applyHandler = nil
    }

    /// Our own write, seen again in DisplayServices' change notification.
    func isEchoOfOwnWrite(_ level: Double) -> Bool {
        services.writer.isEcho(level)
    }

    /// Starts or stops the brightness-key tap after Input Monitoring changed
    /// (Phase 5's Settings asks for it; this never does).
    /// Also runs after every display refresh, so a grant made in System
    /// Settings is picked up without a relaunch.
    ///
    /// - Parameters: `scale`, `boostAllowed`: The store's new value while it is
    ///   being set (`@Published` reports it before storing it).
    func updateKeyTap(scale: BrightnessScale? = nil, boostAllowed: Bool? = nil) {
        guard !hasTerminated else { return }
        let brightness = model.brightness
        let canBoost = (scale ?? brightness.scale).allowingBoost(boostAllowed ?? brightness.boostAllowed).canBoost
        let wanted = settings.keysIntoBoost && settings.allowed && canBoost
        if wanted, !isKeyTapRunning, services.keys.permission == .granted {
            isKeyTapRunning = services.keys.start { [weak self] key in self?.brightnessKey(key) }
            if !isKeyTapRunning { log.notice("The brightness-key tap didn't start") }
        } else if !wanted, isKeyTapRunning {
            services.keys.stop()
            isKeyTapRunning = false
        }
    }

    /// True while the brightness-key tap runs.
    private(set) var isKeyTapRunning = false

    // MARK: Readings from SystemController

    /// Lid, power or heat changed.
    func systemDidChange(lid: LidState, power: PowerSource, thermal: ThermalLevel) {
        guard !hasTerminated else { return }
        conditions.lid = lid
        conditions.power = power
        conditions.thermal = thermal
        pushConditions()
    }

    /// After every display refresh.
    func displaysDidChange(_ inventory: DisplayInventory) {
        guard !hasTerminated else { return }
        builtInID = inventory.builtInOnline ? inventory.builtIn?.displayID : nil
        // A mirrored built-in suspends Boost (the multiply would reach the other
        // screen, and the overlay refuses it): a condition, never a strike.
        let mirrored = builtInID != nil && (inventory.builtIn?.role == .mirrored || builtInID.map(isInMirrorSet) == true)
        if mirrored != builtInMirrored {
            builtInMirrored = mirrored
            log.info("The built-in screen \(mirrored ? "is mirrored: Boost waits" : "is no longer mirrored", privacy: .public)")
        }
        conditions.builtInOnline = builtInID != nil && !mirrored
        presetLocksBrightness = inventory.builtInPresetLocksBrightness
        conditions.panelSupportsBoost = inventory.builtIn?.supportsBoost == true && !inventory.builtInPresetLocksBrightness
        pushConditions()
        updateKeyTap()
        // The built-in too: the controller never dims it, but a mirror set
        // that includes it must not get a shade.
        let online = (inventory.builtInOnline ? inventory.builtIn.map { [$0] } ?? [] : []) + inventory.externals
        if online != knownDisplays {
            knownDisplays = online
            knownExternals = inventory.externals
            services.externals.update(displays: online)
            syncExternals()
        }
    }

    func handle(_ event: SystemEvent) {
        guard !hasTerminated else { return }
        switch event {
        case .willSleep:
            systemSleeping = true
            setExternalPause(.sleep, true)
        case .screensDidSleep:
            screensAsleep = true
        case .didWake:
            systemSleeping = false
            wakeUp()
            setExternalPause(.sleep, false, resumeAfter: Self.externalsWakeDelay)
        case .screensDidWake:
            screensAsleep = false
            wakeUp()
        case .sessionDidResignActive:
            conditions.sessionActive = false
        case .sessionDidBecomeActive:
            conditions.sessionActive = true
        case .lid, .power, .thermal, .willPowerOff:
            // Readings arrive through `systemDidChange`; power off quits through `terminate`.
            return
        }
        pushConditions()
    }

    // MARK: DeskModeBoostInterlock

    func deskModeDidChange(engaged: Bool, switching: Bool) {
        guard !hasTerminated else { return }
        setExternalPause(.deskMode, switching, resumeAfter: Self.externalsResumeDelay)
        guard engaged != conditions.deskModeEngaged else { return }
        conditions.deskModeEngaged = engaged
        pushConditions()
    }

    /// The panic key: the overlay goes at once, the slider leaves Boost and
    /// every shade is removed.
    func panic() {
        guard !hasTerminated else { return }
        log.notice("Panic key: Boost and shades off")
        send(.teardown)
        // A fade the machine already let go of ends now too.
        if services.overlay.isShown { services.overlay.hide(rampSeconds: 0) }
        if model.brightness.isBoosted { model.brightness.leaveBoost() }
        services.externals.removeAllShades()
    }

    // MARK: User actions

    /// The Boost key: boosted → 100 %; otherwise back to the last boosted
    /// position this session, or the ceiling.
    func toggle() {
        guard !hasTerminated else { return }
        let store = model.brightness
        let scale = store.effectiveScale
        guard scale.canBoost else { return }
        if store.isBoosted {
            store.leaveBoost()
        } else {
            store.position = lastBoostedPosition ?? scale.travel.upperBound
        }
    }

    private func brightnessKey(_ key: BrightnessKeyPolicy.Key) {
        // With the built-in off, switching or shut, macOS changes nothing and
        // there is no level to read: a key must not walk the slider into Boost
        // for an overlay that would come up after the panel returns.
        guard !hasTerminated, builtInID != nil, !conditions.deskModeEngaged, conditions.lid != .closed else { return }
        let store = model.brightness
        let scale = store.effectiveScale
        let native = readBrightness?()?.level ?? scale.nativeLevel(store.position)
        if let position = BrightnessKeyPolicy.position(
            after: key, current: store.position, nativeLevel: native, scale: scale, keysIntoBoost: settings.keysIntoBoost
        ) {
            store.position = position
        } else {
            // macOS moves the native level itself; follow it once it has.
            scheduleKeyFollow()
        }
    }

    private func scheduleKeyFollow() {
        keyFollowTimer?.invalidate()
        let timer = Timer(timeInterval: Self.keyFollowDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyFollowFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        keyFollowTimer = timer
    }

    /// True while a key press waits to be followed.
    var isFollowingKey: Bool { keyFollowTimer != nil }

    /// Follows the level macOS set for a key; the timer calls it, tests call it.
    func keyFollowFired() {
        keyFollowTimer?.invalidate()
        keyFollowTimer = nil
        guard !hasTerminated, let reading = readBrightness?() else { return }
        // A key press is the user's own change: follow it at once, even inside
        // the hold after the Boost key (brightness-down leaves Boost).
        model.brightness.applyRead(reading, policy: BrightnessSyncPolicy(userHold: 0))
    }

    /// The overlay removed itself. While displays change (or Desk Mode, sleep
    /// or the lock hold Boost) that is expected and already a block, so it is
    /// not a strike: three strikes would make Boost unavailable.
    ///
    /// The window can leave its screen a moment before the reconfiguration
    /// signal arrives, so an unexpected loss waits `lossGrace` and is dropped
    /// if a reconfiguration begins (or another block arrives) meanwhile.
    func overlayLost() {
        guard !hasTerminated else { return }
        if isLossExpected {
            log.info("The Boost overlay left its screen during a display change")
            return
        }
        guard lossTimer == nil else { return }
        let timer = Timer(timeInterval: Self.lossGrace, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.lossTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        lossTimer = timer
    }

    /// True while a lost overlay waits out `lossGrace`.
    var isLossPending: Bool { lossTimer != nil }

    /// The grace after a loss ended; the timer calls it, tests call it.
    func lossTimerFired() {
        guard lossTimer != nil else { return }
        cancelPendingLoss()
        guard !hasTerminated else { return }
        if isLossExpected {
            log.info("The Boost overlay left its screen during a display change")
        } else {
            log.notice("The Boost overlay lost the built-in screen")
            send(.engineFailed)
        }
    }

    private var isLossExpected: Bool {
        reconfigurationInProgress || suspendedUntil != nil || conditions.deskModeEngaged
            || !conditions.builtInOnline || conditions.lid == .closed || conditions.screensAsleep
            || systemSleeping || screensAsleep || conditions.screenLocked || !conditions.sessionActive
    }

    private func cancelPendingLoss() {
        lossTimer?.invalidate()
        lossTimer = nil
    }

    // MARK: Slider

    private func positionDidChange(_ position: Double, source: BrightnessStore.ChangeSource) {
        let previous = lastPosition
        lastPosition = position
        let scale = model.brightness.effectiveScale
        let limit = BrightnessScale.normalLimit
        // macOS's own level: a level held back earlier is out of date.
        if source == .read { skippedNativeLevel = nil }
        // Native brightness only for the normal part; a move within Boost keeps it at full.
        if source == .user, !(previous >= limit && position >= limit) {
            writeNative(scale.nativeLevel(position))
        }
        requestFactor(for: position)
    }

    /// The slider was released: where it stopped is the position the Boost key returns to.
    private func trackingDidEnd() {
        guard !hasTerminated else { return }
        let store = model.brightness
        let scale = store.effectiveScale
        if scale.isBoosted(store.position) { lastBoostedPosition = scale.clamp(store.position) }
    }

    /// - Parameter scale: The effective scale, when it is being set (`@Published`
    ///   reports it before storing it); the store's otherwise.
    private func requestFactor(for position: Double, scale: BrightnessScale? = nil) {
        let store = model.brightness
        let scale = scale ?? store.effectiveScale
        let factor = scale.boostFactor(position)
        // A drag passes through every position on its way: only its end counts.
        if factor > 1, !store.isTracking { lastBoostedPosition = scale.clamp(position) }
        let boosted = factor > 1
        let wasBoosted = machineRequested > 1
        machineRequested = factor
        send(.request(factor: factor))
        if boosted != wasBoosted { boostedDidChange?(boosted) }
    }

    /// The factor last sent with `.request`.
    private var machineRequested = 1.0

    private func writeNative(_ level: Double) {
        // BezelServices owns the level in a reference preset: nothing to keep.
        guard !presetLocksBrightness else {
            skippedNativeLevel = nil
            return
        }
        guard let builtInID, !nativeWritesBlocked else {
            skippedNativeLevel = level
            return
        }
        skippedNativeLevel = nil
        services.writer.setLevel(level, of: builtInID)
    }

    /// Guards from research §2.3: no native write while the built-in is off,
    /// switching or shut, during a reconfiguration, or while the Mac sleeps.
    private var nativeWritesBlocked: Bool {
        builtInID == nil || conditions.deskModeEngaged || conditions.lid == .closed
            || reconfigurationInProgress || systemSleeping
    }

    /// When the guards close, a coalesced write still waiting is dropped; when
    /// they open, the level the user chose meanwhile is written.
    private func updateNativeGate() {
        let blocked = nativeWritesBlocked
        defer { nativeWritesWereBlocked = blocked }
        if blocked {
            if nativeWritesWereBlocked != true { services.writer.cancelPending() }
        } else if nativeWritesWereBlocked == true, let level = skippedNativeLevel {
            skippedNativeLevel = nil
            if !presetLocksBrightness, let builtInID { services.writer.setLevel(level, of: builtInID) }
        }
    }

    private func boostAllowedDidChange(_ allowed: Bool) {
        // Without a Boost range the slider ends at 100.
        if !allowed, model.brightness.position > BrightnessScale.normalLimit {
            model.brightness.leaveBoost()
        } else {
            requestFactor(for: model.brightness.position, scale: model.brightness.scale.allowingBoost(allowed))
        }
        updateKeyTap(boostAllowed: allowed)
    }

    /// The ceiling or the panel changed. A slider past 100 on a scale that can't
    /// boost any more leaves Boost; otherwise the overlay follows the new factor.
    private func scaleDidChange(_ scale: BrightnessScale) {
        guard !hasTerminated else { return }
        let store = model.brightness
        let effective = scale.allowingBoost(store.boostAllowed)
        if !effective.canBoost, store.position > BrightnessScale.normalLimit {
            // Reaches `requestFactor` with 100, a factor of 1 on any scale.
            store.leaveBoost()
        } else if effective.boostFactor(store.position) != machineRequested {
            requestFactor(for: store.position, scale: effective)
        }
        updateKeyTap(scale: scale)
    }

    // MARK: Conditions

    private func settingsDidChange(_ settings: BoostSettings) {
        self.settings = settings
        pushConditions()
        updateKeyTap()
    }

    private func handle(_ signal: BoostSignal) {
        guard !hasTerminated else { return }
        switch signal {
        case .screenLocked(let locked):
            conditions.screenLocked = locked
        case .lowPowerMode(let on):
            conditions.lowPowerMode = on
        case .hdrSuppressed(let on):
            log.info("macOS HDR suppression \(on ? "began" : "ended", privacy: .public) (ignored)")
            return
        case .reconfigurationBegan:
            // Every display reports a begin; each pushes the limit out.
            reconfigurationInProgress = true
            let deadline = clock() + Self.reconfigurationLimit
            reconfigurationDeadline = max(reconfigurationDeadline ?? deadline, deadline)
            // The overlay may have left its screen just before this arrived.
            cancelPendingLoss()
            setExternalPause(.reconfiguration, true)
            scheduleSettleTimer()
        case .reconfigurationEnded:
            // Every display reports its changes; the settle runs from the last.
            reconfigurationInProgress = false
            reconfigurationDeadline = nil
            suspend(for: Self.settleTime)
            if externalPauses.contains(.reconfiguration) {
                setExternalPause(.reconfiguration, false, resumeAfter: Self.externalsResumeDelay)
            } else if externalPauses.isEmpty {
                // A later display's end: DDC waits a full second after the last one.
                services.externals.resume(after: Self.externalsResumeDelay)
            }
        }
        pushConditions()
    }

    /// After a wake: "Wake at 100 %" first, so the overlay never comes back
    /// boosted for a moment; then a settle before Boost may show again.
    private func wakeUp() {
        if settings.wakeAtNormal, model.brightness.isBoosted {
            log.info("Waking at 100 %")
            model.brightness.leaveBoost()
        }
        suspend(for: Self.settleTime)
    }

    /// Keeps Boost suspended (as `reconfiguring`) for at least `seconds` from
    /// now. A longer suspension already running is kept.
    private func suspend(for seconds: TimeInterval) {
        let until = clock() + seconds
        suspendedUntil = max(suspendedUntil ?? until, until)
        scheduleSettleTimer()
    }

    /// One timer for the earliest of the settle and the reconfiguration limit.
    private func scheduleSettleTimer() {
        settleTimer?.invalidate()
        settleTimer = nil
        guard !hasTerminated, let due = [suspendedUntil, reconfigurationDeadline].compactMap({ $0 }).min() else { return }
        let timer = Timer(timeInterval: max(0, due - clock()), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settleTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    /// A settle or the reconfiguration limit came; the timer calls it, tests
    /// call it after moving their clock. Each ends only at its own time.
    func settleTimerFired() {
        settleTimer = nil
        guard !hasTerminated else { return }
        let now = clock()
        if let until = suspendedUntil, now >= until - 0.01 {
            suspendedUntil = nil
        }
        if reconfigurationInProgress, let deadline = reconfigurationDeadline, now >= deadline - 0.01 {
            // An end pass that never came blocks nothing for good.
            log.notice("A display reconfiguration never reported its end")
            reconfigurationInProgress = false
            reconfigurationDeadline = nil
            setExternalPause(.reconfiguration, false, resumeAfter: Self.externalsResumeDelay)
        }
        scheduleSettleTimer()
        pushConditions()
    }

    /// True while Boost waits out a reconfiguration or a wake.
    var isSettling: Bool { suspendedUntil != nil || reconfigurationInProgress }

    private func pushConditions() {
        guard !hasTerminated else { return }
        updateNativeGate()
        conditions.screensAsleep = screensAsleep || systemSleeping
        conditions.reconfiguring = reconfigurationInProgress || suspendedUntil != nil
        if let sent = sentConditions, sent.0 == conditions, sent.1 == settings {
            hideFadeIfBlocked()
            return
        }
        sentConditions = (conditions, settings)
        send(.conditions(conditions, settings))
    }

    // MARK: External brightness

    private func setExternalPause(_ reason: ExternalPause, _ on: Bool, resumeAfter delay: TimeInterval = 0) {
        let wasPaused = !externalPauses.isEmpty
        if on { externalPauses.insert(reason) } else { externalPauses.remove(reason) }
        let paused = !externalPauses.isEmpty
        guard paused != wasPaused else { return }
        if paused {
            services.externals.pause()
        } else {
            services.externals.resume(after: delay)
        }
    }

    /// Levels and methods the controller knows, into the popover's store.
    private func syncExternals() {
        let store = model.externalBrightness
        for display in knownExternals {
            store.applyRead(
                level: services.externals.level(for: display.id),
                method: services.externals.method(for: display.id),
                for: display.id
            )
        }
        store.retain(only: Set(knownExternals.map(\.id)))
    }

    // MARK: Machine

    private func send(_ event: BoostEvent) {
        guard !hasTerminated else { return }
        pending.append(event)
        guard !isProcessing else { return }
        isProcessing = true
        while !pending.isEmpty {
            let event = pending.removeFirst()
            let before = machine.status
            let commands = machine.handle(event, now: clock())
            if machine.status != before {
                log.info("\(Self.describe(before), privacy: .public) → \(Self.describe(self.machine.status), privacy: .public)")
            }
            for command in commands { run(command) }
        }
        isProcessing = false
        hideFadeIfBlocked()
        updateTicking()
    }

    /// A hide that ramps leaves the window up for a moment, and the machine
    /// already counts it as gone: a block that arrives meanwhile (Desk Mode,
    /// a reconfiguration, sleep) must not wait for the fade.
    private func hideFadeIfBlocked() {
        guard services.overlay.isShown, BoostGuard.block(conditions, settings: settings) != nil else { return }
        services.overlay.hide(rampSeconds: 0)
    }

    private func run(_ command: BoostCommand) {
        switch command {
        case let .show(factor, rampSeconds):
            guard let builtInID, conditions.builtInOnline else {
                pending.append(.engineFailed)
                return
            }
            if !services.overlay.show(on: builtInID, factor: factor, rampSeconds: rampSeconds) {
                log.error("Couldn't put the Boost overlay up")
                pending.append(.engineFailed)
            }
        case let .hide(rampSeconds):
            services.overlay.hide(rampSeconds: rampSeconds)
        case let .notifyPaused(block):
            services.notifier.boostPaused(hot: block == .hot)
        case let .publish(status):
            model.boostStatus.update(status)
        }
    }

    // MARK: Ticks

    /// True while the 0.25 s tick runs.
    var isTicking: Bool { tickTimer != nil }

    /// One tick; the timer calls it, tests call it directly.
    func tick() {
        send(.tick)
    }

    /// Ticks only matter while the machine says so (engaging, backing off, a
    /// coalesced show or a hold waiting): otherwise Boost waits for an event
    /// instead of waking 4 times a second.
    private func updateTicking() {
        if machine.needsTicks, !hasTerminated {
            guard tickTimer == nil else { return }
            let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = Self.tickInterval / 5
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

    // MARK: Keys

    private func registerToggleKey(_ key: KeyShortcut?) {
        guard let hotKeys, !hasTerminated else { return }
        guard let key else {
            hotKeys.unregister(.toggleBoost)
            return
        }
        let result = hotKeys.register(key, for: .toggleBoost, handler: { [weak self] in self?.toggle() })
        if case .failed(let status) = result {
            log.error("Couldn't register the Boost key: \(status, privacy: .public)")
        }
    }

    // MARK: Logging

    private static func describe(_ status: BoostStatus) -> String {
        switch status {
        case .off: "off"
        case .engaging: "engaging"
        case .on(let factor): "on(\(String(format: "%.2f", factor)))"
        case .blocked(let block): "blocked(\(block))"
        case .unavailable: "unavailable"
        }
    }
}

// MARK: - Live signals

/// Lock, Low Power Mode, HDR suppression and display reconfiguration, each
/// delivered on the main actor.
///
/// Swift 6: the Low Power Mode notification is posted on whatever thread
/// changed the state, and the CG callback can run off main inside a
/// configuration transaction, so every observer runs on the main queue
/// (`queue: .main`) or hops there before touching anything.
final class BoostSignalMonitor: BoostSignalSource {
    private nonisolated struct Observation {
        let center: NotificationCenter
        let token: any NSObjectProtocol
    }

    /// The callback's `userInfo`, retained once and never released: a
    /// callback already running on another thread when the monitor stops or
    /// goes away still finds it alive. One small object per monitor.
    nonisolated(unsafe) private let boxPointer = Unmanaged.passRetained(ReconfigurationBox()).toOpaque()
    private var box: ReconfigurationBox { Unmanaged<ReconfigurationBox>.fromOpaque(boxPointer).takeUnretainedValue() }
    // deinit reads these; they're otherwise touched on the main actor only.
    nonisolated(unsafe) private var observations: [Observation] = []
    nonisolated(unsafe) private var callbackRegistered = false
    private var isStarted = false

    deinit {
        if callbackRegistered {
            CGDisplayRemoveReconfigurationCallback(boostReconfigured, boxPointer)
        }
        for observation in observations { observation.center.removeObserver(observation.token) }
    }

    var isScreenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    var isLowPowerModeEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var isHDRSuppressed: Bool {
        if #available(macOS 26.0, *) {
            return NSApplication.shared.applicationShouldSuppressHighDynamicRangeContent
        }
        return false
    }

    func start(handler: @escaping @MainActor (BoostSignal) -> Void) {
        guard !isStarted else { return }
        isStarted = true

        let distributed = DistributedNotificationCenter.default()
        observe(Notification.Name("com.apple.screenIsLocked"), on: distributed) { handler(.screenLocked(true)) }
        observe(Notification.Name("com.apple.screenIsUnlocked"), on: distributed) { handler(.screenLocked(false)) }

        // Foundation posts this only to processes that have read the state.
        _ = ProcessInfo.processInfo.isLowPowerModeEnabled
        observe(.NSProcessInfoPowerStateDidChange, on: .default) {
            handler(.lowPowerMode(ProcessInfo.processInfo.isLowPowerModeEnabled))
        }

        if #available(macOS 26.0, *) {
            observe(.NSApplicationShouldBeginSuppressingHighDynamicRangeContent, on: .default) {
                handler(.hdrSuppressed(true))
            }
            observe(.NSApplicationShouldEndSuppressingHighDynamicRangeContent, on: .default) {
                handler(.hdrSuppressed(false))
            }
        }

        box.handler = handler
        callbackRegistered = CGDisplayRegisterReconfigurationCallback(boostReconfigured, boxPointer) == .success
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        if callbackRegistered {
            CGDisplayRemoveReconfigurationCallback(boostReconfigured, boxPointer)
            callbackRegistered = false
        }
        box.handler = nil
        for observation in observations { observation.center.removeObserver(observation.token) }
        observations = []
    }

    /// The block runs on the main queue whichever thread posts.
    private func observe(_ name: Notification.Name, on center: NotificationCenter, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observations.append(Observation(center: center, token: token))
    }
}

/// Carries the monitor's handler through the C callback's `userInfo`. Written
/// and called on the main thread only.
private nonisolated final class ReconfigurationBox: @unchecked Sendable {
    var handler: (@MainActor (BoostSignal) -> Void)?
}

/// Captures nothing, as a C callback must. On the main thread (another
/// process's change) the begin pass removes the overlay before the change is
/// applied; off main (inside a transaction this app runs) it hops.
private nonisolated func boostReconfigured(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let box = Unmanaged<ReconfigurationBox>.fromOpaque(userInfo).takeUnretainedValue()
    let signal: BoostSignal = flags.contains(.beginConfigurationFlag) ? .reconfigurationBegan : .reconfigurationEnded
    if Thread.isMainThread {
        MainActor.assumeIsolated { box.handler?(signal) }
    } else {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { box.handler?(signal) }
        }
    }
}
