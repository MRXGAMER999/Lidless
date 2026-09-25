import CoreGraphics
import Foundation
import LidlessCore
import Testing
@testable import Lidless

/// `BoostController` against fakes: which overlay, writer and external calls
/// the slider, the guard rails and the keys turn into. The decisions are
/// `BoostMachine`'s and `BoostGuard`'s, tested in LidlessCoreTests.
@MainActor
struct BoostControllerTests {
    typealias Call = BoostCallLog.Call
    let lg = DisplayFixtures.lgUUID

    // MARK: Slider

    @Test func `the normal range writes native brightness and shows nothing`() {
        let rig = BoostRig()
        rig.model.brightness.position = 40
        #expect(rig.log.take() == [.write(0.4, on: 1)])
        #expect(!rig.overlay.isShown)
        #expect(rig.model.boostStatus.status == .off)
        #expect(!rig.controller.isTicking)
    }

    @Test func `the Boost range keeps native at full and puts the overlay up`() {
        let rig = BoostRig()
        rig.model.brightness.position = 130
        let factor = rig.model.brightness.effectiveScale.boostFactor(130)

        // Up at 1 until macOS reports headroom, then the factor follows it.
        #expect(rig.log.take() == [.write(1, on: 1), .show(on: 1, factor: 1, ramp: 0.4)])
        #expect(rig.model.boostStatus.status == .engaging)
        #expect(rig.controller.isTicking)

        rig.overlay.report(headroom: 2)
        #expect(rig.model.boostStatus.status == .on(factor: factor))
        // Coalesced: the next tick sends it.
        #expect(rig.log.take() == [])
        #expect(rig.controller.isTicking)

        rig.advance(BoostMachine.Configuration().minUpdateInterval)
        rig.controller.tick()
        #expect(rig.log.take() == [.show(on: 1, factor: factor, ramp: 0.4)])
        #expect(!rig.controller.isTicking)
    }

