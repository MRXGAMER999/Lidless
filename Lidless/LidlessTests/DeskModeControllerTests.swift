import Combine
import Foundation
import LidlessCore
import Testing
@testable import Lidless

/// `DeskModeController` against fakes: which service calls a user action or a
/// reading turns into, and in what order. The decisions themselves are
/// `DeskModeMachine`'s, tested in LidlessCoreTests.
@MainActor
struct DeskModeControllerTests {
    typealias Call = DeskModeCallLog.Call
    let lgUUID = DisplayFixtures.lgUUID
    let builtInUUID = DisplayFixtures.builtInUUID

    // MARK: Turning on

    @Test func `turning on holds the activity, arms the sidecar and writes the marker before the disable`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.controller.setOn(true)

        #expect(rig.log.take() == [
            .hold(true),
            .arm(1, method: .disconnect),
            .writeMarker(.engaging),
            .disable(1, uuid: builtInUUID, method: .disconnect),
            .hang(true),
        ])
        #expect(rig.marker.marker == CrashMarker(
            stage: .engaging, method: .disconnect, builtInDisplayID: 1, builtInUUID: builtInUUID,
            pid: getpid(), bootSessionUUID: "boot-1", writtenAt: DeskModeRig.since
        ))
        #expect(rig.model.deskMode.state == .switching(toOn: true))
        #expect(rig.controller.isTicking)
    }

    @Test func `the popover switch goes through the controller`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.model.deskMode.isOn = true
        #expect(rig.builtIn.pendingDisables == 1)
        #expect(rig.model.deskMode.state == .switching(toOn: true))
    }

    @Test func `a refused turn-on changes nothing`() {
        let rig = DeskModeRig()
        rig.connect([DisplayFixtures.builtIn])
        rig.controller.availabilityDidChange(.needsDisplay)
        _ = rig.log.take()

        rig.model.deskMode.isOn = true
        #expect(rig.log.take() == [])
        #expect(rig.model.deskMode.state == .unavailable(.needsDisplay))
        #expect(!rig.controller.isTicking)
    }

    @Test func `the prompt shows on the external and keep makes it stick`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.controller.setOn(true)
        _ = rig.log.take()

        rig.builtIn.finishDisable(true)
        #expect(rig.log.take() == [.deadline(1_015), .show(deadline: 1_015, total: 15, onDisplayUUID: lgUUID)])
        #expect(rig.model.deskMode.state == .on(since: DeskModeRig.since, trigger: .manual))
        // The disconnect takes the built-in out of the list. Without this reading
        // the machine would still see the panel online once the settle time is
        // over, and stand down as if a lid cycle had brought it back.
        rig.controller.displaysDidChange(facts: DeskModeRig.builtInOff, lid: .open, power: .adapter)
        #expect(rig.log.take() == [])

        rig.advance(4)
        rig.confirmation.pressKeep()
        #expect(rig.log.take() == [.hide, .deadline(nil), .writeMarker(.active)])
        #expect(rig.marker.marker?.stage == .active)
        #expect(rig.model.deskMode.state == .on(since: DeskModeRig.since, trigger: .manual))
        #expect(rig.hang.isArmed)
        #expect(rig.controller.isTicking)
    }

    @Test func `without asking, a verified disable is active at once`() {
        var settings = DeskModeSettings.defaults
        settings.askBeforeKeeping = false
        let rig = DeskModeRig(settings: settings)
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.setOn(true)
        _ = rig.log.take()

        rig.builtIn.finishDisable(true)
        #expect(rig.log.take() == [.writeMarker(.active)])
        #expect(!rig.confirmation.isShown)
    }

    @Test func `a prompt nobody answers turns the screen back on`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.controller.setOn(true)
        rig.builtIn.finishDisable(true)
        _ = rig.log.take()

        rig.advance(15)
        rig.controller.tick()
        #expect(rig.log.take() == [.hide, .deadline(nil), .enable(1)])
        #expect(rig.model.deskMode.state == .switching(toOn: false))

        rig.builtIn.finishEnable(true)
        #expect(rig.log.take() == [.disarm, .clearMarker, .hold(false), .notify(.confirmationTimedOut), .hang(false)])
        #expect(rig.model.deskMode.state == .off)
        #expect(!rig.controller.isTicking)
    }

    @Test func `turn back on in the prompt restores`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.controller.setOn(true)
        rig.builtIn.finishDisable(true)
        _ = rig.log.take()

        rig.confirmation.pressRevert()
        #expect(rig.log.take() == [.hide, .deadline(nil), .enable(1)])
        rig.builtIn.finishEnable(true)
        #expect(rig.log.take() == [.disarm, .clearMarker, .hold(false), .notify(.declined), .hang(false)])
    }

    @Test func `the prompt's deadline has its own tick`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.controller.setOn(true)
        #expect(!rig.controller.isWaitingForDeadline)

        rig.builtIn.finishDisable(true)
        #expect(rig.controller.isWaitingForDeadline)
        rig.confirmation.pressKeep()
        #expect(!rig.controller.isWaitingForDeadline)
    }

    @Test func `turning back on after an automatic engage keeps the rule from firing again`() {
        let rig = DeskModeRig()
        rig.connect([DisplayFixtures.builtIn])
        rig.controller.availabilityDidChange(.needsDisplay)
        rig.connect()
        rig.advance(3)
        rig.controller.tick()
        rig.builtIn.finishDisable(true)
        #expect(rig.model.deskMode.state == .on(since: DeskModeRig.since, trigger: .automatic(displayName: "LG ULTRAGEAR")))
        // The disable's own reconfiguration drops the LG from one reading, so
        // the rule sees it arrive again.
        rig.controller.displaysDidChange(facts: [DisplayFixtures.builtIn], lid: .open, power: .adapter)
        rig.controller.displaysDidChange(facts: DeskModeRig.builtInOff, lid: .open, power: .adapter)

        rig.confirmation.pressRevert()
        rig.builtIn.finishEnable(true)
        rig.connect()
        rig.advance(10)
        rig.controller.tick()
        #expect(rig.builtIn.pendingDisables == 0)
        #expect(rig.model.deskMode.state == .off)
        #expect(!rig.controller.isTicking)
    }

    @Test func `completions that answer at once keep the commands in order`() {
        let rig = DeskModeRig()
        rig.builtIn.answersAtOnce = true
        rig.connect()
        _ = rig.log.take()

        rig.controller.setOn(true)
        #expect(rig.log.take() == [
            .hold(true),
            .arm(1, method: .disconnect),
            .writeMarker(.engaging),
            .disable(1, uuid: builtInUUID, method: .disconnect),
            .deadline(1_015),
            .show(deadline: 1_015, total: 15, onDisplayUUID: lgUUID),
            .hang(true),
        ])

        rig.confirmation.pressRevert()
        #expect(rig.log.take() == [.hide, .deadline(nil), .enable(1), .disarm, .clearMarker, .hold(false), .notify(.declined), .hang(false)])
        #expect(rig.model.deskMode.state == .off)
    }

    // MARK: The sidecar

    @Test func `without its sidecar Desk Mode never turns the screen off`() {
        let rig = DeskModeRig()
        rig.watchdog.armResult = false
        rig.connect()
        _ = rig.log.take()

        rig.controller.setOn(true)
        let calls = rig.log.take()
        #expect(calls.filter(\.touchesDisplay) == [.enable(1)])
        #expect(rig.builtIn.pendingDisables == 0)

        rig.builtIn.finishEnable(true)
        // Disarmed all the same: a sidecar that didn't start is retried until then.
        #expect(rig.log.take() == [.disarm, .clearMarker, .hold(false), .notify(.engageFailed), .hang(false)])
        #expect(rig.model.deskMode.state == .off)
    }

    @Test func `a failed disable restores and says so`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.controller.setOn(true)
        _ = rig.log.take()

        rig.builtIn.finishDisable(false)
        #expect(rig.log.take() == [.hide, .enable(1)])
        rig.builtIn.finishEnable(true)
        #expect(rig.log.take().contains(.notify(.engageFailed)))
    }

    // MARK: Losing the external

    @Test func `unplugging the last external restores the built-in`() {
        let rig = DeskModeRig()
        rig.turnOnAndKeep()

        rig.advance(3)
        rig.controller.displaysDidChange(facts: [], lid: .open, power: .adapter)
        // One reading could be mid-reconfiguration; the next tick confirms it.
        #expect(rig.log.take() == [])
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.log.take() == [.hide, .enable(1)])

        rig.builtIn.finishEnable(true)
        #expect(rig.log.take() == [.disarm, .clearMarker, .hold(false), .notify(.externalLost(displayName: "LG ULTRAGEAR")), .hang(false)])
        #expect(rig.model.deskMode.state == .off)
    }

    @Test func `ticks re-read the displays, so a missed callback still restores`() {
        let system = SystemRig()
        defer { system.cleanUp() }
        let desk = DeskModeRig(model: system.model)
        system.controller.deskMode = desk.controller
        system.controller.start()
        desk.controller.setOn(true)
        desk.builtIn.finishDisable(true)
        system.displays.facts = DeskModeRig.builtInOff
        system.changes.send()
        desk.confirmation.pressKeep()
        _ = desk.log.take()

        // Unplugged, and no reconfiguration callback arrives.
        system.displays.facts = []
        desk.advance(3)
        let reads = system.displays.snapshotCount
        desk.controller.tick()
        #expect(system.displays.snapshotCount == reads + 1)
        desk.advance(1)
        desk.controller.tick()
        #expect(desk.log.take().filter(\.touchesDisplay) == [.enable(1)])
    }

    @Test func `ticks read nothing while Desk Mode is off`() {
        let system = SystemRig()
        defer { system.cleanUp() }
        let desk = DeskModeRig(model: system.model)
        system.controller.deskMode = desk.controller
        system.controller.start()

        let reads = system.displays.snapshotCount
        desk.controller.tick()
        #expect(system.displays.snapshotCount == reads)
    }

    @Test func `display sleep never ends Desk Mode`() {
        let rig = DeskModeRig()
        rig.turnOnAndKeep()
        rig.advance(3)

        rig.controller.handle(.screensDidSleep)
        // Asleep displays can even drop out of the online list.
        rig.controller.displaysDidChange(facts: [], lid: .open, power: .adapter)
        rig.advance(60)
        rig.controller.tick()
        #expect(rig.log.take() == [])
        #expect(rig.model.deskMode.state.isOn)
    }

    // MARK: Panic, quit, power off

    @Test func `panic restores from active`() {
        let rig = DeskModeRig()
        rig.turnOnAndKeep()

        rig.controller.panic()
        #expect(rig.log.take() == [.hide, .enable(1)])
        rig.builtIn.finishEnable(true)
        // The user pressed it: no notification.
        #expect(rig.log.take() == [.disarm, .clearMarker, .hold(false), .hang(false)])
    }

    @Test func `panic sends an enable even when Desk Mode is off`() {
        let rig = DeskModeRig()
        rig.connect()
        _ = rig.log.take()

        rig.controller.panic()
        #expect(rig.log.take().filter(\.touchesDisplay) == [.enable(1)])
    }

    @Test func `quitting restores synchronously and stops everything`() {
        let rig = DeskModeRig()
        rig.turnOnAndKeep()

        rig.controller.terminate()
        #expect(rig.log.take() == [.hide, .enableNow(1), .disarm, .clearMarker, .hold(false), .hang(false)])
        #expect(rig.builtIn.pendingEnables == 0)
        #expect(!rig.controller.isTicking)
        #expect(rig.marker.marker == nil)

        rig.model.deskMode.isOn = true
        rig.controller.panic()
        rig.controller.terminate()
        #expect(rig.log.take() == [])
        #expect(rig.model.deskMode.state == .off)
    }

    @Test func `a restore at quit that isn't confirmed leaves the sidecar armed and the marker`() {
        let rig = DeskModeRig()
        rig.turnOnAndKeep()
        rig.builtIn.enableNowResult = false

        rig.controller.terminate()
        #expect(rig.log.take() == [.hide, .enableNow(1), .hang(false)])
        #expect(rig.marker.marker?.stage == .active)
    }

    @Test func `a restore at power off that isn't confirmed keeps trying, armed and awake`() {
        let rig = DeskModeRig()
        rig.turnOnAndKeep()
        rig.builtIn.enableNowResult = false

        rig.controller.handle(.willPowerOff)
        let calls = rig.log.take()
        #expect(calls.filter(\.touchesDisplay) == [.enableNow(1), .enable(1)])
        #expect(!calls.contains(.disarm))
        #expect(!calls.contains(.clearMarker))
        #expect(!calls.contains(.hold(false)))
        #expect(rig.model.deskMode.state == .switching(toOn: false))
        #expect(rig.hang.isArmed)

        rig.builtIn.finishEnable(true)
        #expect(rig.log.take() == [.disarm, .clearMarker, .hold(false), .hang(false)])
        #expect(rig.marker.marker == nil)
        #expect(rig.model.deskMode.state == .off)
    }

    @Test func `launch recovery that failed hands the panel to the machine`() {
        let rig = DeskModeRig()
        rig.marker.marker = CrashMarker(
            stage: .active, method: .disconnect, builtInDisplayID: 1, builtInUUID: builtInUUID,
            pid: 99, bootSessionUUID: "boot-1", writtenAt: DeskModeRig.since
        )
        rig.connect(DeskModeRig.builtInOff)
        _ = rig.log.take()

        rig.controller.resumeRestore(displayID: 1, uuid: builtInUUID, method: .disconnect)
        #expect(rig.log.take() == [.hold(true), .arm(1, method: .disconnect), .writeMarker(.engaging), .enable(1), .hang(true)])
        #expect(rig.model.deskMode.state == .switching(toOn: false))

        // Retried until the panel is back, and the marker stays until then.
        rig.builtIn.finishEnable(false)
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.log.take() == [.enable(1)])
        #expect(rig.marker.marker != nil)

        rig.builtIn.finishEnable(true)
        #expect(rig.log.take() == [.disarm, .clearMarker, .hold(false), .hang(false)])
        #expect(rig.marker.marker == nil)
        #expect(rig.model.deskMode.state == .off)
    }

    @Test func `quitting with Desk Mode off touches nothing`() {
        let rig = DeskModeRig()
        rig.connect()
        _ = rig.log.take()
        rig.controller.terminate()
        #expect(rig.log.take() == [])
    }

    @Test func `power off restores synchronously and Desk Mode still works after`() {
        let rig = DeskModeRig()
        rig.turnOnAndKeep()

        rig.controller.handle(.willPowerOff)
        #expect(rig.log.take() == [.hide, .enableNow(1), .disarm, .clearMarker, .hold(false), .hang(false)])
        #expect(rig.model.deskMode.state == .off)

        // Logging out was cancelled.
        rig.connect()
        rig.controller.setOn(true)
        #expect(rig.builtIn.pendingDisables == 1)
    }

    // MARK: Sleep

    @Test func `no switch calls between willSleep and didWake`() {
        let rig = DeskModeRig()
        rig.turnOnAndKeep()
        rig.advance(3)

        rig.controller.handle(.willSleep)
        rig.controller.handle(.screensDidSleep)
        rig.controller.displaysDidChange(facts: [], lid: .open, power: .adapter)
        rig.controller.systemDidChange(lid: .closed, power: .battery(percent: 80))
        rig.advance(600)
        rig.controller.tick()
        rig.controller.handle(.didWake)
        #expect(rig.log.calls.filter(\.touchesDisplay).isEmpty)

        // After wake, once the reading settles, the panel comes back
        // ("Keep Desk Mode after wake" is off).
        rig.controller.handle(.screensDidWake)
        rig.controller.displaysDidChange(facts: DeskModeRig.builtInOff, lid: .open, power: .adapter)
        rig.advance(3)
        rig.controller.tick()
        #expect(rig.log.take().filter(\.touchesDisplay) == [.enable(1)])
    }

    // MARK: Ticks and the hang watchdog

    @Test func `ticks and the hang watchdog run only while Desk Mode is not idle`() {
        let rig = DeskModeRig()
        rig.connect()
        #expect(!rig.controller.isTicking)
        #expect(!rig.hang.isArmed)

        rig.controller.setOn(true)
        #expect(rig.controller.isTicking)
        #expect(rig.hang.isArmed)

        rig.builtIn.finishDisable(true)
        rig.controller.setOn(false)
        rig.builtIn.finishEnable(true)
        #expect(!rig.controller.isTicking)
        #expect(!rig.hang.isArmed)
        #expect(rig.log.calls.filter { if case .hang = $0 { true } else { false } } == [.hang(true), .hang(false)])
    }

    // MARK: Other displays' modes

    @Test func `the mode watch brackets every verified switch`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.controller.setOn(true)
        #expect(rig.modeWatch.calls == [.willSwitch])
        rig.builtIn.finishDisable(true)
        #expect(rig.modeWatch.calls == [.willSwitch, .didSwitch])

        rig.controller.setOn(false)
        #expect(rig.modeWatch.calls == [.willSwitch, .didSwitch, .willSwitch])
        rig.builtIn.finishEnable(true)
        #expect(rig.modeWatch.calls == [.willSwitch, .didSwitch, .willSwitch, .didSwitch])
    }

    @Test func `a failed disable is never compared`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.controller.setOn(true)
        rig.builtIn.finishDisable(false)
        #expect(rig.modeWatch.calls.first == .willSwitch)
        #expect(!rig.modeWatch.calls.contains(.didSwitch))
    }

    // MARK: The plug-in rule

    @Test func `plugging in a display turns Desk Mode on after the rule's delay`() {
        let rig = DeskModeRig()
        rig.connect([DisplayFixtures.builtIn])
        rig.controller.availabilityDidChange(.needsDisplay)

        rig.connect()
        #expect(rig.controller.isTicking)
        rig.advance(2)
        rig.controller.tick()
        #expect(rig.builtIn.pendingDisables == 0)

        rig.advance(1)
        rig.controller.tick()
        #expect(rig.builtIn.pendingDisables == 1)
        rig.builtIn.finishDisable(true)
        #expect(rig.model.deskMode.state == .on(since: DeskModeRig.since, trigger: .automatic(displayName: "LG ULTRAGEAR")))
        #expect(rig.confirmation.isShown)
    }

    @Test func `displays present at launch never fire the rule`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.advance(10)
        rig.controller.tick()
        #expect(rig.builtIn.pendingDisables == 0)
        #expect(!rig.controller.isTicking)
    }

    @Test func `a display that drops out during display sleep isn't newly plugged in`() {
        let rig = DeskModeRig()
        rig.connect()

        rig.controller.handle(.screensDidSleep)
        rig.connect([DisplayFixtures.builtIn])
        rig.controller.handle(.screensDidWake)
        rig.connect()
        rig.advance(10)
        rig.controller.tick()
        #expect(rig.builtIn.pendingDisables == 0)
    }

    @Test func `switching Desk Mode off cancels the rule for the display connected now`() {
        let rig = DeskModeRig()
        rig.connect([DisplayFixtures.builtIn])
        rig.connect()
        rig.controller.setOn(false)
        rig.advance(10)
        rig.controller.tick()
        #expect(rig.builtIn.pendingDisables == 0)
        #expect(!rig.controller.isTicking)
    }

    // MARK: Black out and preferences

    @Test func `the method comes from the preferences and reaches the switch`() {
        let rig = DeskModeRig()
        defer { rig.cleanUp() }
        rig.model.preferences.deskMode.method = .blackout
        #expect(rig.controller.machine.configuration.method == .blackout)

        rig.connect()
        rig.controller.setOn(true)
        #expect(rig.builtIn.method == .blackout)
        #expect(rig.log.take().filter(\.touchesDisplay) == [.disable(1, uuid: builtInUUID, method: .blackout)])
    }

    @Test func `a lost black out cover ends Desk Mode quietly`() {
        var settings = DeskModeSettings.defaults
        settings.method = .blackout
        let rig = DeskModeRig(settings: settings)
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.setOn(true)
        rig.builtIn.finishDisable(true)
        rig.confirmation.pressKeep()
        _ = rig.log.take()

        rig.controller.coverLost()
        rig.builtIn.finishEnable(true)
        let calls = rig.log.take()
        #expect(calls.filter(\.touchesDisplay) == [.enable(1)])
        #expect(!calls.contains { if case .notify = $0 { true } else { false } })
        #expect(rig.model.deskMode.state == .off)
    }

    @Test func `settings reach the machine`() {
        let rig = DeskModeRig()
        defer { rig.cleanUp() }
        rig.model.preferences.deskMode.askBeforeKeeping = false
        rig.model.preferences.deskMode.keepAfterWake = true
        let configuration = rig.controller.machine.configuration
        #expect(!configuration.askBeforeKeeping)
        #expect(configuration.keepAfterWake)
        #if DEBUG
        // Off unless the launch argument or defaults key asks for one.
        #expect(configuration.maxDuration == DeskModeController.debugTimeLimit())
        #else
        #expect(configuration.maxDuration == nil)
        #endif
    }

    /// Debug runs from Xcode used to end Desk Mode after 5 minutes by
    /// themselves; the limit is opt-in now.
    @Test func `the debug time limit is off unless asked for`() throws {
        let suite = "DeskModeControllerTests.timeLimit.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DeskModeController.debugTimeLimit(defaults) == nil)
        defaults.set(300, forKey: DeskModeController.debugTimeLimitKey)
        #expect(DeskModeController.debugTimeLimit(defaults) == 300)
        defaults.set(0, forKey: DeskModeController.debugTimeLimitKey)
        #expect(DeskModeController.debugTimeLimit(defaults) == nil)
        defaults.set(-5, forKey: DeskModeController.debugTimeLimitKey)
        #expect(DeskModeController.debugTimeLimit(defaults) == nil)
        defaults.set("soon", forKey: DeskModeController.debugTimeLimitKey)
        #expect(DeskModeController.debugTimeLimit(defaults) == nil)
    }

    @Test func `a kept Desk Mode outlives the old debug limit`() {
        let rig = DeskModeRig()
        defer { rig.cleanUp() }
        guard rig.controller.machine.configuration.maxDuration == nil else { return } // a developer opted in
        rig.turnOnAndKeep()
        rig.advance(3)
        _ = rig.log.take()
        for _ in 0..<20 {
            rig.advance(60)
            rig.connect(DeskModeRig.builtInOff)
            rig.controller.tick()
        }
        #expect(rig.log.take().filter(\.touchesDisplay).isEmpty)
        #expect(rig.model.deskMode.state.isOn)
    }

    @Test func `a new panic shortcut reaches the popover`() {
        let rig = DeskModeRig()
        defer { rig.cleanUp() }
        let shortcut = KeyShortcut(keyCode: 0x0F, keyLabel: "R", modifiers: [.control, .option, .command])
        rig.model.preferences.shortcuts.panic = shortcut
        #expect(rig.model.deskMode.panicShortcut == shortcut)
    }

    // MARK: Hot keys

    @Test func `the panic key and the Desk Mode key reach the controller`() {
        let rig = DeskModeRig()
        let registrar = FakeHotKeyRegistrar()
        rig.controller.bindHotKeys(.fake(registrar))
        rig.connect()
        _ = rig.log.take()
        #expect(registrar.held[HotKeyID.panic.rawValue] == UInt32(KeyShortcut.defaultPanic.keyCode))
        #expect(registrar.held[HotKeyID.toggleDeskMode.rawValue] == UInt32(KeyShortcut.defaultDeskMode.keyCode))

        #expect(registrar.press(.toggleDeskMode))
        #expect(rig.builtIn.pendingDisables == 1)
        rig.builtIn.finishDisable(true)
        _ = rig.log.take()

        #expect(registrar.press(.panic))
        #expect(rig.log.take().filter(\.touchesDisplay) == [.enable(1)])
    }

    @Test func `clearing the Desk Mode key unregisters it`() {
        let rig = DeskModeRig()
        defer { rig.cleanUp() }
        let registrar = FakeHotKeyRegistrar()
        let center = HotKeyCenter.fake(registrar)
        rig.controller.bindHotKeys(center)
        rig.connect()

        rig.model.preferences.shortcuts.toggleDeskMode = nil
        #expect(registrar.held[HotKeyID.toggleDeskMode.rawValue] == nil)
        #expect(center.registrations[.toggleDeskMode] == nil)
        #expect(!registrar.press(.toggleDeskMode))
        #expect(rig.builtIn.pendingDisables == 0)
        #expect(center.registrations[.panic]?.isRegistered == true)
    }

    @Test func `swapping the two keys keeps both working`() {
        let rig = DeskModeRig()
        defer { rig.cleanUp() }
        let registrar = FakeHotKeyRegistrar()
        let center = HotKeyCenter.fake(registrar)
        rig.controller.bindHotKeys(center)
        rig.connect()
        _ = rig.log.take()

        var swapped = ShortcutSet.defaults
        swapped.panic = .defaultDeskMode
        swapped.toggleDeskMode = .defaultPanic
        rig.model.preferences.shortcuts = swapped
        #expect(registrar.held[HotKeyID.panic.rawValue] == UInt32(KeyShortcut.defaultDeskMode.keyCode))
        #expect(registrar.held[HotKeyID.toggleDeskMode.rawValue] == UInt32(KeyShortcut.defaultPanic.keyCode))
        #expect(center.registrations[.panic]?.isRegistered == true)
        #expect(center.registrations[.toggleDeskMode]?.isRegistered == true)
        #expect(rig.model.deskMode.panicShortcut == .defaultDeskMode)

        #expect(registrar.press(.toggleDeskMode))
        #expect(rig.builtIn.pendingDisables == 1)
        #expect(registrar.press(.panic))
        #expect(rig.log.take().filter(\.touchesDisplay) == [.disable(1, uuid: builtInUUID, method: .disconnect), .enable(1)])
    }

    // MARK: Forced prompt ("Test the safety net", intents before onboarding)

    /// "Ask before keeping it off" switched off, so only a forced prompt asks.
    private static func withoutAsking() -> DeskModeRig {
        var settings = DeskModeSettings.defaults
        settings.askBeforeKeeping = false
        return DeskModeRig(settings: settings)
    }

    @Test func `testing the safety net asks even with asking switched off`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.testSafetyNet()
        #expect(rig.builtIn.pendingDisables == 1)
        #expect(rig.controller.machine.configuration.askBeforeKeeping)
        _ = rig.log.take()

        rig.builtIn.finishDisable(true)
        #expect(rig.log.take() == [.deadline(1_015), .show(deadline: 1_015, total: 15, onDisplayUUID: lgUUID)])
        #expect(rig.model.deskMode.isConfirming)
        // Once the prompt is up the force is spent; the setting is back.
        #expect(!rig.controller.machine.configuration.askBeforeKeeping)
    }

    @Test func `requestTurnOn forcing the prompt is testSafetyNet`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.requestTurnOn(forcePrompt: true)
        rig.builtIn.finishDisable(true)
        #expect(rig.confirmation.isShown)
    }

    @Test func `requestTurnOn without forcing follows the setting`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.requestTurnOn(forcePrompt: false)
        #expect(!rig.controller.machine.configuration.askBeforeKeeping)
        _ = rig.log.take()
        rig.builtIn.finishDisable(true)
        #expect(rig.log.take() == [.writeMarker(.active)])
        #expect(!rig.confirmation.isShown)
        #expect(!rig.model.deskMode.isConfirming)
    }

    /// After the forced engage ended some way, a plain turn-on doesn't ask.
    private static func expectPlainTurnOnDoesNotAsk(_ rig: DeskModeRig) {
        #expect(!rig.controller.machine.configuration.askBeforeKeeping)
        rig.connect()
        rig.controller.setOn(true)
        rig.builtIn.finishDisable(true)
        #expect(!rig.confirmation.isShown)
        #expect(rig.controller.machine.phase != .idle)
    }

    @Test func `a refused test doesn't leave the prompt forced`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        // No external: refused.
        rig.connect([DisplayFixtures.builtIn])
        rig.controller.availabilityDidChange(.needsDisplay)
        rig.controller.testSafetyNet()
        #expect(rig.builtIn.pendingDisables == 0)
        rig.controller.availabilityDidChange(nil)
        Self.expectPlainTurnOnDoesNotAsk(rig)
    }

    @Test func `a test not ready to engage doesn't leave the prompt forced`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        // No reading yet: not ready.
        rig.controller.testSafetyNet()
        #expect(rig.builtIn.pendingDisables == 0)
        Self.expectPlainTurnOnDoesNotAsk(rig)
    }

    @Test func `a test while Desk Mode is busy forces nothing`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.setOn(true)
        rig.controller.testSafetyNet()
        #expect(rig.builtIn.pendingDisables == 1)
        #expect(!rig.controller.machine.configuration.askBeforeKeeping)
        _ = rig.log.take()
        rig.builtIn.finishDisable(true)
        #expect(rig.log.take() == [.writeMarker(.active)])
    }

    @Test func `a failed test disable ends the force`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.testSafetyNet()
        rig.builtIn.finishDisable(false)
        rig.builtIn.finishEnable(true)
        #expect(rig.controller.machine.phase == .idle)
        #expect(!rig.controller.machine.configuration.askBeforeKeeping)
    }

    @Test func `a test disable that times out ends the force`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.testSafetyNet()
        rig.advance(12)
        rig.controller.tick()
        let restoring = if case .restoring(.engageFailed, _, _) = rig.controller.machine.phase { true } else { false }
        #expect(restoring)
        #expect(!rig.controller.machine.configuration.askBeforeKeeping)
    }

    @Test func `panic during a test ends the force`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.testSafetyNet()
        rig.controller.panic()
        #expect(!rig.controller.machine.configuration.askBeforeKeeping)
        rig.builtIn.finishDisable(true)
        rig.builtIn.finishEnable(true)
        #expect(!rig.confirmation.isShown)
    }

    @Test func `quitting during a test ends the force`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.testSafetyNet()
        rig.controller.terminate()
        #expect(!rig.controller.machine.configuration.askBeforeKeeping)
        #expect(rig.log.take().contains(.enableNow(1)))
    }

    @Test func `changing settings during a test keeps the prompt forced`() {
        let rig = Self.withoutAsking()
        defer { rig.cleanUp() }
        rig.connect()
        rig.controller.testSafetyNet()
        rig.model.preferences.deskMode.keepAfterWake = true
        rig.model.preferences.deskMode.askBeforeKeeping = true
        rig.model.preferences.deskMode.askBeforeKeeping = false
        #expect(rig.controller.machine.configuration.askBeforeKeeping)
        #expect(rig.controller.machine.configuration.keepAfterWake)

        rig.builtIn.finishDisable(true)
        #expect(rig.confirmation.isShown)
        #expect(!rig.controller.machine.configuration.askBeforeKeeping)
    }

    // MARK: Whether the prompt is up

    @Test func `isConfirming follows the prompt`() {
        let rig = DeskModeRig()
        rig.connect()
        #expect(!rig.model.deskMode.isConfirming)
        rig.controller.setOn(true)
        #expect(!rig.model.deskMode.isConfirming)
        rig.builtIn.finishDisable(true)
        #expect(rig.model.deskMode.isConfirming)
        rig.confirmation.pressKeep()
        #expect(!rig.model.deskMode.isConfirming)
        #expect(rig.model.deskMode.state == .on(since: DeskModeRig.since, trigger: .manual))
    }

    @Test func `isConfirming is already set when the state turns on`() {
        let rig = DeskModeRig()
        rig.connect()
        var seen: [Bool] = []
        let subscription = rig.model.deskMode.$state.dropFirst().sink { [deskMode = rig.model.deskMode] state in
            // @Published sends before storing; isConfirming is stored by then.
            if case .on = state { seen.append(deskMode.isConfirming) }
        }
        rig.controller.setOn(true)
        rig.builtIn.finishDisable(true)
        subscription.cancel()
        #expect(seen == [true])
    }

    @Test func `isConfirming clears when the prompt is answered with Turn Back On`() {
        let rig = DeskModeRig()
        rig.connect()
        rig.controller.setOn(true)
        rig.builtIn.finishDisable(true)
        rig.confirmation.pressRevert()
        #expect(!rig.model.deskMode.isConfirming)
    }

    // MARK: SystemController hookup

    @Test func `the system controller forwards readings, events and availability`() {
        let system = SystemRig()
        defer { system.cleanUp() }
        let desk = DeskModeRig(model: system.model)
        system.controller.deskMode = desk.controller
        system.controller.start()

        #expect(desk.controller.machine.snapshot.externals.map(\.uuid) == [lgUUID])
        #expect(desk.controller.machine.snapshot.builtInUUID == builtInUUID)
        #expect(desk.controller.machine.availability == nil)

        // No display reads inside willSleep.
        let reads = system.displays.snapshotCount
        system.events.send(.willSleep)
        #expect(system.displays.snapshotCount == reads)
        #expect(desk.controller.machine.snapshot.systemSleeping)
        system.events.send(.didWake)
        #expect(!desk.controller.machine.snapshot.systemSleeping)

        system.displays.facts = [DisplayFixtures.builtIn]
        system.changes.send()
        #expect(desk.controller.machine.snapshot.externals.isEmpty)
        #expect(desk.controller.machine.availability == .needsDisplay)

        system.system.powerSource = .battery(percent: 40)
        system.events.send(.power)
        #expect(desk.controller.machine.snapshot.power == .battery(percent: 40))
    }

    @Test func `the system controller's power-off event restores`() {
        let system = SystemRig()
        defer { system.cleanUp() }
        let desk = DeskModeRig(model: system.model)
        system.controller.deskMode = desk.controller
        system.controller.start()
        desk.controller.setOn(true)
        desk.builtIn.finishDisable(true)
        _ = desk.log.take()

        system.events.send(.willPowerOff)
        #expect(desk.log.take().filter(\.touchesDisplay) == [.enableNow(1)])
    }
}

