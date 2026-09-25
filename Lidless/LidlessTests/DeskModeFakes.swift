import CoreGraphics
import Foundation
import LidlessCore
@testable import Lidless

// Fakes for the seams in DeskMode/DeskModeServices.swift. Every call lands in
// one shared log, so tests can check the order across services. Nothing here
// touches a display.

/// What the controller asked the services to do, in order.
@MainActor
final class DeskModeCallLog {
    enum Call: Equatable {
        case disable(UInt32, uuid: String?, method: DeskModeMethod)
        case enable(UInt32?)
        case enableNow(UInt32?)
        case arm(UInt32, method: DeskModeMethod)
        case deadline(TimeInterval?)
        case disarm
        case writeMarker(CrashMarker.Stage)
        case clearMarker
        case hold(Bool)
        case show(deadline: TimeInterval, total: TimeInterval, onDisplayUUID: String?)
        case hide
        case notify(DeskModeRestoreReason)
        case recovered
        case hang(Bool)

        /// A call that changes what the built-in screen shows.
        var touchesDisplay: Bool {
            switch self {
            case .disable, .enable, .enableNow: true
            default: false
            }
        }
    }

    private(set) var calls: [Call] = []

    func record(_ call: Call) { calls.append(call) }

    /// The calls so far, then starts afresh.
    func take() -> [Call] {
        defer { calls = [] }
        return calls
    }
}

@MainActor
final class FakeBuiltInSwitch: BuiltInSwitch, DeskModeMethodSelecting {
    var method: DeskModeMethod = .disconnect
    /// What `enableNow` reports: false when the list never showed the panel.
    var enableNowResult = true
    /// Set: disables and enables answer inside the call, as a switch that
    /// fails fast may.
    var answersAtOnce: Bool?
    private let log: DeskModeCallLog
    private var disableCompletions: [@MainActor (Bool) -> Void] = []
    private var enableCompletions: [@MainActor (Bool) -> Void] = []

    init(log: DeskModeCallLog) { self.log = log }

    var pendingDisables: Int { disableCompletions.count }
    var pendingEnables: Int { enableCompletions.count }

    func disable(displayID: CGDirectDisplayID, uuid: String?, completion: @escaping @MainActor (Bool) -> Void) {
        log.record(.disable(displayID, uuid: uuid, method: method))
        if let answersAtOnce { return completion(answersAtOnce) }
        disableCompletions.append(completion)
    }

    func enable(displayID: CGDirectDisplayID?, uuid: String?, completion: @escaping @MainActor (Bool) -> Void) {
        log.record(.enable(displayID))
        if let answersAtOnce { return completion(answersAtOnce) }
        enableCompletions.append(completion)
    }

    func enableNow(displayID: CGDirectDisplayID?, uuid: String?, timeout: TimeInterval) -> Bool {
        log.record(.enableNow(displayID))
        return enableNowResult
    }

    /// Answers the oldest disable, as the real switch does after verifying.
    func finishDisable(_ ok: Bool) {
        guard !disableCompletions.isEmpty else { return }
        disableCompletions.removeFirst()(ok)
    }

    func finishEnable(_ ok: Bool) {
        guard !enableCompletions.isEmpty else { return }
        enableCompletions.removeFirst()(ok)
    }
}

@MainActor
final class FakeConfirmation: ConfirmationPresenter {
    private let log: DeskModeCallLog
    private var keep: (@MainActor () -> Void)?
    private var revert: (@MainActor () -> Void)?

    init(log: DeskModeCallLog) { self.log = log }

    var isShown: Bool { keep != nil }

    func show(deadline: TimeInterval, total: TimeInterval, onDisplayUUID: String?, keep: @escaping @MainActor () -> Void, revert: @escaping @MainActor () -> Void) {
        log.record(.show(deadline: deadline, total: total, onDisplayUUID: onDisplayUUID))
        self.keep = keep
        self.revert = revert
    }

    func hide() {
        log.record(.hide)
        keep = nil
        revert = nil
    }

    /// "Keep Off".
    func pressKeep() { keep?() }
    /// "Turn Back On".
    func pressRevert() { revert?() }
}

@MainActor
final class FakeWatchdogLink: WatchdogLink {
    private let log: DeskModeCallLog
    /// What `arm` reports: false when no sidecar could be started.
    var armResult = true
    init(log: DeskModeCallLog) { self.log = log }

    func arm(displayID: CGDirectDisplayID, method: DeskModeMethod, uuid: String?) -> Bool {
        log.record(.arm(displayID, method: method))
        return armResult
    }
    func setDeadline(_ deadline: TimeInterval?) { log.record(.deadline(deadline)) }
    func disarm() { log.record(.disarm) }
}

@MainActor
final class FakeCrashMarkerStore: CrashMarkerStore {
    private let log: DeskModeCallLog
    /// What the file holds; nil when absent.
    var marker: CrashMarker?
    /// A file that exists but doesn't decode.
    var isDamaged = false
    var currentBootSession: String? = "boot-1"

    init(log: DeskModeCallLog) { self.log = log }

    func write(_ marker: CrashMarker) {
        log.record(.writeMarker(marker.stage))
        self.marker = marker
        isDamaged = false
    }

    func read() -> (marker: CrashMarker?, fileExists: Bool) {
        (isDamaged ? nil : marker, marker != nil || isDamaged)
    }