    @Test func `moving within Boost writes no native brightness`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.advance(1)
        rig.model.brightness.position = 140
        rig.controller.tick()
        let factor = rig.model.brightness.effectiveScale.boostFactor(140)
        #expect(rig.log.take() == [.show(on: 1, factor: factor, ramp: 0.4)])
    }

    @Test func `Back to 100 hides the overlay without a native write`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.model.brightness.leaveBoost()
        #expect(rig.log.take() == [.hide(ramp: 0.4)])
        #expect(rig.model.boostStatus.status == .off)
        #expect(!rig.controller.isTicking)
    }

    @Test func `a read moves the slider but never writes`() {
        let rig = BoostRig()
        rig.model.brightness.applyRead(BrightnessLevelReading(level: 0.25))
        #expect(rig.model.brightness.position == 25)
        #expect(rig.log.take() == [])
    }

    @Test func `a full read keeps a boosted slider, a lower one leaves Boost`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        let noHold = BrightnessSyncPolicy(userHold: 0)

        rig.model.brightness.applyRead(BrightnessLevelReading(level: 1), policy: noHold)
        #expect(rig.model.brightness.position == 130)
        #expect(rig.log.take() == [])

        rig.model.brightness.applyRead(BrightnessLevelReading(level: 0.9), policy: noHold)
        #expect(rig.model.brightness.position == 90)
        #expect(rig.log.take() == [.hide(ramp: 0.4)])
    }

    @Test func `Boost not allowed leaves Boost`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.model.brightness.boostAllowed = false
        #expect(rig.model.brightness.position == 100)
        #expect(rig.log.take() == [.hide(ramp: 0.4)])
    }

    @Test func `an overlay that can't go up counts as a failure`() {
        let rig = BoostRig()
        rig.overlay.showResult = false
        rig.model.brightness.position = 130
        #expect(rig.log.take() == [.write(1, on: 1), .show(on: 1, factor: 1, ramp: 0.4), .hide(ramp: 0)])
        #expect(!rig.overlay.isShown)
        // Backing off: nothing is up.
        #expect(rig.model.boostStatus.status == .unavailable)
        #expect(rig.controller.isTicking)
    }

    @Test func `three overlays that can't go up make Boost unavailable until the next request`() {
        let rig = BoostRig()
        rig.overlay.showResult = false
        rig.model.brightness.position = 130
        let backoff = BoostMachine.Configuration().backoff
        for _ in 0..<2 {
            rig.advance(backoff)
            rig.controller.tick()
        }
        let show = Call.show(on: 1, factor: 1, ramp: 0.4)
        #expect(rig.log.take() == [.write(1, on: 1), show, .hide(ramp: 0), show, .hide(ramp: 0), show, .hide(ramp: 0)])
        #expect(rig.model.boostStatus.status == .unavailable)
        #expect(!rig.controller.isTicking)

        // No more tries by themselves; a new request tries again.
        rig.advance(backoff)
        rig.controller.tick()
        #expect(rig.log.take() == [])
        rig.overlay.showResult = true
        rig.model.brightness.position = 140
        #expect(rig.log.take() == [show])
        #expect(rig.model.boostStatus.status == .engaging)
    }

    @Test func `losing the screen just before a reconfiguration is no strike`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        // The window goes first; the reconfiguration signal follows.
        rig.overlay.lose()
        #expect(rig.controller.isLossPending)
        #expect(rig.log.take() == [])
        rig.signals.send(.reconfigurationBegan)
        #expect(!rig.controller.isLossPending)
        #expect(rig.log.take() == [.pauseExternals, .hide(ramp: 0)])

        rig.advance(BoostController.lossGrace)
        rig.controller.lossTimerFired()
        rig.signals.send(.reconfigurationEnded)
        rig.advance(BoostController.settleTime)
        rig.controller.settleTimerFired()
        // No back-off: the overlay comes straight back.
        #expect(rig.log.take() == [.resumeExternals(after: 1), .show(on: 1, factor: 1, ramp: 0.4)])
        #expect(rig.overlay.isShown)
        #expect(rig.model.boostStatus.status == .engaging)
    }

    @Test func `losing the screen during a reconfiguration is no strike`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.signals.send(.reconfigurationBegan)
        rig.overlay.lose()
        #expect(!rig.controller.isLossPending)
        rig.signals.send(.reconfigurationEnded)
        rig.advance(BoostController.settleTime)
        rig.controller.settleTimerFired()
        #expect(rig.log.take() == [.pauseExternals, .hide(ramp: 0), .resumeExternals(after: 1), .show(on: 1, factor: 1, ramp: 0.4)])
        #expect(rig.model.boostStatus.status == .engaging)
    }

    @Test func `losing the screen otherwise is a failure after the grace`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.overlay.lose()
        #expect(rig.log.take() == [])
        #expect(rig.controller.isLossPending)

        rig.advance(BoostController.lossGrace)
        rig.controller.lossTimerFired()
        #expect(!rig.controller.isLossPending)
        #expect(rig.log.take() == [.hide(ramp: 0)])
        #expect(!rig.overlay.isShown)
        #expect(rig.model.boostStatus.status == .unavailable)
    }

    @Test func `a mirrored built-in suspends Boost instead of failing`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        var mirrored = DisplayFixtures.builtIn
        mirrored.mirrorsDisplay = DisplayFixtures.lg.displayID
        rig.controller.displaysDidChange(DisplayInventory(facts: [DisplayFixtures.lg, mirrored], previousBuiltIn: nil, names: DisplayFixtures.names))
        #expect(rig.log.take() == [.hide(ramp: 0)])
        #expect(rig.model.boostStatus.status == .blocked(.builtInUnavailable))

        // The built-in as the mirror source reads as mirrored through CoreGraphics.
        rig.advance(1)
        rig.controller.displaysDidChange(DisplayInventory(facts: DisplayFixtures.thisMac, previousBuiltIn: nil, names: DisplayFixtures.names))
        #expect(rig.log.take() == [.show(on: 1, factor: 1, ramp: 0.4)])
        rig.mirror.isOn = true
        rig.controller.displaysDidChange(DisplayInventory(facts: DisplayFixtures.thisMac, previousBuiltIn: nil, names: DisplayFixtures.names))
        #expect(rig.log.take() == [.hide(ramp: 0)])
        #expect(rig.model.boostStatus.status == .blocked(.builtInUnavailable))

        // Native brightness still goes to a mirrored built-in.
        rig.model.brightness.position = 40
        #expect(rig.log.take() == [.write(0.4, on: 1)])
    }

    @Test func `nothing shows before the displays are read`() {
        let rig = BoostRig(connect: false)
        rig.model.brightness.position = 130
        #expect(rig.log.take() == [])
        #expect(rig.model.boostStatus.status == .blocked(.unsupported))
    }

    // MARK: Guard rails

    @Test func `Desk Mode engaging hides at once and pauses DDC`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        let cancels = rig.writer.cancels
        rig.controller.deskModeDidChange(engaged: true, switching: true)
        #expect(rig.log.take() == [.pauseExternals, .hide(ramp: 0)])
        #expect(rig.model.boostStatus.status == .blocked(.builtInUnavailable))
        // A coalesced write still waiting is dropped.
        #expect(rig.writer.cancels == cancels + 1)

        // Native writes wait too: the panel is switching.
        rig.model.brightness.position = 40
        #expect(rig.log.take() == [])
    }

    @Test func `a level held back while displays change is written when they settle`() {
        let rig = BoostRig()
        rig.signals.send(.reconfigurationBegan)
        rig.model.brightness.position = 40
        #expect(rig.log.take() == [.pauseExternals])
        rig.signals.send(.reconfigurationEnded)
        #expect(rig.log.take() == [.resumeExternals(after: 1), .write(0.4, on: 1)])

        // A read of macOS's level in between replaces it.
        rig.controller.deskModeDidChange(engaged: true, switching: false)
        rig.model.brightness.position = 60
        rig.model.brightness.applyRead(BrightnessLevelReading(level: 0.3), policy: BrightnessSyncPolicy(userHold: 0))
        rig.controller.deskModeDidChange(engaged: false, switching: false)
        #expect(rig.log.take() == [])
    }

    @Test func `a fade under way ends at once when a block starts`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.model.brightness.leaveBoost()
        #expect(rig.log.take() == [.hide(ramp: 0.4)])
        #expect(rig.overlay.isFading)

        rig.controller.deskModeDidChange(engaged: true, switching: true)
        #expect(rig.log.take() == [.pauseExternals, .hide(ramp: 0)])
        #expect(!rig.overlay.isShown)
    }

    @Test func `a fade under way ends at once when displays reconfigure`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.model.brightness.leaveBoost()
        _ = rig.log.take()
        rig.signals.send(.reconfigurationBegan)
        #expect(rig.log.take() == [.pauseExternals, .hide(ramp: 0)])
        #expect(!rig.overlay.isShown)
    }

    @Test func `the panic key ends a fade under way`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.model.brightness.leaveBoost()
        _ = rig.log.take()
        rig.controller.panic()
        #expect(rig.log.take() == [.hide(ramp: 0), .removeShades])
        #expect(!rig.overlay.isShown)
    }

    @Test func `Boost comes back after Desk Mode ends`() {
        let rig = BoostRig()
        rig.boost(to: 150)
        rig.controller.deskModeDidChange(engaged: true, switching: true)
        rig.controller.deskModeDidChange(engaged: true, switching: false)
        #expect(rig.log.take() == [.pauseExternals, .hide(ramp: 0), .resumeExternals(after: 1)])

        rig.advance(1)
        rig.controller.deskModeDidChange(engaged: false, switching: false)
        #expect(rig.log.take() == [.show(on: 1, factor: 1, ramp: 0.4)])

        rig.overlay.report(headroom: 3)
        rig.advance(1)
        rig.controller.tick()
        let factor = rig.model.brightness.effectiveScale.boostFactor(150)
        #expect(rig.log.take() == [.show(on: 1, factor: factor, ramp: 0.4)])
    }

    @Test func `the panic key tears Boost down, leaves it and removes the shades`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.controller.panic()
        #expect(rig.log.take() == [.hide(ramp: 0), .removeShades])
        #expect(rig.model.brightness.position == 100)
        #expect(rig.model.boostStatus.status == .off)
    }

    @Test func `sleep hides at once and wakes at 100`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.controller.handle(.willSleep)
        #expect(rig.log.take() == [.pauseExternals, .hide(ramp: 0)])
        #expect(rig.model.boostStatus.status == .blocked(.screenAsleepOrLocked))

        rig.controller.handle(.didWake)
        #expect(rig.model.brightness.position == 100)
        #expect(rig.model.boostStatus.status == .off)
        #expect(rig.log.take() == [.resumeExternals(after: 3)])
    }

    @Test func `without Wake at 100, Boost returns after the settle`() {
        var settings = BoostSettings.defaults
        settings.wakeAtNormal = false
        let rig = BoostRig(settings: settings)
        rig.boost(to: 130)
        rig.controller.handle(.screensDidSleep)
        rig.controller.handle(.screensDidWake)
        #expect(rig.log.take() == [.hide(ramp: 0)])
        #expect(rig.model.brightness.position == 130)
        #expect(rig.model.boostStatus.status == .blocked(.reconfiguring))

        rig.advance(BoostController.settleTime)
        rig.controller.settleTimerFired()
        #expect(!rig.controller.isSettling)
        #expect(rig.log.take() == [.show(on: 1, factor: 1, ramp: 0.4)])
    }

    @Test func `a wake inside a reconfiguration doesn't end it early`() {
        var settings = BoostSettings.defaults
        settings.wakeAtNormal = false
        let rig = BoostRig(settings: settings)
        rig.boost(to: 130)
        rig.signals.send(.reconfigurationBegan)
        rig.controller.handle(.screensDidWake)
        #expect(rig.log.take() == [.pauseExternals, .hide(ramp: 0)])

        // The wake's settle ends; the reconfiguration hasn't.
        rig.advance(BoostController.settleTime)
        rig.controller.settleTimerFired()
        #expect(rig.model.boostStatus.status == .blocked(.reconfiguring))
        #expect(rig.controller.isSettling)
        #expect(rig.log.take() == [])
        rig.model.brightness.position = 60
        #expect(rig.log.take() == [])

        // Its real end starts the settle, and only then does Boost return.
        rig.signals.send(.reconfigurationEnded)
        #expect(rig.log.take() == [.resumeExternals(after: 1), .write(0.6, on: 1)])
        rig.model.brightness.position = 130
        rig.advance(BoostController.settleTime - 1)
        rig.controller.settleTimerFired()
        #expect(rig.model.boostStatus.status == .blocked(.reconfiguring))
        rig.advance(1)
        rig.controller.settleTimerFired()
        #expect(rig.log.take() == [.write(1, on: 1), .show(on: 1, factor: 1, ramp: 0.4)])
    }

    @Test func `a wake never shortens a settle already running`() {
        var settings = BoostSettings.defaults
        settings.wakeAtNormal = false
        let rig = BoostRig(settings: settings)
        rig.boost(to: 130)
        rig.signals.send(.reconfigurationBegan)
        rig.signals.send(.reconfigurationEnded)
        rig.advance(2)
        rig.controller.handle(.screensDidWake)
        _ = rig.log.take()
        // The reconfiguration's settle would end now; the wake's runs 2 s more.
        rig.advance(1)
        rig.controller.settleTimerFired()
        #expect(rig.model.boostStatus.status == .blocked(.reconfiguring))
        rig.advance(2)
        rig.controller.settleTimerFired()
        #expect(rig.log.take() == [.show(on: 1, factor: 1, ramp: 0.4)])
    }

    @Test func `the lock suspends Boost until unlocked`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.signals.send(.screenLocked(true))
        #expect(rig.log.take() == [.hide(ramp: 0)])
        #expect(rig.model.boostStatus.status == .blocked(.screenAsleepOrLocked))

        rig.advance(1)
        rig.signals.send(.screenLocked(false))
        #expect(rig.log.take() == [.show(on: 1, factor: 1, ramp: 0.4)])
        #expect(rig.overlay.isShown)
    }

    @Test func `leaving the session suspends Boost`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.controller.handle(.sessionDidResignActive)
        #expect(rig.log.take() == [.hide(ramp: 0)])
        #expect(rig.model.boostStatus.status == .blocked(.screenAsleepOrLocked))
    }

    @Test func `a reconfiguration hides at once, pauses DDC and waits for the settle`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.signals.send(.reconfigurationBegan)
        #expect(rig.log.take() == [.pauseExternals, .hide(ramp: 0)])

        // No native write while displays change; the last one waits.
        rig.model.brightness.position = 60
        rig.model.brightness.position = 130
        #expect(rig.log.take() == [])

        rig.signals.send(.reconfigurationEnded)
        #expect(rig.log.take() == [.resumeExternals(after: 1), .write(1, on: 1)])
        #expect(rig.controller.isSettling)

        rig.advance(BoostController.settleTime)
        rig.controller.settleTimerFired()
        #expect(rig.log.take() == [.show(on: 1, factor: 1, ramp: 0.4)])
        #expect(rig.overlay.isShown)
    }

    @Test func `every reconfiguration end pushes the DDC resume back`() {
        let rig = BoostRig()
        // One begin and one end per display.
        rig.signals.send(.reconfigurationBegan)
        rig.signals.send(.reconfigurationBegan)
        rig.signals.send(.reconfigurationEnded)
        rig.signals.send(.reconfigurationEnded)
        #expect(rig.log.take() == [.pauseExternals, .resumeExternals(after: 1), .resumeExternals(after: 1)])

        // Not while Desk Mode still holds DDC.
        rig.controller.deskModeDidChange(engaged: true, switching: true)
        rig.signals.send(.reconfigurationBegan)
        rig.signals.send(.reconfigurationEnded)
        rig.signals.send(.reconfigurationEnded)
        #expect(rig.log.take() == [.pauseExternals])
    }

    @Test func `a reconfiguration that never ends stops blocking after the limit`() {
        let rig = BoostRig()
        rig.signals.send(.reconfigurationBegan)
        _ = rig.log.take()
        rig.advance(BoostController.reconfigurationLimit)
        rig.controller.settleTimerFired()
        #expect(rig.log.take() == [.resumeExternals(after: 1)])
        rig.model.brightness.position = 40
        #expect(rig.log.take() == [.write(0.4, on: 1)])
    }

    @Test func `heat pauses Boost and tells the user once`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.controller.systemDidChange(lid: .open, power: .adapter, thermal: .serious)
        #expect(rig.log.take() == [.hide(ramp: 0), .notify(hot: true)])
        #expect(rig.model.boostStatus.status == .blocked(.hot))

        rig.controller.systemDidChange(lid: .open, power: .adapter, thermal: .critical)
        #expect(rig.log.take() == [])
    }

    @Test func `Low Power Mode pauses Boost`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.signals.send(.lowPowerMode(true))
        #expect(rig.model.boostStatus.status == .blocked(.lowPower))
    }

    /// macOS asks a background menu bar app to hold back HDR nearly all the
    /// time; the request is advisory and Boost must keep running through it.
    @Test func `HDR suppression is ignored`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        let boosted = rig.model.boostStatus.status
        #expect(boosted == .on(factor: rig.model.brightness.effectiveScale.boostFactor(130)))
        rig.signals.send(.hdrSuppressed(true))
        #expect(rig.model.boostStatus.status == boosted)
        #expect(rig.log.take() == [])
        rig.signals.send(.hdrSuppressed(false))
        #expect(rig.model.boostStatus.status == boosted)
    }

    @Test func `the lid closing suspends Boost`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.controller.systemDidChange(lid: .closed, power: .adapter, thermal: .nominal)
        #expect(rig.log.take() == [.hide(ramp: 0)])
        #expect(rig.model.boostStatus.status == .blocked(.builtInUnavailable))
    }

    @Test func `a new ceiling while boosted changes the factor`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.advance(1)
        let scale = BrightnessScale(normalMaxNits: 600, ceilingNits: 800)
        rig.model.brightness.applyScale(scale)
        #expect(rig.log.take() == [.show(on: 1, factor: scale.boostFactor(130), ramp: 0.4)])
        #expect(rig.model.boostStatus.status == .on(factor: scale.boostFactor(130)))
        #expect(rig.model.brightness.position == 130)
    }

    @Test func `a ceiling below normal maximum leaves Boost`() {
        let rig = BoostRig()
        rig.boost(to: 130)
        rig.model.brightness.applyScale(BrightnessScale(normalMaxNits: 600, ceilingNits: 550))
        #expect(rig.model.brightness.position == 100)
        #expect(rig.log.take() == [.hide(ramp: 0.4)])
        #expect(rig.model.boostStatus.status == .off)
    }

    @Test func `the ceiling from Settings reaches the overlay`() {
        let system = SystemRig()
        defer { system.cleanUp() }
        let rig = BoostRig(model: system.model, connect: false)
        system.controller.boost = rig.controller
        system.controller.start()
        rig.boost(to: 130)
        rig.advance(1)

        system.model.preferences.boost.ceilingNits = 800
        let scale = system.model.brightness.effectiveScale
        #expect(scale.ceilingNits == 800)
        #expect(rig.log.take() == [.show(on: 1, factor: scale.boostFactor(130), ramp: 0.4)])
    }

    @Test func `starting locked or in Low Power Mode starts blocked`() {
        let signals = FakeBoostSignals()
        signals.isScreenLocked = true
        let rig = BoostRig(signals: signals)
        rig.model.brightness.position = 130
        #expect(rig.model.boostStatus.status == .blocked(.screenAsleepOrLocked))
        #expect(!rig.overlay.isShown)
    }

    // MARK: Keys

    @Test func `the Boost key goes to the ceiling, back to 100, then to the last boosted position`() {
        let rig = BoostRig()
        let registrar = FakeHotKeyRegistrar()
        rig.controller.bindHotKeys(.fake(registrar))
        #expect(registrar.held[HotKeyID.toggleBoost.rawValue] != nil)

        #expect(registrar.press(.toggleBoost))
        #expect(rig.model.brightness.position == BrightnessScale.sliderMax)
        #expect(registrar.press(.toggleBoost))
        #expect(rig.model.brightness.position == 100)

        rig.model.brightness.position = 120
        #expect(registrar.press(.toggleBoost))
        #expect(rig.model.brightness.position == 100)
        #expect(registrar.press(.toggleBoost))
        #expect(rig.model.brightness.position == 120)
    }

    @Test func `the Boost key returns to where a drag stopped, not where it passed`() {
        let rig = BoostRig()
        let store = rig.model.brightness
        store.position = 140

        // Dragged down out of Boost: the positions on the way don't count.
        store.setTracking(true)
        store.position = 120
        store.position = 101
        store.position = 100
        store.setTracking(false)
        rig.controller.toggle()
        #expect(store.position == 140)

        // Released inside Boost: that is the new place.
        store.setTracking(true)
        store.position = 125
        store.setTracking(false)
        store.leaveBoost()
        rig.controller.toggle()
        #expect(store.position == 125)
    }

    @Test func `a cleared Boost key is unregistered`() {
        let rig = BoostRig()
        let registrar = FakeHotKeyRegistrar()
        rig.controller.bindHotKeys(.fake(registrar))
        rig.model.preferences.shortcuts.toggleBoost = nil
        #expect(registrar.held[HotKeyID.toggleBoost.rawValue] == nil)
    }

    @Test func `the brightness keys go into Boost only with Input Monitoring`() {
        let denied = BoostRig()
        #expect(!denied.keys.isRunning)
        #expect(!denied.controller.isKeyTapRunning)

        let keys = FakeBrightnessKeys()
        keys.permission = .granted
        let rig = BoostRig(keys: keys)
        #expect(keys.isRunning)
        rig.nativeLevel = 1
        rig.model.brightness.position = 100
        keys.press(.up)
        #expect(rig.model.brightness.position == 100 + BrightnessKeyPolicy.boostStep)
        #expect(rig.overlay.isShown)
    }

    @Test func `brightness-down leaves Boost, even right after the Boost key`() {
        let keys = FakeBrightnessKeys()
        keys.permission = .granted
        let rig = BoostRig(keys: keys)
        rig.nativeLevel = 1
        rig.controller.toggle()
        #expect(rig.model.brightness.isBoosted)
        _ = rig.log.take()

        // Inside the 2 s hold after the Boost key: macOS drops a step.
        keys.press(.down)
        #expect(rig.controller.isFollowingKey)
        rig.nativeLevel = 0.92
        rig.controller.keyFollowFired()
        #expect(!rig.controller.isFollowingKey)
        #expect(abs(rig.model.brightness.position - 92) < 0.001)
        #expect(rig.log.take() == [.hide(ramp: 0.4)])
    }

    @Test func `brightness keys do nothing while the built-in is off or shut`() {
        let keys = FakeBrightnessKeys()
        keys.permission = .granted
        let rig = BoostRig(keys: keys)
        rig.model.brightness.position = 100
        _ = rig.log.take()
        // Desk Mode: no level to read.
        rig.nativeLevel = nil
        rig.controller.deskModeDidChange(engaged: true, switching: false)
        keys.press(.up)
        #expect(rig.model.brightness.position == 100)
        #expect(!rig.controller.isFollowingKey)
        rig.controller.deskModeDidChange(engaged: false, switching: false)

        // The lid shut.
        rig.controller.systemDidChange(lid: .closed, power: .adapter, thermal: .nominal)
        keys.press(.up)
        #expect(rig.model.brightness.position == 100)
        rig.controller.systemDidChange(lid: .open, power: .adapter, thermal: .nominal)

        // The built-in offline.
        rig.controller.displaysDidChange(DisplayInventory(facts: [DisplayFixtures.lg], previousBuiltIn: nil, names: DisplayFixtures.names))
        keys.press(.up)
        #expect(rig.model.brightness.position == 100)
        #expect(rig.log.take().allSatisfy { if case .show = $0 { false } else { true } })
    }

    @Test func `turning Keep pressing to boost off stops the tap`() {
        let keys = FakeBrightnessKeys()
        keys.permission = .granted
        let rig = BoostRig(keys: keys)
        #expect(keys.isRunning)
        rig.model.preferences.boost.keysIntoBoost = false
        #expect(!keys.isRunning)
    }

    // MARK: External brightness

    @Test func `external displays and sliders reach the external controller`() {
        let rig = BoostRig()
        // The built-in goes too, for the controller's mirroring check.
        #expect(rig.externals.displays == [DisplayFixtures.builtInUUID, lg])

        rig.model.externalBrightness.setLevel(0.5, for: lg)
        #expect(rig.log.take() == [.setExternal(lg, 0.5)])
    }

    @Test func `the external controller's levels and methods come back without being applied`() {
        let rig = BoostRig()
        rig.externals.levels[lg] = 0.3
        rig.externals.methods[lg] = .shade
        rig.externals.onChange?()
        #expect(rig.model.externalBrightness.level(for: lg) == 0.3)
        #expect(rig.model.externalBrightness.method(for: lg) == .shade)
        #expect(rig.log.take() == [])
    }

    @Test func `sleep and a reconfiguration pause DDC once until both end`() {
        let rig = BoostRig()
        rig.controller.handle(.willSleep)
        rig.signals.send(.reconfigurationBegan)
        rig.signals.send(.reconfigurationEnded)
        #expect(rig.log.take() == [.pauseExternals])
        rig.controller.handle(.didWake)
        #expect(rig.log.take() == [.resumeExternals(after: 3)])
    }

    // MARK: Quit

    @Test func `terminate removes the overlay, the shades and the key tap`() {
        let keys = FakeBrightnessKeys()
        keys.permission = .granted
        let rig = BoostRig(keys: keys)
        rig.boost(to: 130)
        rig.controller.terminate()
        let calls = rig.log.take()
        #expect(calls.first == .hide(ramp: 0))
        #expect(calls.contains(.removeShades))
        #expect(!keys.isRunning)
        #expect(!rig.controller.isTicking)
        #expect(rig.signals.isStopped)

        // Nothing reaches the screen afterwards, not even Desk Mode ending
        // (the quit path ends Boost first).
        rig.model.brightness.position = 40
        rig.controller.deskModeDidChange(engaged: true, switching: true)
        rig.controller.deskModeDidChange(engaged: false, switching: false)
        rig.signals.send(.reconfigurationBegan)
        #expect(rig.log.take() == [])
    }

    // MARK: Wiring with Desk Mode and SystemController

    @Test func `Desk Mode tells Boost before the disable starts`() {
        let desk = DeskModeRig()
        let spy = InterlockSpy()
        desk.controller.boost = spy
        desk.connect()
        spy.onChange = { _, _ in spy.disablesAtReport.append(desk.builtIn.pendingDisables) }
        desk.controller.setOn(true)
        #expect(spy.reports.first?.engaged == true)
        #expect(spy.reports.first?.switching == true)
        #expect(spy.disablesAtReport.first == 0)

        // The keep-or-revert prompt still counts as switching: DDC stays quiet.
        desk.builtIn.finishDisable(true)
        desk.controller.displaysDidChange(facts: DeskModeRig.builtInOff, lid: .open, power: .adapter)
        #expect(spy.reports.last?.switching == true)
        #expect(spy.reports.last?.engaged == true)

        desk.confirmation.pressKeep()
        #expect(spy.reports.last?.switching == false)
        #expect(spy.reports.last?.engaged == true)
    }

    @Test func `the Desk Mode panic key reaches Boost`() {
        let desk = DeskModeRig()
        let spy = InterlockSpy()
        desk.controller.boost = spy
        desk.connect()
        desk.controller.panic()
        #expect(spy.panics == 1)
    }

    @Test func `SystemController ignores the echo of Boost's own write`() {
        let system = SystemRig()
        let rig = BoostRig(model: system.model, connect: false)
        system.controller.boost = rig.controller
        system.controller.start()
        let before = system.model.brightness.position

        system.brightness.levels[1] = 0.8
        rig.writer.echoes = [0.8]
        system.controller.refreshBrightness()
        #expect(system.model.brightness.position == before)

        rig.writer.echoes = []
        system.controller.refreshBrightness()
        #expect(abs(system.model.brightness.position - 80) < 0.001)
    }

    @Test func `the Boost ceiling and Boost allowed follow Settings`() {
        let system = SystemRig()
        defer { system.cleanUp() }
        system.model.preferences.boost.ceilingNits = 800
        system.controller.start()
        #expect(system.model.brightness.scale.ceilingNits == 800)

        system.model.preferences.boost.allowed = false
        #expect(!system.model.brightness.boostAllowed)
        system.model.preferences.boost.ceilingNits = 900
        #expect(system.model.brightness.scale.ceilingNits == 900)
    }

    @Test func `boosted, a lower level inside the hold is read again when it ends`() {
        let system = SystemRig()
        defer { system.cleanUp() }
        system.brightness.levels[1] = 1
        let rig = BoostRig(model: system.model, connect: false)
        system.controller.boost = rig.controller
        system.controller.start()
        // The Boost key: a user edit, so reads wait out the hold.
        rig.controller.toggle()
        #expect(system.model.brightness.isBoosted)
        #expect(system.controller.catchUpRead == nil)

        system.brightness.levels[1] = 0.92
        system.brightness.sendChange()
        #expect(system.model.brightness.isBoosted)
        #expect(system.controller.catchUpRead != nil)

        system.clock.now += BrightnessSyncPolicy().userHold + 0.1
        system.controller.catchUpRead?.fire()
        #expect(!system.model.brightness.isBoosted)
        #expect(abs(system.model.brightness.position - 92) < 0.001)
    }

    @Test func `boosted, the level is followed with the popover closed`() {
        let system = SystemRig()
        let rig = BoostRig(model: system.model, connect: false)
        system.controller.boost = rig.controller
        system.controller.start()
        #expect(system.brightness.observed == nil)

        system.model.brightness.position = 130
        #expect(system.brightness.observed == 1)
        #expect(!system.controller.isPolling)

        system.model.brightness.leaveBoost()
        #expect(system.brightness.observed == nil)
    }

    @Test func `Boost settings persist under their own key`() {
        let suiteName = "BoostSettings.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PreferencesStore(defaults: defaults)
        #expect(store.boost == .defaults)
        store.boost.pauseBelowBattery = nil
        #expect(defaults.data(forKey: PreferencesStore.boostKey) != nil)
        #expect(PreferencesStore(defaults: defaults).boost.pauseBelowBattery == nil)
    }
}

