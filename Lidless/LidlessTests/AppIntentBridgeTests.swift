import AppIntents
import Foundation
import LidlessCore
import Testing
@testable import Lidless

/// `AppIntentBridge` against real stores and fake controllers: which path each
/// intent takes and what it reports. Nothing here touches a display; the
/// stores stand in for what `DeskModeController` and `BoostController` publish.
/// No test touches the global `AppIntentBridge.shared`, so they run in parallel.
@MainActor
struct AppIntentBridgeTests {
    // MARK: Finding the bridge

    @Test func `an intent waits for a cold launch to install the bridge`() async {
        let slot = BridgeSlot()
        let rig = BridgeRig()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            slot.bridge = rig.bridge
        }
        let found = await AppIntentBridge.current(waitingUpTo: 10, pollInterval: 0.01, lookup: { slot.bridge })
        #expect(found === rig.bridge)
    }

    @Test func `without a bridge an intent gives up after the timeout`() async {
        let slot = BridgeSlot()
        #expect(await AppIntentBridge.current(waitingUpTo: 0.05, pollInterval: 0.01, lookup: { slot.bridge }) == nil)
    }

    // MARK: Desk Mode on and off

    @Test func `turning on takes the popover path and waits for the screen`() async {
        let rig = BridgeRig()
        rig.simulateController(landsOn: { on in on ? .on(since: .now, trigger: .manual) : .off })

        #expect(await rig.bridge.turnDeskMode(on: true) == .turnedOn(asksToKeep: true))
        #expect(rig.requests == [true])
        #expect(rig.panicker.turnOnRequests.isEmpty)
        #expect(rig.model.deskMode.state.isOn)
    }

    @Test func `the reply asks to keep only while the prompt is up`() async {
        // The preference says ask, but the machine shows no prompt (for example
        // a rule it keeps without asking): the reply follows the machine.
        let rig = BridgeRig()
        rig.model.preferences.deskMode.askBeforeKeeping = true
        rig.simulateController(landsOn: { _ in .on(since: .now, trigger: .manual) }, prompts: false)

        #expect(await rig.bridge.turnDeskMode(on: true) == .turnedOn(asksToKeep: false))
    }

    // MARK: Before onboarding

    @Test(arguments: [true, false])
    func `before onboarding, turning on always asks before keeping it off`(askBeforeKeeping: Bool) async {
        let rig = BridgeRig(onboarded: false)
        rig.model.preferences.deskMode.askBeforeKeeping = askBeforeKeeping
        rig.simulateController(landsOn: { on in on ? .on(since: .now, trigger: .manual) : .off }, prompts: false)

        #expect(await rig.bridge.turnDeskMode(on: true) == .turnedOn(asksToKeep: true))
        #expect(rig.panicker.turnOnRequests == [true])
        #expect(rig.requests.isEmpty)
    }

    @Test func `before onboarding, toggling on asks too, and off takes the usual path`() async {
        let rig = BridgeRig(onboarded: false)
        rig.simulateController(landsOn: { on in on ? .on(since: .now, trigger: .manual) : .off }, prompts: false)

        #expect(await rig.bridge.toggleDeskMode() == .turnedOn(asksToKeep: true))
        #expect(await rig.bridge.toggleDeskMode() == .turnedOff)
        #expect(rig.panicker.turnOnRequests == [true])
        #expect(rig.requests == [false])
    }

    @Test func `before onboarding, a sample launch still changes the store directly`() async {
        let rig = BridgeRig(controllers: false, onboarded: false)

        #expect(await rig.bridge.turnDeskMode(on: true) == .turnedOn(asksToKeep: false))
        #expect(rig.panicker.turnOnRequests.isEmpty)
    }

    // MARK: Switching

    @Test func `turning off brings the screen back`() async {
        let rig = BridgeRig(state: .on(since: .now, trigger: .manual))
        rig.simulateController(landsOn: { _ in .off })

        #expect(await rig.bridge.turnDeskMode(on: false) == .turnedOff)
        #expect(rig.requests == [false])
    }

    @Test func `a refused turn-on says so`() async {
        let rig = BridgeRig()
        // The machine refused (not ready, latched): nothing changes.
        rig.model.deskMode.requestHandler = { on in rig.requests.append(on) }

        #expect(await rig.bridge.turnDeskMode(on: true) == .couldNotTurnOn)
    }

    @Test func `a disable that fails and restores reads as couldn't turn on`() async {
        let rig = BridgeRig()
        rig.simulateController(landsOn: { _ in .off })

        #expect(await rig.bridge.turnDeskMode(on: true) == .couldNotTurnOn)
    }

    @Test func `a screen still switching after the wait is reported, not hidden`() async {
        let rig = BridgeRig(deskModeSettle: BridgeRig.shortSettle)
        rig.simulateController(landsOn: nil)

        #expect(await rig.bridge.turnDeskMode(on: true) == .stillSwitching(toOn: true))
    }

    @Test func `unavailable Desk Mode gives the reason and asks nothing`() async {
        let rig = BridgeRig(state: .unavailable(.needsDisplay))
        rig.model.deskMode.requestHandler = { on in rig.requests.append(on) }

        #expect(await rig.bridge.turnDeskMode(on: true) == .unavailable(.needsDisplay))
        #expect(await rig.bridge.turnDeskMode(on: false) == .alreadyOff)
        #expect(rig.requests.isEmpty)
    }

    @Test func `already on or off asks nothing`() async {
        let on = BridgeRig(state: .on(since: .now, trigger: .manual))
        on.model.deskMode.requestHandler = { value in on.requests.append(value) }
        #expect(await on.bridge.turnDeskMode(on: true) == .alreadyOn)
        #expect(on.requests.isEmpty)

        let off = BridgeRig()
        off.model.deskMode.requestHandler = { value in off.requests.append(value) }
        #expect(await off.bridge.turnDeskMode(on: false) == .alreadyOff)
        #expect(off.requests.isEmpty)
    }

    @Test func `turning on while the screen comes back is busy`() async {
        let rig = BridgeRig(state: .switching(toOn: false))
        rig.model.deskMode.requestHandler = { on in rig.requests.append(on) }

        #expect(await rig.bridge.turnDeskMode(on: true) == .busy)
        #expect(rig.requests.isEmpty)
    }

    @Test func `turning off while switching on ends it`() async {
        let rig = BridgeRig(state: .switching(toOn: true))
        rig.simulateController(landsOn: { _ in .off })

        #expect(await rig.bridge.turnDeskMode(on: false) == .turnedOff)
        #expect(rig.requests == [false])
    }

    @Test func `a request already on its way waits for it instead of asking again`() async {
        let rig = BridgeRig(state: .switching(toOn: true))
        rig.model.deskMode.requestHandler = { on in rig.requests.append(on) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            rig.model.deskMode.setConfirming(true)
            rig.model.deskMode.update(.on(since: .now, trigger: .manual))
        }

        #expect(await rig.bridge.turnDeskMode(on: true) == .turnedOn(asksToKeep: true))
        #expect(rig.requests.isEmpty)
    }

    @Test func `toggle follows the current state`() async {
        let rig = BridgeRig()
        rig.simulateController(landsOn: { on in on ? .on(since: .now, trigger: .manual) : .off })

        #expect(await rig.bridge.toggleDeskMode() == .turnedOn(asksToKeep: true))
        #expect(await rig.bridge.toggleDeskMode() == .turnedOff)
        #expect(rig.requests == [true, false])
    }

    @Test func `sample launches change the store directly`() async {
        // No controller, so no prompt: nothing asks to keep.
        let rig = BridgeRig()
        #expect(await rig.bridge.turnDeskMode(on: true) == .turnedOn(asksToKeep: false))
        #expect(await rig.bridge.turnDeskMode(on: false) == .turnedOff)
    }

    @Test func `the state intent reads the store`() {
        let rig = BridgeRig(state: .unavailable(.lidClosed))
        #expect(rig.bridge.deskModeState() == .unavailable(.lidClosed))
    }

    // MARK: Panic

    @Test func `panic takes the panic key's path and waits for the screen`() async {
        let rig = BridgeRig(state: .on(since: .now, trigger: .manual))
        rig.panicker.onPanic = { rig.model.deskMode.update(.switching(toOn: false)) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            rig.model.deskMode.update(.off)
        }

        #expect(await rig.bridge.panic() == .turnedOff)
        #expect(rig.panicker.panics == 1)
    }

    @Test(arguments: [DeskModeState.off, .unavailable(.lidClosed), .unavailable(.needsDisplay)])
    func `panic is never refused, even with nothing to restore`(state: DeskModeState) async {
        let rig = BridgeRig(state: state)
        #expect(await rig.bridge.panic() == .alreadyOff)
        #expect(rig.panicker.panics == 1)
    }

    @Test func `panic reports a screen that hasn't come back yet`() async {
        let rig = BridgeRig(state: .on(since: .now, trigger: .manual), deskModeSettle: BridgeRig.shortSettle)
        rig.panicker.onPanic = { rig.model.deskMode.update(.switching(toOn: false)) }

        #expect(await rig.bridge.panic() == .stillSwitching(toOn: false))
    }

    @Test func `panic in a sample launch turns Desk Mode and Boost off`() async {
        let rig = BridgeRig(state: .on(since: .now, trigger: .manual), position: 130, controllers: false)

        #expect(await rig.bridge.panic() == .turnedOff)
        #expect(!rig.model.deskMode.state.isOn)
        #expect(rig.model.brightness.position == BrightnessScale.normalLimit)
    }

    // MARK: Boost

    @Test func `Boost on takes the Boost key's path`() async {
        let rig = BridgeRig(boostStatus: .on(factor: 1.5))
        rig.booster.onToggle = { rig.model.brightness.position = 140 }

        #expect(await rig.bridge.setBoost(on: true) == .turnedOn)
        #expect(rig.booster.toggles == 1)
    }

    @Test func `Boost on when already boosted doesn't toggle it off`() async {
        let rig = BridgeRig(position: 130, boostStatus: .on(factor: 1.4))

        #expect(await rig.bridge.setBoost(on: true) == .alreadyOn)
        #expect(rig.booster.toggles == 0)
        #expect(rig.model.brightness.position == 130)
    }

    @Test func `Boost off goes back to 100`() async {
        let rig = BridgeRig(position: 130)

        #expect(await rig.bridge.setBoost(on: false) == .turnedOff)
        #expect(rig.model.brightness.position == BrightnessScale.normalLimit)
        #expect(await rig.bridge.setBoost(on: false) == .alreadyOff)
        #expect(rig.booster.toggles == 0)
    }

    @Test func `Boost off leaves normal brightness alone`() async {
        let rig = BridgeRig(position: 40)
        #expect(await rig.bridge.setBoost(on: false) == .alreadyOff)
        #expect(rig.model.brightness.position == 40)
    }

    @Test func `Boost not allowed in Settings is refused without moving anything`() async {
        let rig = BridgeRig(position: 60, boostAllowed: false)

        #expect(await rig.bridge.setBoost(on: true) == .notAllowed)
        #expect(rig.booster.toggles == 0)
        #expect(rig.model.brightness.position == 60)
    }

    @Test func `a screen that can't boost is refused`() async {
        let rig = BridgeRig(scale: BrightnessScale(normalMaxNits: 600, ceilingNits: 600))

        #expect(await rig.bridge.setBoost(on: true) == .unsupported)
        #expect(rig.booster.toggles == 0)
    }

    @Test func `a toggle that does nothing is not reported as on`() async {
        let rig = BridgeRig()
        #expect(await rig.bridge.setBoost(on: true) == .unsupported)
        #expect(rig.booster.toggles == 1)
    }

    @Test func `a paused Boost says why`() async {
        let rig = BridgeRig(boostStatus: .blocked(.hot))
        rig.booster.onToggle = { rig.model.brightness.position = 150 }

        #expect(await rig.bridge.setBoost(on: true) == .paused(.hot))
    }

    @Test func `macOS refusing headroom is reported`() async {
        let rig = BridgeRig(position: 130, boostStatus: .unavailable)
        #expect(await rig.bridge.setBoost(on: true) == .systemRefused)
    }

    @Test func `Boost waits for headroom, then reports on either way`() async {
        let rig = BridgeRig(boostStatus: .engaging)
        rig.booster.onToggle = { rig.model.brightness.position = 150 }

        #expect(await rig.bridge.setBoost(on: true) == .turnedOn)
    }

    @Test func `Boost on in a sample launch goes to the ceiling`() async {
        let rig = BridgeRig(controllers: false)

        #expect(await rig.bridge.setBoost(on: true) == .turnedOn)
        #expect(rig.model.brightness.position == rig.model.brightness.effectiveScale.travel.upperBound)
    }

    // MARK: Replies

    @Test func `failed switches throw so a shortcut stops`() throws {
        #expect(throws: LidlessIntentError.self) { try DeskModeIntentOutcome.unavailable(.needsDisplay).switchDialog() }
        #expect(throws: LidlessIntentError.self) { try DeskModeIntentOutcome.couldNotTurnOn.switchDialog() }
        #expect(throws: LidlessIntentError.self) { try DeskModeIntentOutcome.busy.switchDialog() }
        _ = try DeskModeIntentOutcome.turnedOn(asksToKeep: true).switchDialog()
        _ = try DeskModeIntentOutcome.stillSwitching(toOn: false).switchDialog()
    }

    @Test func `refused Boost throws, paused Boost replies`() throws {
        #expect(throws: LidlessIntentError.self) { try BoostIntentOutcome.notAllowed.dialog() }
        #expect(throws: LidlessIntentError.self) { try BoostIntentOutcome.unsupported.dialog() }
        #expect(throws: LidlessIntentError.self) { try BoostIntentOutcome.paused(.notAllowed).dialog() }
        _ = try BoostIntentOutcome.paused(.lowPower).dialog()
        _ = try BoostIntentOutcome.systemRefused.dialog()
    }

    @Test(arguments: [
        LidlessIntentError.notReady, .deskModeUnavailable(.needsDisplay), .deskModeUnavailable(.lidClosed),
        .deskModeUnavailable(.unsupportedMac), .deskModeUnavailable(.unsupportedSystem),
        .deskModeFailed, .deskModeBusy, .boostNotAllowed, .boostUnsupported,
    ])
    func `every error has a message`(error: LidlessIntentError) {
        #expect(!String(localized: error.localizedStringResource).isEmpty)
    }
}