/// `PreferencesStore` against a private UserDefaults suite.
@MainActor
struct PreferencesStoreTests {
    @Test func `settings and shortcuts survive a relaunch`() throws {
        let name = "PreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let store = PreferencesStore(defaults: defaults)
        #expect(store.deskMode == .defaults)
        #expect(store.shortcuts == .defaults)
        store.deskMode.method = .blackout
        store.deskMode.rule.delaySeconds = 10
        store.shortcuts.toggleDeskMode = nil

        let reloaded = PreferencesStore(defaults: defaults)
        #expect(reloaded.deskMode == store.deskMode)
        #expect(reloaded.shortcuts.toggleDeskMode == nil)
        #expect(reloaded.shortcuts.panic == .defaultPanic)
    }

    @Test func `damaged values fall back to the defaults`() throws {
        let name = "PreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("nonsense".utf8), forKey: PreferencesStore.deskModeKey)
        defaults.set(Data("{}".utf8), forKey: PreferencesStore.shortcutsKey)

        let store = PreferencesStore(defaults: defaults)
        #expect(store.deskMode == .defaults)
        #expect(store.shortcuts == .defaults)
    }

    @Test func `general settings survive a relaunch`() throws {
        let name = "PreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let store = PreferencesStore(defaults: defaults)
        #expect(store.general == .defaults)
        store.general.onboardingCompleted = true
        store.general.iconShowsState = false

        let reloaded = PreferencesStore(defaults: defaults)
        #expect(reloaded.general == GeneralSettings(iconShowsState: false, onboardingCompleted: true, autoUpdate: true))
    }

    @Test func `an older general save gets the defaults for what it lacks`() throws {
        let name = "PreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"onboardingCompleted":true}"#.utf8), forKey: PreferencesStore.generalKey)

        let store = PreferencesStore(defaults: defaults)
        #expect(store.general == GeneralSettings(iconShowsState: true, onboardingCompleted: true, autoUpdate: true))
    }

    @Test func `an unchanged value is not written`() throws {
        let name = "PreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let store = PreferencesStore(defaults: defaults)
        store.deskMode = .defaults
        #expect(defaults.data(forKey: PreferencesStore.deskModeKey) == nil)
    }
}