// MARK: - Fakes

/// What the controller asked of its services, in order.
@MainActor
final class BoostCallLog {
    enum Call: Equatable {
        case show(on: CGDirectDisplayID, factor: Double, ramp: Double)
        case hide(ramp: Double)
        case write(Double, on: CGDirectDisplayID)
        case notify(hot: Bool)
        case setExternal(String, Double)
        case pauseExternals
        case resumeExternals(after: TimeInterval)
        case removeShades
    }

    private(set) var calls: [Call] = []

    func record(_ call: Call) { calls.append(call) }

    func take() -> [Call] {
        defer { calls = [] }
        return calls
    }
}

@MainActor
final class FakeBoostOverlay: BoostOverlay {
    var showResult = true
    /// Up, or still fading out after a hide that ramps.
    private(set) var isShown = false
    /// A hide that ramps leaves the window up until `finishFade()`, like the real one.
    private(set) var isFading = false
    var onHeadroom: (@MainActor (Double) -> Void)?
    var onLost: (@MainActor () -> Void)?
    private let log: BoostCallLog

    init(log: BoostCallLog) { self.log = log }

    func show(on displayID: CGDirectDisplayID, factor: Double, rampSeconds: Double) -> Bool {
        log.record(.show(on: displayID, factor: factor, ramp: rampSeconds))
        isShown = showResult
        isFading = false
        return showResult
    }

