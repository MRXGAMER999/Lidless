import Combine
import CoreGraphics
import Foundation
import LidlessCore
import Testing
@testable import Lidless

/// `SystemController` driven by fakes loaded with this Mac's readings, so the
/// wiring is checked without touching (or depending on) the real hardware.
@MainActor
struct SystemControllerTests {
    // MARK: Launch

    @Test func `start publishes this Mac's state`() {
        let rig = SystemRig()
        rig.controller.start()

        let system = rig.model.system
        #expect(system.lid == .open)
        #expect(system.power == .adapter)
        #expect(system.thermal == .nominal)
        #expect(system.builtIn == DisplayFixtures.builtInDescriptor)
        #expect(system.externals == [DisplayFixtures.lgDescriptor])
        #expect(system.externals.first?.resolutionClass == "1080p")
        #expect(rig.segments == [.lidOpen, .displayCount(2), .onPower])
        #expect(rig.model.deskMode.state == .off)

        let inventory = rig.controller.inventory
        #expect(inventory.builtInOnline)
        #expect(!inventory.builtInPresetLocksBrightness)
        #expect(inventory.usableExternalCount == 1)
        #expect(inventory.virtualCount == 0)

        let brightness = rig.model.brightness
        #expect(brightness.scale.normalMaxNits == 600)
        #expect(brightness.scale.ceilingNits == 1000)
        #expect(brightness.scale.curve?.stops.count == 17)
        #expect(abs(brightness.position - DisplayFixtures.controlCenterLevel * 100) < 0.001)
        #expect(brightness.scale.displayPercent(brightness.position) == 51)
        #expect(brightness.scale.displayNits(brightness.position) == 140)
        #expect(rig.model.externalBrightness.level(for: DisplayFixtures.lgDescriptor.id) == 1)
    }

    @Test func `start subscribes once and reads the built-in once`() {
        let rig = SystemRig()
        rig.controller.start()
        rig.controller.start()
        #expect(rig.changes.startCount == 1)
        #expect(rig.events.startCount == 1)
        #expect(rig.displays.snapshotCount == 1)
        #expect(rig.brightness.reads == [1])
        #expect(rig.brightness.observed == nil)
        #expect(!rig.controller.isPolling)
    }

    @Test func `identical refreshes publish nothing`() {
        let rig = SystemRig()
        rig.controller.start()
        var publishes = 0
        let model = rig.model
        let subscriptions = [
            model.system.objectWillChange.sink { publishes += 1 },
            model.deskMode.objectWillChange.sink { publishes += 1 },
            model.brightness.objectWillChange.sink { publishes += 1 },
            model.externalBrightness.objectWillChange.sink { publishes += 1 },
        ]

        rig.changes.send()
        for event in [SystemEvent.lid, .power, .thermal, .didWake, .screensDidWake, .sessionDidBecomeActive] {
            rig.events.send(event)
        }
        rig.controller.refreshBrightness()

        #expect(publishes == 0)
        subscriptions.forEach { $0.cancel() }
    }

    /// Availability is judged once, after the displays are read, so the card
    /// never flashes a wrong state at launch.
    @Test(arguments: [
        (true, true, LidState.open, [DeskModeState]()),
        (false, true, .open, [.unavailable(.needsDisplay)]),
        (true, false, .closed, [.unavailable(.lidClosed)]),
    ])
    func `launch publishes Desk Mode at most once`(external: Bool, builtIn: Bool, lid: LidState, expected: [DeskModeState]) {
        let rig = SystemRig(facts: (external ? [DisplayFixtures.lg] : []) + (builtIn ? [DisplayFixtures.builtIn] : []))
        rig.system.lidState = lid
        var published: [DeskModeState] = []
        let subscription = rig.model.deskMode.$state.dropFirst().sink { published.append($0) }
        rig.controller.start()
        #expect(published == expected)
        subscription.cancel()
    }

    // MARK: Displays and availability

    @Test func `unplugging the only external needs a display, replugging turns it back off`() {
        let rig = SystemRig()
        rig.controller.start()

        rig.displays.facts = [DisplayFixtures.builtIn]
        rig.changes.send()
        #expect(rig.model.deskMode.state == .unavailable(.needsDisplay))
        #expect(rig.model.system.externals.isEmpty)
        #expect(rig.segments == [.builtInOnly, .onPower])

        rig.displays.facts = DisplayFixtures.thisMac
        rig.changes.send()
        #expect(rig.model.deskMode.state == .off)
        #expect(rig.segments == [.lidOpen, .displayCount(2), .onPower])
    }

