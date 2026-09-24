import Foundation
import LidlessCore

// Installing the bridge: the app delegate adds this one line to
// `applicationDidFinishLaunching`, after `startLive()` (so the controllers
// exist) and only when the UI starts (not in tests, previews or safe mode):
//
//     AppIntentBridge.shared = AppIntentBridge(model: model, deskMode: deskModeController, boost: boostController)
//
// It needs no `#available`: the bridge is plain Swift and builds for macOS 12.
// Only the intents (`DeskModeIntents.swift`, `BoostIntents.swift`) and the
// App Shortcuts (`LidlessShortcuts.swift`) are macOS 13+.

/// The Desk Mode controller's paths an intent needs. `DeskModeController` in
/// a normal launch.
protocol DeskModePanicking: AnyObject {
    /// The panic key.
    func panic()
    /// Turns Desk Mode on like the popover switch. `forcePrompt`: the
    /// keep-or-revert prompt shows even with "Ask before keeping it off"
    /// switched off.
    func requestTurnOn(forcePrompt: Bool)
}

/// The Boost key's toggle: boosted → 100 %, otherwise back to the last boosted
/// position or the ceiling. `BoostController` in a normal launch.
protocol BoostToggling: AnyObject {
    func toggle()
}

extension DeskModeController: DeskModePanicking {}
extension BoostController: BoostToggling {}

/// What a Desk Mode intent did, for its dialog.
nonisolated enum DeskModeIntentOutcome: Sendable, Equatable {
    /// The built-in screen is off. `asksToKeep`: the keep-or-revert prompt is up.
    case turnedOn(asksToKeep: Bool)
    /// The built-in screen is back on.
    case turnedOff
    case alreadyOn
    case alreadyOff
    /// Still switching when the intent stopped waiting.
    case stillSwitching(toOn: Bool)
    case unavailable(DeskModeState.UnavailableReason)
    /// Desk Mode refused or the screen didn't switch off (the reason is in the log).
    case couldNotTurnOn
    /// Asked to turn on while the built-in screen is on its way back.
    case busy
}

/// What the Set Brightness Boost intent did, for its dialog.
nonisolated enum BoostIntentOutcome: Sendable, Equatable {
    case turnedOn
    case alreadyOn
    /// Boost is set, but a guard rail holds it back until it clears.
    case paused(BoostBlock)
    /// Boost is set, but macOS gave the screen no extra brightness.
    case systemRefused
    case turnedOff
    case alreadyOff
    /// "Boost allowed" is off in Settings › Brightness.
    case notAllowed
    /// The built-in screen has no extra brightness to give.
    case unsupported
}

/// How App Intents reach the app. Intents run in this process with no UI; each
/// `perform()` hops to the main actor and calls one of these, which take the
/// same paths as the popover and the global keys, so every guard still applies.
@MainActor
final class AppIntentBridge {
    /// Set once by the app delegate (see the top of this file). Nil in tests,
    /// previews and safe mode, where intents report that Lidless isn't ready.
    static var shared: AppIntentBridge?

    struct Timing: Sendable {
        /// How long an intent waits for the built-in screen to finish switching.
        /// A display transaction can block for most of 30 s; past this the
        /// intent says it is still switching.
        var deskModeSettle: TimeInterval = 15
        /// How long Set Brightness Boost waits for macOS to give headroom.
        var boostSettle: TimeInterval = 2
        var pollInterval: TimeInterval = 0.1
    }

    private let model: AppModel
    private weak var deskMode: (any DeskModePanicking)?
    private weak var boost: (any BoostToggling)?
    private let timing: Timing

    /// - Parameters:
    ///   - deskMode: The panic path; nil in sample launches, where the stores
    ///     change directly.
    ///   - boost: The Boost key's toggle; nil in sample launches.
    init(model: AppModel, deskMode: (any DeskModePanicking)?, boost: (any BoostToggling)?, timing: Timing = .init()) {
        self.model = model
        self.deskMode = deskMode
        self.boost = boost
        self.timing = timing
    }