    func hide(rampSeconds: Double) {
        log.record(.hide(ramp: rampSeconds))
        isFading = isShown && rampSeconds > 0
        isShown = isFading
    }

    /// The ramp to 1 ended and the window went.
    func finishFade() {
        guard isFading else { return }
        isFading = false
        isShown = false
    }

    func report(headroom: Double) { onHeadroom?(headroom) }

    /// What the panel does when it leaves the built-in: gone, then reported.
    func lose() {
        isShown = false
        isFading = false
        onLost?()
    }
}

@MainActor
final class FakeBuiltInWriter: BuiltInBrightnessWriter {
    var echoes: [Double] = []
    /// `cancelPending` calls; not in the log, which would repeat them everywhere.
    private(set) var cancels = 0
    private let log: BoostCallLog

    init(log: BoostCallLog) { self.log = log }

    func setLevel(_ level: Double, of display: CGDirectDisplayID) -> Bool {
        log.record(.write(level, on: display))
        return true
    }

    func isEcho(_ level: Double) -> Bool { echoes.contains(level) }

    func cancelPending() { cancels += 1 }
}

@MainActor
final class FakeExternals: ExternalBrightnessControl {
    private(set) var displays: [String] = []
    var levels: [String: Double] = [:]
    var methods: [String: ExternalBrightnessMethod] = [:]
    var onChange: (@MainActor () -> Void)?
    private let log: BoostCallLog