    @Test func `screen sleep holds the count, and after wake an inactive external stops counting`() {
        let rig = SystemRig()
        rig.controller.start()
        var inactive = DisplayFixtures.lg
        inactive.isActive = false

        rig.events.send(.screensDidSleep)
        rig.displays.facts = [inactive, DisplayFixtures.builtIn]
        rig.changes.send()
        #expect(rig.model.deskMode.state == .off)

        rig.events.send(.screensDidWake)
        #expect(rig.model.deskMode.state == .unavailable(.needsDisplay))
    }

    @Test func `a closed lid keeps the built-in listed and never reads its brightness`() {
        let rig = SystemRig()
        rig.controller.start()

        rig.system.lidState = .closed
        rig.displays.facts = [DisplayFixtures.lg]
        rig.events.send(.lid)
        rig.changes.send()
        #expect(rig.model.deskMode.state == .unavailable(.lidClosed))
        #expect(rig.model.system.builtIn == DisplayFixtures.builtInDescriptor)
        #expect(!rig.controller.inventory.builtInOnline)
        #expect(rig.segments == [.lidClosed, .displayCount(1), .onPower])

        let readsBefore = rig.brightness.reads.count
        rig.controller.popoverWillShow()
        rig.controller.refreshBrightness()
        #expect(rig.brightness.reads.count == readsBefore)
        #expect(rig.brightness.observed == nil)
        rig.controller.popoverDidClose()

        rig.system.lidState = .open
        rig.displays.facts = DisplayFixtures.thisMac
        rig.events.send(.lid)
        rig.changes.send()
        #expect(rig.model.deskMode.state == .off)
    }

    @Test(arguments: [
        ("Mac15,3", LidState.open, true, DeskModeState.UnavailableReason.unsupportedMac),
        ("Mac17,9", .open, false, .unsupportedSystem),
        ("Mac17,9", .unknown, true, .unsupportedMac),
    ])
    func `unsupported Macs and systems are reported`(modelIdentifier: String, lid: LidState, callsPresent: Bool, expected: DeskModeState.UnavailableReason) {
        let rig = SystemRig()
        rig.controller.start()
        rig.system.modelIdentifier = modelIdentifier
        rig.system.lidState = lid
        rig.system.deskModeCallsPresent = callsPresent
        rig.controller.refreshSystem()
        #expect(rig.model.deskMode.state == .unavailable(expected))
    }

    // Every row differs from FakeSystem's defaults (open, adapter, nominal) in
    // all three readings, so a row only passes if its event really re-reads.
    @Test(arguments: [
        (SystemEvent.lid, LidState.closed, PowerSource.battery(percent: 55), ThermalLevel.fair),
        (.power, .unknown, .battery(percent: 81), .serious),
        (.thermal, .closed, .unknown, .serious),
        (.didWake, .closed, .battery(percent: 40), .fair),
        (.screensDidWake, .unknown, .battery(percent: 12), .critical),
        (.sessionDidBecomeActive, .closed, .battery(percent: nil), .critical),
    ])
    func `system events re-read lid, power and heat`(event: SystemEvent, lid: LidState, power: PowerSource, thermal: ThermalLevel) {
        let rig = SystemRig()
        rig.controller.start()
        rig.system.lidState = lid
        rig.system.powerSource = power
        rig.system.thermalLevel = thermal
        rig.events.send(event)
        #expect(rig.model.system.lid == lid)
        #expect(rig.model.system.power == power)
        #expect(rig.model.system.thermal == thermal)
    }

    @Test func `desk mode on survives availability, and turning it off lands on the reason`() {
        let rig = SystemRig()
        rig.controller.start()

        rig.model.deskMode.setOn(true)
        rig.displays.facts = [DisplayFixtures.builtIn]
        rig.changes.send()
        #expect(rig.model.deskMode.state.isOn)
        #expect(rig.model.deskMode.unavailableReason == .needsDisplay)

        rig.model.deskMode.setOn(false)
        #expect(rig.model.deskMode.state == .unavailable(.needsDisplay))
    }

    // MARK: Brightness

