import Combine
import Foundation
import LidlessCore
import Testing
@testable import Lidless

/// `SystemController` across transitions: the lid opening after a clamshell
/// launch, the screens waking, the slider being released and the popover
/// closing mid-hold. Fakes only; nothing here touches the system.
@MainActor
struct SystemControllerTransitionTests {
    // MARK: Desk Mode availability

    /// After a clamshell launch the lid reports open before the panel comes
    /// online. The closed lid already proved the panel, so the permanent
    /// "Not available on this Mac" never flashes in between.
    @Test(arguments: [SystemEvent.lid, .didWake])
    func `opening the lid after a clamshell launch never reports an unsupported Mac`(event: SystemEvent) {
        let rig = SystemRig(facts: [DisplayFixtures.lg])
        rig.system.lidState = .closed
        rig.controller.start()
        #expect(rig.model.deskMode.state == .unavailable(.lidClosed))
        #expect(rig.controller.inventory.builtIn == nil)

        var published: [DeskModeState] = []
        let subscription = rig.model.deskMode.$state.dropFirst().sink { published.append($0) }
        rig.system.lidState = .open
        rig.events.send(event)
        rig.displays.facts = DisplayFixtures.thisMac
        rig.changes.send()

        #expect(!published.contains(.unavailable(.unsupportedMac)))
        #expect(published == [.off])
        subscription.cancel()
    }

    /// Judged against the snapshot from while the screens slept, the awake
    /// latch would publish "Needs a display" and then "Off".
    @Test func `waking the screens judges Desk Mode once, against fresh displays`() {
        let rig = SystemRig()
        rig.controller.start()
        rig.events.send(.screensDidSleep)
        rig.displays.facts = [DisplayFixtures.builtIn]
        rig.changes.send()
        #expect(rig.model.deskMode.state == .off)

        var published: [DeskModeState] = []
        let subscription = rig.model.deskMode.$state.dropFirst().sink { published.append($0) }
        rig.displays.facts = DisplayFixtures.thisMac
        rig.events.send(.screensDidWake)

        #expect(published.isEmpty)
        #expect(rig.model.deskMode.state == .off)
        subscription.cancel()
    }

    // MARK: Brightness hold

    @Test func `the hold left counts from the last touch, and a held slider keeps all of it`() {
        let clock = FakeClock()
        let store = BrightnessStore(clock: { clock.now })
        #expect(store.remainingUserHold() == nil)

        store.position = 90
        clock.now += 0.5
        #expect(store.remainingUserHold() == 1.5)

        store.setTracking(true)
        #expect(store.isTracking)
        clock.now += 10
        #expect(store.remainingUserHold() == 2)

        store.setTracking(false)
        #expect(store.lastUserEdit == clock.now)
        clock.now += 2
        #expect(store.remainingUserHold() == nil)
    }

    @Test func `reads never move a held slider, and wait 2 s after its release`() {
        let rig = SystemRig()
        rig.controller.start()
        rig.controller.popoverWillShow()
        let brightness = rig.model.brightness

        brightness.setTracking(true)
        brightness.position = 130
        rig.brightness.levels[1] = 0.3
        // Held still long past the hold: a still thumb writes no position.
        rig.clock.now += 5
        rig.brightness.sendChange()
        rig.controller.refreshBrightness()
        #expect(brightness.position == 130)

        brightness.setTracking(false)
        rig.clock.now += 1.9
        rig.controller.refreshBrightness()
        #expect(brightness.position == 130)

        rig.clock.now += 0.2
        rig.controller.refreshBrightness()
        #expect(abs(brightness.position - 30) < 1e-9)
        rig.controller.popoverDidClose()
    }

    @Test func `closing the popover mid-drag reads again when the hold ends`() throws {
        let rig = SystemRig()
        var icons: [MenuBarIconState] = []
        let subscription = StatusItemController.iconStates(model: rig.model, iconShowsState: Just(true).eraseToAnyPublisher())
            .sink { icons.append($0) }
        rig.controller.start()
        rig.controller.popoverWillShow()
        let brightness = rig.model.brightness

        brightness.setTracking(true)
        brightness.position = 130
        #expect(icons == [.normal, .boost])

        rig.controller.popoverDidClose()
        #expect(!brightness.isTracking)
        #expect(!rig.controller.isPolling)
        let catchUp = try #require(rig.controller.catchUpRead)

        rig.clock.now += 2.1
        catchUp.fire()
        #expect(rig.controller.catchUpRead == nil)
        #expect(abs(brightness.position - DisplayFixtures.controlCenterLevel * 100) < 1e-9)
        #expect(icons == [.normal, .boost, .normal])
        subscription.cancel()
    }

    @Test func `reopening the popover or stopping cancels the catch-up read`() throws {
        let rig = SystemRig()
        rig.controller.start()
        rig.controller.popoverWillShow()
        rig.model.brightness.position = 130
        rig.controller.popoverDidClose()
        let first = try #require(rig.controller.catchUpRead)

        rig.controller.popoverWillShow()
        #expect(rig.controller.catchUpRead == nil)
        #expect(!first.isValid)

        rig.controller.popoverDidClose()
        let second = try #require(rig.controller.catchUpRead)
        rig.controller.stop()
        #expect(rig.controller.catchUpRead == nil)
        #expect(!second.isValid)
    }

    @Test func `closing without a recent edit schedules no catch-up read`() {
        let rig = SystemRig()
        rig.controller.start()
        rig.controller.popoverWillShow()
        rig.controller.popoverDidClose()
        #expect(rig.controller.catchUpRead == nil)

        rig.controller.popoverWillShow()
        rig.model.brightness.position = 130
        rig.clock.now += 2.1
        rig.controller.popoverDidClose()
        #expect(rig.controller.catchUpRead == nil)
    }
}