    init(log: BoostCallLog) { self.log = log }

    func update(displays: [DisplayDescriptor]) { self.displays = displays.map(\.id) }
    func method(for displayUUID: String) -> ExternalBrightnessMethod { methods[displayUUID] ?? .probing }
    func level(for displayUUID: String) -> Double? { levels[displayUUID] }
    func setLevel(_ level: Double, for displayUUID: String) { log.record(.setExternal(displayUUID, level)) }
    func pause() { log.record(.pauseExternals) }
    func resume(after delay: TimeInterval) { log.record(.resumeExternals(after: delay)) }
    func removeAllShades() { log.record(.removeShades) }
}

@MainActor
final class FakeBrightnessKeys: BrightnessKeySource {
    var permission = InputMonitoringPermission.notDetermined
    private(set) var requests = 0
    private var handler: (@MainActor (BrightnessKeyPolicy.Key) -> Void)?
    var isRunning: Bool { handler != nil }

    func requestPermission() { requests += 1 }

    func start(handler: @escaping @MainActor (BrightnessKeyPolicy.Key) -> Void) -> Bool {
        guard permission == .granted else { return false }
        self.handler = handler
        return true
    }

    func stop() { handler = nil }

    func press(_ key: BrightnessKeyPolicy.Key) { handler?(key) }
}