    /// The installed bridge. An intent can launch the app, and `perform()` may
    /// start before the app delegate has installed it: wait up to `timeout`.
    /// - Parameter lookup: Where the bridge is installed; `shared` unless a
    ///   test passes its own, so tests never race on the global.
    static func current(
        waitingUpTo timeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.1,
        lookup: () -> AppIntentBridge? = { AppIntentBridge.shared }
    ) async -> AppIntentBridge? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while lookup() == nil, ProcessInfo.processInfo.systemUptime < deadline {
            guard await pause(pollInterval) else { break }
        }
        return lookup()
    }

    // MARK: Desk Mode

    /// Turn Desk Mode On / Off: the popover switch's path (`DeskModeStore.setOn`),
    /// then waits for the built-in screen to finish switching. Until onboarding
    /// is done, turning on always asks before keeping the screen off: a
    /// shortcut run before the user has seen the panic key still gets the
    /// safety net's prompt.
    func turnDeskMode(on: Bool) async -> DeskModeIntentOutcome {
        let store = model.deskMode
        switch store.state {
        case .unavailable(let reason):
            return on ? .unavailable(reason) : .alreadyOff
        case .switching(let toOn) where toOn == on:
            // Already on its way: report where it lands.
            return await settle(requested: on)
        case .switching(toOn: false):
            // The machine refuses an engage while it restores.
            return .busy
        case .on where on:
            return .alreadyOn
        case .off where !on:
            return .alreadyOff
        case .off, .on, .switching:
            if on, !model.preferences.general.onboardingCompleted, let deskMode {
                deskMode.requestTurnOn(forcePrompt: true)
            } else {
                // Sample launches have no controller: the store changes directly.
                store.setOn(on)
            }
            return await settle(requested: on)
        }
    }

    /// Toggle Desk Mode: the Desk Mode key's behaviour.
    func toggleDeskMode() async -> DeskModeIntentOutcome {
        await turnDeskMode(on: !model.deskMode.state.isOn)
    }

    /// Turn the Built-in Screen Back On: exactly what the panic key does (it
    /// also ends Boost and removes shades). Never refused.
    func panic() async -> DeskModeIntentOutcome {
        let store = model.deskMode
        let wasOn = store.state.isOn || store.state.isSwitching
        if let deskMode {
            deskMode.panic()
        } else {
            // A sample launch: no controller, so the stores change directly.
            store.setOn(false)
            if model.brightness.isBoosted { model.brightness.leaveBoost() }
        }
        guard wasOn else { return .alreadyOff }
        return await settle(requested: false)
    }

    /// Get Desk Mode State.
    func deskModeState() -> DeskModeState {
        model.deskMode.state
    }

    /// Waits while the built-in screen switches, then says where it landed.
    private func settle(requested on: Bool) async -> DeskModeIntentOutcome {
        let store = model.deskMode
        await wait(upTo: timing.deskModeSettle) { !store.state.isSwitching }
        switch store.state {
        case .switching(let toOn):
            return .stillSwitching(toOn: toOn)
        case .on:
            // What the machine does, not the preference: a forced prompt asks
            // too, and a prompt already answered doesn't.
            return on ? .turnedOn(asksToKeep: store.isConfirming) : .stillSwitching(toOn: false)
        case .off:
            return on ? .couldNotTurnOn : .turnedOff
        case .unavailable(let reason):
            return on ? .unavailable(reason) : .turnedOff
        }
    }

    // MARK: Boost

    /// Set Brightness Boost. On: the Boost key's path (back to the last boosted
    /// position this session, or the ceiling). Off: "Back to 100%".
    func setBoost(on: Bool) async -> BoostIntentOutcome {
        let brightness = model.brightness
        guard on else {
            guard brightness.isBoosted else { return .alreadyOff }
            brightness.leaveBoost()
            return .turnedOff
        }
        guard brightness.boostAllowed else { return .notAllowed }
        guard brightness.scale.canBoost else { return .unsupported }
        let wasBoosted = brightness.isBoosted
        if !wasBoosted {
            if let boost {
                boost.toggle()
            } else {
                brightness.position = brightness.effectiveScale.travel.upperBound
            }
            // The controller refuses once it has terminated (the app is quitting).
            guard brightness.isBoosted else { return .unsupported }
        }
        let status = model.boostStatus
        await wait(upTo: timing.boostSettle) { status.status != .engaging }
        switch status.status {
        case .blocked(.notAllowed): return .notAllowed
        case .blocked(.unsupported): return .unsupported
        case .blocked(let block): return .paused(block)
        case .unavailable: return .systemRefused
        case .off, .engaging, .on: return wasBoosted ? .alreadyOn : .turnedOn
        }
    }

    // MARK: Waiting

    /// Polls `done` until it holds, `seconds` pass or the intent is cancelled.
    private func wait(upTo seconds: TimeInterval, until done: () -> Bool) async {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !done(), ProcessInfo.processInfo.systemUptime < deadline {
            guard await Self.pause(timing.pollInterval) else { return }
        }
    }

    /// Sleeps; false when the task was cancelled.
    private static func pause(_ seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0.001) * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }
}