    func clear() {
        log.record(.clearMarker)
        marker = nil
        isDamaged = false
    }
}

@MainActor
final class FakeNotifier: DeskModeNotifier {
    private let log: DeskModeCallLog
    init(log: DeskModeCallLog) { self.log = log }

    func restored(_ reason: DeskModeRestoreReason) { log.record(.notify(reason)) }
    func recoveredAfterCrash() { log.record(.recovered) }
}

@MainActor
final class FakeActivity: ActivityHolder {
    private let log: DeskModeCallLog
    init(log: DeskModeCallLog) { self.log = log }

    func hold(_ on: Bool) { log.record(.hold(on)) }
}

@MainActor
final class FakeHangWatchdog: HangWatchdogControl {
    private let log: DeskModeCallLog
    private(set) var isArmed = false
    init(log: DeskModeCallLog) { self.log = log }

    func setArmed(_ armed: Bool) {
        isArmed = armed
        log.record(.hang(armed))
    }
}

/// Records when the controller brackets a switch, apart from the call log.
final class FakeModeWatch: DisplayModeWatching {
    enum Call: Equatable { case willSwitch, didSwitch }
    private(set) var calls: [Call] = []

    func willSwitch() { calls.append(.willSwitch) }
    func didSwitch() { calls.append(.didSwitch) }
}

/// A Desk Mode controller wired to fakes and a fake clock, with preferences
/// in a private UserDefaults suite. Call `cleanUp()` when a test changed them.
@MainActor
struct DeskModeRig {
    static let since = Date(timeIntervalSince1970: 1_800_000_000)

    let clock = FakeClock()
    let log = DeskModeCallLog()
    let builtIn: FakeBuiltInSwitch
    let confirmation: FakeConfirmation
    let watchdog: FakeWatchdogLink
    let marker: FakeCrashMarkerStore
    let hang: FakeHangWatchdog
    let modeWatch = FakeModeWatch()
    let suiteName = "DeskModeRig.\(UUID().uuidString)"
    let model: AppModel
    let controller: DeskModeController

    /// - Parameters:
    ///   - settings: Stored in the model's preferences before the controller reads them.
    ///   - model: Shares a model with a `SystemRig` (whose suite then holds
    ///     the settings); a fresh one otherwise.
    init(settings: DeskModeSettings = .defaults, model: AppModel? = nil) {
        builtIn = FakeBuiltInSwitch(log: log)
        confirmation = FakeConfirmation(log: log)
        watchdog = FakeWatchdogLink(log: log)
        marker = FakeCrashMarkerStore(log: log)
        hang = FakeHangWatchdog(log: log)
        self.model = model ?? AppModel(preferences: PreferencesStore(defaults: UserDefaults(suiteName: suiteName)!))
        let preferences = self.model.preferences
        if settings != preferences.deskMode { preferences.deskMode = settings }
        let clock = clock
        controller = DeskModeController(
            model: self.model,
            services: DeskModeController.Services(
                builtIn: builtIn,
                confirmation: confirmation,
                watchdog: watchdog,
                marker: marker,
                notifier: FakeNotifier(log: log),
                activity: FakeActivity(log: log),
                hang: hang,
                modeWatch: modeWatch
            ),
            names: DisplayFixtures.names,
            clock: { clock.now },
            date: { DeskModeRig.since }
        )
        controller.start()
    }

    /// This Mac as it is at the desk: lid open, the LG on HDMI, on power.
    func connect(_ facts: [DisplayFacts] = DisplayFixtures.thisMac) {
        controller.displaysDidChange(facts: facts, lid: .open, power: .adapter)
        controller.availabilityDidChange(nil)
    }

    /// The list once the disconnect took the built-in out of it.
    static let builtInOff = [DisplayFixtures.lg]

    /// Turns Desk Mode on and answers the prompt with "Keep Off": active, log empty.
    func turnOnAndKeep() {
        connect()
        controller.setOn(true)
        builtIn.finishDisable(true)
        controller.displaysDidChange(facts: Self.builtInOff, lid: .open, power: .adapter)
        confirmation.pressKeep()
        _ = log.take()
    }

    func advance(_ seconds: TimeInterval) {
        clock.now += seconds
    }

    func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

/// Carbon's side of `HotKeyCenter`: records what is held, presses by ID.
@MainActor
final class FakeHotKeyRegistrar: HotKeyRegistrar {
    var onPress: (@MainActor (UInt32) -> Bool)?
    /// Key codes held, by hot key ID.
    private(set) var held: [UInt32: UInt32] = [:]

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, exclusive: Bool) -> OSStatus {
        held[id] = keyCode
        return 0
    }

    func unregister(id: UInt32) { held[id] = nil }

    /// What Carbon does on a press: returns whether a handler took it.
    func press(_ id: HotKeyID) -> Bool { onPress?(id.rawValue) ?? false }
}

@MainActor
extension HotKeyCenter {
    /// A center that never touches Carbon or `NSEvent`.
    static func fake(_ registrar: FakeHotKeyRegistrar) -> HotKeyCenter {
        HotKeyCenter(
            registrar: registrar,
            notificationCenter: NotificationCenter(),
            keyDownMonitor: HotKeyCenter.KeyDownMonitor(add: { _ in nil }, remove: { _ in })
        )
    }
}