@MainActor
final class FakeBoostNotifier: BoostNotifier {
    private let log: BoostCallLog

    init(log: BoostCallLog) { self.log = log }

    func boostPaused(hot: Bool) { log.record(.notify(hot: hot)) }
}

@MainActor
final class FakeBoostSignals: BoostSignalSource {
    var isScreenLocked = false
    var isLowPowerModeEnabled = false
    var isHDRSuppressed = false
    private var handler: (@MainActor (BoostSignal) -> Void)?
    private(set) var isStopped = false

    func start(handler: @escaping @MainActor (BoostSignal) -> Void) { self.handler = handler }
    func stop() {
        handler = nil
        isStopped = true
    }

    func send(_ signal: BoostSignal) { handler?(signal) }
}

@MainActor
final class InterlockSpy: DeskModeBoostInterlock {
    private(set) var reports: [(engaged: Bool, switching: Bool)] = []
    private(set) var panics = 0
    var disablesAtReport: [Int] = []
    var onChange: ((Bool, Bool) -> Void)?

    func deskModeDidChange(engaged: Bool, switching: Bool) {
        reports.append((engaged, switching))
        onChange?(engaged, switching)
    }

    func panic() { panics += 1 }
}

/// Whether the fake mirror check reports a mirror set.
@MainActor
final class MirrorFlag {
    var isOn = false
}