    @Test func `the open popover follows the built-in's brightness, and closing stops it`() async throws {
        let rig = SystemRig(pollInterval: 0.05)
        rig.controller.start()

        rig.brightness.levels[1] = 0.8
        rig.controller.popoverWillShow()
        #expect(rig.brightness.observed == 1)
        #expect(rig.controller.isPolling)
        #expect(abs(rig.model.brightness.position - 80) < 1e-9)

        rig.brightness.levels[1] = 0.3
        rig.brightness.sendChange()
        #expect(abs(rig.model.brightness.position - 30) < 1e-9)

        rig.brightness.levels[1] = 0.6
        let readsBeforePoll = rig.brightness.reads.count
        // Wait for the 0.05 s poll, however late a busy main thread runs it
        // (other suites run beside this one on CI); ends as soon as it lands.
        let deadline = ContinuousClock.now + .seconds(5)
        while abs(rig.model.brightness.position - 60) >= 1e-9, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(rig.brightness.reads.count > readsBeforePoll)
        #expect(abs(rig.model.brightness.position - 60) < 1e-9)

        rig.controller.popoverDidClose()
        #expect(rig.brightness.observed == nil)
        #expect(!rig.controller.isPolling)
        let readsAfterClose = rig.brightness.reads.count
        try await Task.sleep(for: .milliseconds(200))
        #expect(rig.brightness.reads.count == readsAfterClose)
    }

    @Test func `a re-issued built-in ID is observed again`() {
        let rig = SystemRig()
        rig.controller.start()
        rig.controller.popoverWillShow()
        #expect(rig.brightness.observed == 1)

        var reissued = DisplayFixtures.builtIn
        reissued.displayID = 7
        rig.brightness.levels[7] = 0.9
        rig.displays.facts = [DisplayFixtures.lg, reissued]
        rig.changes.send()
        #expect(rig.brightness.observed == 7)
        #expect(rig.brightness.observeCount == 2)
        #expect(rig.brightness.reads.last == 7)
        #expect(abs(rig.model.brightness.position - 90) < 1e-9)

        rig.changes.send()
        #expect(rig.brightness.observeCount == 2)
        rig.controller.popoverDidClose()
    }

    @Test func `reads wait 2 s after a user edit, then snap back`() {
        let rig = SystemRig()
        rig.controller.start()
        rig.controller.popoverWillShow()
        let brightness = rig.model.brightness

        brightness.position = 130
        rig.brightness.levels[1] = 0.3
        rig.clock.now += 1.9
        rig.brightness.sendChange()
        #expect(brightness.position == 130)

        rig.clock.now += 0.2
        rig.controller.refreshBrightness()
        #expect(abs(brightness.position - 30) < 1e-9)
        rig.controller.popoverDidClose()
    }

    @Test func `a read is not a user edit`() {
        let rig = SystemRig()
        rig.controller.start()
        let brightness = rig.model.brightness
        #expect(brightness.lastUserEdit == nil)

        brightness.applyRead(BrightnessLevelReading(level: 0.2))
        #expect(abs(brightness.position - 20) < 1e-9)
        #expect(brightness.lastUserEdit == nil)

        rig.clock.now += 5
        brightness.position = 45
        #expect(brightness.lastUserEdit == rig.clock.now)
    }

    @Test func `a reference preset removes the Boost range`() {
        var preset = DisplayFixtures.builtIn
        preset.referenceHeadroom = 2
        let rig = SystemRig(facts: [DisplayFixtures.lg, preset])
        rig.controller.start()
        #expect(rig.controller.inventory.builtInPresetLocksBrightness)
        #expect(!rig.model.brightness.scale.canBoost)
        #expect(rig.model.brightness.scale.ceilingNits == 600)
    }

    @Test func `live reads never show the boost glyph`() {
        let rig = SystemRig()
        var icons: [MenuBarIconState] = []
        let subscription = StatusItemController.iconStates(model: rig.model, iconShowsState: Just(true).eraseToAnyPublisher())
            .sink { icons.append($0) }
        rig.controller.start()
        rig.controller.popoverWillShow()
        for level in [1.0, 1.6, 0.05, 1.3] {
            rig.brightness.levels[1] = level
            rig.brightness.sendChange()
        }
        #expect(rig.model.brightness.position == 100)
        #expect(icons == [.normal])
        rig.controller.popoverDidClose()
        subscription.cancel()
    }

    // MARK: Stop

    @Test func `stop stops every source`() {
        let rig = SystemRig()
        rig.controller.start()
        rig.controller.popoverWillShow()
        rig.controller.stop()

        #expect(!rig.changes.isRunning)
        #expect(!rig.events.isRunning)
        #expect(!rig.controller.isPolling)
        #expect(rig.brightness.observed == nil)

        // A popover opened after stop reads nothing.
        let reads = rig.brightness.reads.count
        rig.controller.popoverDidClose()
        rig.controller.popoverWillShow()
        #expect(rig.brightness.reads.count == reads)
        #expect(!rig.controller.isPolling)
        rig.controller.stop()
    }

    @Test func `names for unnamed displays are localized`() {
        #expect(DisplayNames.localized == DisplayFixtures.names)
    }
}