// MARK: - Rig

@MainActor
final class FakePanicker: DeskModePanicking {
    private(set) var panics = 0
    var onPanic: () -> Void = {}
    /// `forcePrompt` of each `requestTurnOn`, in order.
    private(set) var turnOnRequests: [Bool] = []
    var onTurnOn: (_ forcePrompt: Bool) -> Void = { _ in }

    func panic() {
        panics += 1
        onPanic()
    }

    func requestTurnOn(forcePrompt: Bool) {
        turnOnRequests.append(forcePrompt)
        onTurnOn(forcePrompt)
    }
}

/// Where a test installs its bridge, in place of the global `shared`.
@MainActor
final class BridgeSlot {
    var bridge: AppIntentBridge?
}

@MainActor
final class FakeBoostToggle: BoostToggling {
    private(set) var toggles = 0
    var onToggle: () -> Void = {}

    func toggle() {
        toggles += 1
        onToggle()
    }
}

/// A model with real stores and the two fake controllers.
///
/// A switch the fake controller lands ends the bridge's wait at once, so that
/// wait is long: all the app-hosted tests share the main actor, and on a busy
/// CI machine a landing 30 ms away can run well over a second late. Only the
/// tests that expect "still switching" wait out a short one.
@MainActor
final class BridgeRig {
    static let shortSettle: TimeInterval = 0.3