/// A controller wired to fakes, on this Mac's displays (unless `connect` is
/// false), with preferences in a private UserDefaults suite.
@MainActor
final class BoostRig {
    let clock = FakeClock()
    let log = BoostCallLog()
    let overlay: FakeBoostOverlay
    let writer: FakeBuiltInWriter
    let externals: FakeExternals
    let keys: FakeBrightnessKeys
    let signals: FakeBoostSignals
    let model: AppModel
    let controller: BoostController
    /// What `readBrightness` returns.
    var nativeLevel: Double?
    /// What the controller's mirror check answers for every display.
    let mirror = MirrorFlag()
    private let suiteName = "BoostRig.\(UUID().uuidString)"

    init(
        settings: BoostSettings = .defaults,
        keys: FakeBrightnessKeys = FakeBrightnessKeys(),
        signals: FakeBoostSignals = FakeBoostSignals(),
        model: AppModel? = nil,
        connect: Bool = true
    ) {
        overlay = FakeBoostOverlay(log: log)
        writer = FakeBuiltInWriter(log: log)
        externals = FakeExternals(log: log)
        self.keys = keys
        self.signals = signals
        let clock = clock
        self.model = model ?? AppModel(
            brightness: BrightnessStore(clock: { clock.now }),
            preferences: PreferencesStore(defaults: UserDefaults(suiteName: suiteName)!)
        )
        if settings != self.model.preferences.boost { self.model.preferences.boost = settings }
        controller = BoostController(
            model: self.model,
            services: BoostController.Services(
                overlay: overlay,
                writer: writer,
                externals: externals,
                keys: keys,
                notifier: FakeBoostNotifier(log: log),
                signals: signals
            ),
            clock: { clock.now },
            isInMirrorSet: { [mirror] _ in mirror.isOn }
        )
        controller.readBrightness = { [weak self] in self?.nativeLevel.map { BrightnessLevelReading(level: $0) } }
        controller.start()
        if connect {
            controller.systemDidChange(lid: .open, power: .adapter, thermal: .nominal)
            controller.displaysDidChange(DisplayInventory(facts: DisplayFixtures.thisMac, previousBuiltIn: nil, names: DisplayFixtures.names))
        }
        _ = log.take()
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func advance(_ seconds: TimeInterval) { clock.now += seconds }

    /// Boosts to `position` and lets the overlay engage at its full factor
    /// (headroom 3, then the coalesced show); the log is empty after.
    func boost(to position: Double) {
        model.brightness.position = position
        overlay.report(headroom: 3)
        advance(1)
        controller.tick()
        _ = log.take()
    }
}