    let model: AppModel
    let panicker = FakePanicker()
    let booster = FakeBoostToggle()
    let bridge: AppIntentBridge
    /// What reached `DeskModeStore.requestHandler`, in order.
    var requests: [Bool] = []
    private let suiteName = "BridgeRig.\(UUID().uuidString)"

    init(
        state: DeskModeState = .off,
        position: Double = 70,
        scale: BrightnessScale = .init(normalMaxNits: 600, ceilingNits: 1000),
        boostAllowed: Bool = true,
        boostStatus: BoostStatus = .off,
        controllers: Bool = true,
        onboarded: Bool = true,
        deskModeSettle: TimeInterval = 10
    ) {
        model = AppModel(
            deskMode: DeskModeStore(state: state, keyLabel: { _ in "B" }),
            brightness: BrightnessStore(position: position, scale: scale, boostAllowed: boostAllowed),
            boostStatus: BoostStatusStore(status: boostStatus),
            preferences: PreferencesStore(defaults: UserDefaults(suiteName: suiteName)!)
        )
        model.preferences.general.onboardingCompleted = onboarded
        bridge = AppIntentBridge(
            model: model,
            deskMode: controllers ? panicker : nil,
            boost: controllers ? booster : nil,
            timing: .init(deskModeSettle: deskModeSettle, boostSettle: 0.1, pollInterval: 0.01)
        )
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// Stands in for `DeskModeController`: each request switches at once, then
    /// lands where `landsOn` says a moment later (nil: stays switching). A
    /// landing on `.on` shows the keep-or-revert prompt when `prompts` says so
    /// or the turn-on forced it. Switch flips arrive in `requests`; forced
    /// turn-ons in `panicker.turnOnRequests`.
    func simulateController(landsOn: ((Bool) -> DeskModeState)?, prompts: Bool = true) {
        let store = model.deskMode
        func drive(_ on: Bool, forcePrompt: Bool) {
            store.update(.switching(toOn: on))
            guard let landsOn else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000)
                let landed = landsOn(on)
                // Like the controller: the prompt flag before the state.
                store.setConfirming(landed.isOn && (prompts || forcePrompt))
                store.update(landed)
            }
        }
        store.requestHandler = { [unowned self] on in
            requests.append(on)
            drive(on, forcePrompt: false)
        }
        panicker.onTurnOn = { forcePrompt in drive(true, forcePrompt: forcePrompt) }
    }
}
