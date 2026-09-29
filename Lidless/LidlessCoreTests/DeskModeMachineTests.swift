import Foundation
import Testing
@testable import LidlessCore

/// Readings of this Mac (Mac17,9 + LG ULTRAGEAR) in each situation Desk Mode meets.
private enum Desk {
    typealias Fixtures = DisplayFixtures

    static func reading(
        _ facts: [DisplayFacts], lid: LidState = .open, screensAsleep: Bool = false,
        systemSleeping: Bool = false, sessionActive: Bool = true
    ) -> DeskModeSnapshot {
        DeskModeSnapshot(
            facts: facts, previous: atDesk, lid: lid, screensAsleep: screensAsleep,
            systemSleeping: systemSleeping, sessionActive: sessionActive, power: .adapter, names: Fixtures.names
        )
    }

    /// Lid open, the LG plugged in and awake, the panel on.
    static let atDesk = DeskModeSnapshot(
        facts: Fixtures.thisMac, previous: nil, lid: .open, screensAsleep: false,
        systemSleeping: false, sessionActive: true, power: .adapter, names: Fixtures.names
    )
    /// The panel switched off: only the LG is online.
    static let panelOff = reading([Fixtures.lg])
    /// The LG unplugged while the panel is off.
    static let unplugged = reading([])
    /// Display sleep: the LG is still online but inactive and asleep.
    static let screensAsleep = reading([asleep(Fixtures.lg)], screensAsleep: true)
    /// The panel came back by itself (a lid cycle, another tool).
    static let panelBack = reading(Fixtures.thisMac)

    static let mirroredBuiltIn: DisplayFacts = {
        var facts = Fixtures.builtIn
        facts.isInMirrorSet = true
        return facts
    }()

    static func asleep(_ facts: DisplayFacts) -> DisplayFacts {
        var facts = facts
        facts.isActive = false
        facts.isAsleep = true
        return facts
    }
}

/// A machine plus a monotonic clock.
private struct Rig {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static let uuid = DisplayFixtures.builtInUUID
    static let enable = DeskModeCommand.enable(displayID: 1, uuid: uuid, method: .disconnect)
    static let restore: [DeskModeCommand] = [.hideConfirmation, enable]
    /// Leaving the prompt also clears the sidecar's deadline.
    static let restoreFromPrompt: [DeskModeCommand] = [.hideConfirmation, .watchdogDeadline(nil), enable]
    static let standDown: [DeskModeCommand] = [.disarmWatchdog, .clearMarker, .holdActivity(false)]
    static let engage: [DeskModeCommand] = [
        .holdActivity(true),
        .armWatchdog(displayID: 1, uuid: uuid, method: .disconnect),
        .writeMarker(.engaging),
        .disable(displayID: 1, uuid: uuid, method: .disconnect),
    ]
    static let noPrompt = DeskModeMachine.Configuration(askBeforeKeeping: false)

    var machine: DeskModeMachine
    var now: TimeInterval = 1000

    init(_ configuration: DeskModeMachine.Configuration = .init(), snapshot: DeskModeSnapshot = Desk.atDesk, availability: DeskModeState.UnavailableReason? = nil) {
        machine = DeskModeMachine(configuration: configuration, snapshot: snapshot, availability: availability)
    }

    var phase: DeskModeMachine.Phase { machine.phase }
    var state: DeskModeState { machine.state }

    var restoreReason: DeskModeRestoreReason? {
        if case .restoring(let reason, _, _) = phase { return reason }
        return nil
    }

    var isConfirming: Bool {
        if case .confirming = phase { return true }
        return false
    }

    var isActive: Bool {
        if case .active = phase { return true }
        return false
    }

    @discardableResult
    mutating func send(_ event: DeskModeEvent) -> [DeskModeCommand] {
        machine.handle(event, now: now, date: Self.date)
    }

    @discardableResult
    mutating func tick(after seconds: TimeInterval) -> [DeskModeCommand] {
        now += seconds
        return send(.tick)
    }

    /// Turns Desk Mode on and verifies the disable at `now`; the list then shows the panel gone.
    mutating func engage(_ trigger: DeskModeState.Trigger = .manual) {
        send(.turnOn(trigger: trigger))
        send(.disableFinished(succeeded: true))
        send(.snapshot(Desk.panelOff))
    }

    /// Engages, answers the prompt with Keep if there is one, and waits out the settle window.
    mutating func activate() {
        engage()
        if isConfirming { send(.keep) }
        tick(after: machine.configuration.settleTime)
    }
}

struct DeskModeMachineTests {
    // MARK: Turning on

    @Test func `turning on without the prompt goes straight to active`() {
        var rig = Rig(Rig.noPrompt)
        #expect(rig.send(.turnOn(trigger: .manual)) == Rig.engage)
        #expect(rig.phase == .engaging(trigger: .manual, method: .disconnect, startedAt: 1000))
        #expect(rig.state == .switching(toOn: true))
        rig.now = 1003
        #expect(rig.send(.disableFinished(succeeded: true)) == [.writeMarker(.active)])
        #expect(rig.phase == .active(trigger: .manual, method: .disconnect, since: Rig.date, engagedAt: 1003))
        #expect(rig.state == .on(since: Rig.date, trigger: .manual))
        #expect(rig.send(.snapshot(Desk.panelOff)).isEmpty)
        #expect(rig.tick(after: 30).isEmpty)
        #expect(rig.isActive)
    }

    @Test func `turning on with the prompt shows it on the external`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        rig.now = 1003
        #expect(rig.send(.disableFinished(succeeded: true)) == [
            .watchdogDeadline(1018),
            .showConfirmation(deadline: 1018, onDisplayUUID: DisplayFixtures.lgUUID),
        ])
        #expect(rig.phase == .confirming(trigger: .manual, method: .disconnect, since: Rig.date, deadline: 1018))
        #expect(rig.state == .on(since: Rig.date, trigger: .manual))
    }

    @Test func `the plug-in rule always asks, even with the prompt switched off`() {
        var rig = Rig(Rig.noPrompt)
        let trigger = DeskModeState.Trigger.automatic(displayName: "LG ULTRAGEAR")
        rig.send(.turnOn(trigger: trigger))
        let commands = rig.send(.disableFinished(succeeded: true))
        #expect(commands.contains(.showConfirmation(deadline: 1015, onDisplayUUID: DisplayFixtures.lgUUID)))
        #expect(rig.state == .on(since: Rig.date, trigger: trigger))
    }

    @Test func `the prompt goes to the main external first`() {
        var other = DisplayFixtures.lg
        other.displayID = 3
        other.uuid = "OTHER"
        other.isMain = false
        other.originX = -2560
        var rig = Rig(snapshot: Desk.reading([other, DisplayFixtures.lg, DisplayFixtures.builtIn]))
        rig.send(.turnOn(trigger: .manual))
        #expect(rig.send(.disableFinished(succeeded: true)).contains(.showConfirmation(deadline: 1015, onDisplayUUID: DisplayFixtures.lgUUID)))
    }

    @Test func `black out carries its method in every command`() {
        var rig = Rig(.init(method: .blackout, askBeforeKeeping: false))
        #expect(rig.send(.turnOn(trigger: .manual)) == [
            .holdActivity(true),
            .armWatchdog(displayID: 1, uuid: Rig.uuid, method: .blackout),
            .writeMarker(.engaging),
            .disable(displayID: 1, uuid: Rig.uuid, method: .blackout),
        ])
        rig.send(.disableFinished(succeeded: true))
        #expect(rig.send(.turnOff) == [.hideConfirmation, .enable(displayID: 1, uuid: Rig.uuid, method: .blackout)])
    }

    // MARK: Keep or revert

    @Test func `keep makes it active and tells the watchdog`() {
        var rig = Rig()
        rig.engage()
        rig.now = 1005
        #expect(rig.send(.keep) == [.hideConfirmation, .watchdogDeadline(nil), .writeMarker(.active)])
        #expect(rig.phase == .active(trigger: .manual, method: .disconnect, since: Rig.date, engagedAt: 1000))
        #expect(rig.tick(after: 60).isEmpty)
    }

    @Test func `revert restores and says so`() {
        var rig = Rig()
        rig.engage()
        #expect(rig.send(.revert) == Rig.restoreFromPrompt)
        #expect(rig.restoreReason == .declined)
        #expect(rig.state == .switching(toOn: false))
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown + [.notifyRestored(.declined)])
        #expect(rig.phase == .idle)
        #expect(rig.state == .off)
    }

    @Test func `nobody answering the prompt restores at the deadline`() {
        var rig = Rig()
        rig.engage()
        #expect(rig.tick(after: 14.5).isEmpty)
        #expect(rig.isConfirming)
        #expect(rig.tick(after: 0.5) == Rig.restoreFromPrompt)
        #expect(rig.restoreReason == .confirmationTimedOut)
        #expect(rig.send(.enableFinished(succeeded: true)).last == .notifyRestored(.confirmationTimedOut))
    }

    /// The sidecar restores at the deadline too, so a late Keep can't win.
    @Test func `keep after the deadline is ignored`() {
        var rig = Rig()
        rig.engage()
        rig.now += 15
        #expect(rig.send(.keep) == Rig.restoreFromPrompt)
        #expect(rig.restoreReason == .confirmationTimedOut)
    }

    @Test func `keep and revert do nothing outside the prompt`() {
        var idle = Rig()
        #expect(idle.send(.keep).isEmpty)
        #expect(idle.send(.revert).isEmpty)
        #expect(idle.phase == .idle)

        var active = Rig(Rig.noPrompt)
        active.activate()
        #expect(active.send(.keep).isEmpty)
        #expect(active.send(.revert).isEmpty)
        #expect(active.isActive)
    }

    /// The sidecar kills the app past the deadline; it must not while the enable verifies.
    @Test(arguments: [DeskModeEvent.revert, .turnOff, .panic, .snapshot(Desk.reading([DisplayFixtures.lg], sessionActive: false))])
    func `leaving the prompt clears the sidecar's deadline`(event: DeskModeEvent) {
        var rig = Rig()
        rig.engage()
        #expect(rig.send(event) == Rig.restoreFromPrompt)
        #expect(rig.send(.enableFinished(succeeded: false)).isEmpty)
        #expect(!rig.tick(after: 1).contains(.watchdogDeadline(nil))) // cleared once
    }

    @Test func `a restore from active leaves the deadline alone`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.turnOff) == Rig.restore)
    }

    // MARK: Turning off

    @Test func `turning off from active restores without a notification`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.turnOff) == Rig.restore)
        #expect(rig.restoreReason == .user)
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown)
        #expect(rig.state == .off)
    }

    @Test func `turning off from the prompt restores`() {
        var rig = Rig()
        rig.engage()
        #expect(rig.send(.turnOff) == Rig.restoreFromPrompt)
        #expect(rig.restoreReason == .user)
    }

    @Test func `turning off while idle does nothing`() {
        var rig = Rig()
        #expect(rig.send(.turnOff).isEmpty)
        #expect(rig.phase == .idle)
    }

    /// The disable may land after the enable ran, so it is enabled once more.
    @Test func `turning off mid-engage enables again once the disable lands`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        #expect(rig.send(.turnOff) == Rig.restore)
        #expect(rig.send(.snapshot(Desk.atDesk)).isEmpty) // the disable is still in flight
        #expect(rig.restoreReason == .user)
        rig.now += 1
        #expect(rig.send(.disableFinished(succeeded: true)) == [Rig.enable])
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown)
    }

    @Test func `a snapshot with the panel back completes the restore`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.turnOff)
        #expect(rig.send(.snapshot(Desk.panelBack)) == Rig.standDown)
        #expect(rig.phase == .idle)
        #expect(rig.send(.enableFinished(succeeded: true)).isEmpty)
    }

    /// Black out keeps the panel in the list, so only the enable's answer counts.
    @Test func `black out waits for the enable's answer`() {
        var rig = Rig(.init(method: .blackout, askBeforeKeeping: false))
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: true))
        rig.send(.snapshot(Desk.atDesk))
        #expect(rig.tick(after: 5).isEmpty) // the panel stays online: that's not a lid cycle
        #expect(rig.isActive)
        rig.send(.turnOff)
        #expect(rig.send(.snapshot(Desk.atDesk)).isEmpty)
        #expect(rig.restoreReason == .user)
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown)
    }

    // MARK: Losing the external

    @Test func `unplugging while active restores and names the display`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restore)
        #expect(rig.restoreReason == .externalLost(displayName: "LG ULTRAGEAR"))
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown + [.notifyRestored(.externalLost(displayName: "LG ULTRAGEAR"))])
    }

    @Test func `unplugging during the prompt restores`() {
        var rig = Rig()
        rig.engage()
        rig.now += 3
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restoreFromPrompt)
        #expect(rig.restoreReason == .externalLost(displayName: "LG ULTRAGEAR"))
    }

    /// Our own transaction reshuffles the list for a moment, so the loss clock starts after it.
    @Test func `an empty list inside the settle window waits, then restores`() {
        var rig = Rig(Rig.noPrompt)
        rig.engage()
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
        #expect(rig.tick(after: 1).isEmpty)
        #expect(rig.tick(after: 1).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restore)
        #expect(rig.restoreReason == .externalLost(displayName: "LG ULTRAGEAR"))
    }

    @Test func `a list that recovers inside the settle window keeps Desk Mode`() {
        var rig = Rig(Rig.noPrompt)
        rig.engage()
        rig.send(.snapshot(Desk.unplugged))
        rig.now += 1
        rig.send(.snapshot(Desk.panelOff))
        #expect(rig.tick(after: 5).isEmpty)
        #expect(rig.isActive)
    }

    @Test func `the lost display's name is the last one seen`() {
        var dell = DisplayFixtures.lg
        dell.displayID = 4
        dell.uuid = "DELL"
        dell.screenName = "DELL U2723QE"
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.snapshot(Desk.reading([dell])))
        rig.send(.snapshot(Desk.unplugged))
        rig.tick(after: 1)
        #expect(rig.restoreReason == .externalLost(displayName: "DELL U2723QE"))
    }

    /// Display sleep makes every display inactive; that must never end Desk Mode.
    @Test func `display sleep never restores`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.snapshot(Desk.screensAsleep)).isEmpty)
        for _ in 0..<600 { #expect(rig.tick(after: 1).isEmpty) }
        #expect(rig.isActive)
    }

    /// Asleep displays can even drop out of the lists; decide once the screens wake.
    @Test func `an empty list while the screens sleep waits for them to wake`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.snapshot(Desk.reading([], screensAsleep: true))).isEmpty)
        #expect(rig.tick(after: 60).isEmpty)
        #expect(rig.send(.snapshot(Desk.panelOff)).isEmpty)
        rig.send(.snapshot(Desk.reading([], screensAsleep: true)))
        rig.now += 5
        // The asleep reading doesn't start the loss clock; the first awake one
        // does, and the external gets the screen-wake grace to come back.
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
        #expect(rig.tick(after: 1).isEmpty)
        #expect(rig.tick(after: 4).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restore)
        #expect(rig.restoreReason == .externalLost(displayName: "LG ULTRAGEAR"))
    }

    /// A monitor leaving standby (the LG on HDMI) can be missing from the list
    /// for a few seconds while its signal resyncs: that isn't an unplug.
    @Test func `an external resyncing after display sleep keeps Desk Mode`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.snapshot(Desk.screensAsleep))
        rig.tick(after: 120)
        rig.send(.snapshot(Desk.reading([], screensAsleep: true)))
        rig.tick(after: 60)
        // Awake, the LG not back yet.
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
        for _ in 0..<5 { #expect(rig.tick(after: 1).isEmpty) }
        #expect(rig.send(.snapshot(Desk.panelOff)).isEmpty)
        #expect(rig.tick(after: 60).isEmpty)
        #expect(rig.isActive)
    }

    /// The grace belongs to the wake: a later unplug is confirmed in the usual second.
    @Test func `an unplug well after the screens woke restores in the usual time`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.snapshot(Desk.screensAsleep))
        rig.tick(after: 30)
        rig.send(.snapshot(Desk.panelOff))
        rig.tick(after: 30)
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restore)
    }

    @Test(arguments: [0.0, 10.0])
    func `the screen-wake grace is configurable`(seconds: TimeInterval) {
        var rig = Rig(.init(askBeforeKeeping: false, screenWakeGrace: seconds))
        rig.activate()
        rig.send(.snapshot(Desk.reading([], screensAsleep: true)))
        rig.tick(after: 30)
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
        if seconds == 0 {
            #expect(rig.tick(after: 1) == Rig.restore)
        } else {
            #expect(rig.tick(after: 9.5).isEmpty)
            #expect(rig.tick(after: 0.5) == Rig.restore)
        }
    }

    /// The prompt's deadline still wins inside the grace.
    @Test func `the prompt still times out inside the screen-wake grace`() {
        var rig = Rig()
        rig.engage()
        rig.send(.snapshot(Desk.reading([], screensAsleep: true)))
        rig.now += 10
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
        #expect(rig.tick(after: 5) == Rig.restoreFromPrompt)
        #expect(rig.restoreReason == .confirmationTimedOut)
    }

    @Test func `a present but inactive external keeps Desk Mode`() {
        var lg = DisplayFixtures.lg
        lg.isActive = false
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.snapshot(Desk.reading([lg]))).isEmpty)
        #expect(rig.isActive)
    }

    /// One reading taken mid-reconfiguration can miss a display that is still there.
    @Test func `one empty reading is not a loss`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
        rig.now += 0.5
        #expect(rig.send(.snapshot(Desk.panelOff)).isEmpty)
        #expect(rig.tick(after: 0.5).isEmpty)
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty) // the clock starts over
        #expect(rig.tick(after: 0.5).isEmpty)
        #expect(rig.tick(after: 0.5) == Rig.restore)
    }

    @Test func `a later empty reading confirms the loss too`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.snapshot(Desk.unplugged))
        rig.now += 1
        #expect(rig.send(.snapshot(Desk.unplugged)) == Rig.restore)
    }

    @Test(arguments: [0.0, 3.0])
    func `the loss confirm time is configurable`(seconds: TimeInterval) {
        var rig = Rig(.init(askBeforeKeeping: false, lossConfirmTime: seconds))
        rig.activate()
        if seconds == 0 {
            #expect(rig.send(.snapshot(Desk.unplugged)) == Rig.restore)
        } else {
            #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty)
            #expect(rig.tick(after: 2.5).isEmpty)
            #expect(rig.tick(after: 0.5) == Rig.restore)
        }
    }

    @Test func `a loss pending at sleep starts over after wake`() {
        var rig = Rig(.init(askBeforeKeeping: false, keepAfterWake: true))
        rig.activate()
        rig.send(.snapshot(Desk.unplugged))
        rig.send(.willSleep)
        rig.now += 60
        rig.send(.didWake)
        #expect(rig.tick(after: 2).isEmpty) // settled: the clock starts now, not before sleep
        #expect(rig.tick(after: 1).isEmpty) // confirmed, but inside the screen-wake grace
        #expect(rig.tick(after: 2).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restore)
    }

    /// No prompt on a display that's gone, and no settle window to wait out.
    @Test(arguments: [false, true])
    func `a disable that lands with the external gone restores at once`(askBeforeKeeping: Bool) {
        var rig = Rig(.init(askBeforeKeeping: askBeforeKeeping))
        rig.send(.turnOn(trigger: .manual))
        rig.send(.snapshot(Desk.reading([DisplayFixtures.builtIn])))
        #expect(rig.send(.disableFinished(succeeded: true)) == Rig.restore)
        #expect(rig.restoreReason == .externalLost(displayName: "LG ULTRAGEAR"))
        #expect(rig.send(.enableFinished(succeeded: true)).last == .notifyRestored(.externalLost(displayName: "LG ULTRAGEAR")))
    }

    @Test func `a disable that lands while the screens sleep still waits for them`() {
        var rig = Rig(Rig.noPrompt)
        rig.send(.turnOn(trigger: .manual))
        rig.send(.snapshot(Desk.reading([], screensAsleep: true)))
        #expect(rig.send(.disableFinished(succeeded: true)) == [.writeMarker(.active)])
        #expect(rig.isActive)
    }

    @Test(arguments: [
        [DisplayFixtures.standIn],
        [DisplayFixtures.sidecar],
        [DisplayFixtures.emptySlot(3), DisplayFixtures.standIn, DisplayFixtures.sidecar],
    ])
    func `placeholders and virtual displays don't count as an external`(facts: [DisplayFacts]) {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.snapshot(Desk.reading(facts))).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restore)
        #expect(rig.restoreReason == .externalLost(displayName: "LG ULTRAGEAR"))
    }

    @Test func `turning on refuses a stand-in or a virtual display as the external`() {
        var rig = Rig(snapshot: Desk.reading([DisplayFixtures.builtIn, DisplayFixtures.standIn, DisplayFixtures.sidecar]))
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.notReady)])
    }

    // MARK: The panel coming back by itself

    @Test func `the panel coming back ends Desk Mode quietly and for good`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.snapshot(Desk.panelBack)) == Rig.standDown)
        #expect(rig.phase == .idle)
        #expect(rig.state == .off)
        #expect(rig.tick(after: 5).isEmpty)
        #expect(rig.send(.snapshot(Desk.panelOff)).isEmpty) // a later lid close
        #expect(rig.send(.snapshot(Desk.panelBack)).isEmpty)
    }

    @Test func `the panel coming back during the prompt hides it`() {
        var rig = Rig()
        rig.engage()
        rig.now += 3
        #expect(rig.send(.snapshot(Desk.panelBack)) == [.hideConfirmation] + Rig.standDown)
    }

    @Test func `the panel still listed inside the settle window is not a lid cycle`() {
        var rig = Rig(Rig.noPrompt)
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: true))
        #expect(rig.send(.snapshot(Desk.atDesk)).isEmpty)
        #expect(rig.isActive)
        rig.send(.snapshot(Desk.panelOff))
        #expect(rig.tick(after: 3).isEmpty)
        #expect(rig.isActive)
    }

    @Test func `a lid cycle while active ends Desk Mode`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.snapshot(Desk.reading([DisplayFixtures.lg], lid: .closed))).isEmpty)
        #expect(rig.isActive)
        #expect(rig.send(.snapshot(Desk.panelBack)) == Rig.standDown)
    }

    // MARK: System sleep

    @Test func `nothing happens between willSleep and the end of the wake settle`() {
        var rig = Rig(.init(askBeforeKeeping: false, keepAfterWake: true))
        rig.activate()
        #expect(rig.send(.willSleep).isEmpty)
        #expect(rig.send(.snapshot(Desk.reading([], systemSleeping: true))).isEmpty)
        #expect(rig.tick(after: 1).isEmpty)
        #expect(rig.send(.panic) == [.hideConfirmation]) // held back until wake
        #expect(rig.send(.didWake) == [Rig.enable]) // the panic key doesn't wait for the settle
    }

    @Test func `waking without keepAfterWake restores after the settle time`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.willSleep).isEmpty)
        #expect(rig.send(.snapshot(Desk.reading([DisplayFixtures.lg], systemSleeping: true))).isEmpty)
        #expect(rig.tick(after: 1).isEmpty)
        #expect(rig.send(.didWake).isEmpty)
        #expect(rig.send(.snapshot(Desk.panelOff)).isEmpty)
        #expect(rig.tick(after: 1).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restore)
        #expect(rig.restoreReason == .sleep)
        #expect(rig.send(.enableFinished(succeeded: true)).last == .notifyRestored(.sleep))
    }

    @Test func `waking with keepAfterWake stays on and watches the external again`() {
        var rig = Rig(.init(askBeforeKeeping: false, keepAfterWake: true))
        rig.activate()
        rig.send(.willSleep)
        rig.send(.snapshot(Desk.reading([], systemSleeping: true)))
        rig.send(.didWake)
        #expect(rig.send(.snapshot(Desk.unplugged)).isEmpty) // still settling
        #expect(rig.tick(after: 2).isEmpty) // the loss clock starts
        #expect(rig.tick(after: 1).isEmpty) // the screen-wake grace
        #expect(rig.tick(after: 3) == Rig.restore)
        #expect(rig.restoreReason == .externalLost(displayName: "LG ULTRAGEAR"))
    }

    @Test func `waking with keepAfterWake and the external there keeps Desk Mode`() {
        var rig = Rig(.init(askBeforeKeeping: false, keepAfterWake: true))
        rig.activate()
        rig.send(.willSleep)
        rig.send(.didWake)
        rig.send(.snapshot(Desk.panelOff))
        #expect(rig.tick(after: 2).isEmpty)
        #expect(rig.tick(after: 60).isEmpty)
        #expect(rig.isActive)
    }

    @Test(arguments: [false, true])
    func `a prompt pending at sleep restores after wake`(keepAfterWake: Bool) {
        var rig = Rig(.init(keepAfterWake: keepAfterWake))
        rig.engage()
        // Uptime stops while asleep: a deadline left with the sidecar would pass during the restore.
        #expect(rig.send(.willSleep) == [.hideConfirmation, .watchdogDeadline(nil)])
        rig.send(.didWake)
        #expect(rig.send(.keep).isEmpty) // the prompt is gone
        #expect(rig.tick(after: 1).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restoreFromPrompt)
        #expect(rig.restoreReason == .sleep)
    }

    @Test func `the panel back after wake ends Desk Mode quietly`() {
        var rig = Rig(.init(askBeforeKeeping: false, keepAfterWake: true))
        rig.activate()
        rig.send(.willSleep)
        rig.send(.didWake)
        #expect(rig.send(.snapshot(Desk.panelBack)).isEmpty) // still settling
        #expect(rig.tick(after: 2) == Rig.standDown)
        #expect(rig.phase == .idle)
    }

    @Test func `an engage in flight at sleep restores once its disable lands`() {
        var rig = Rig(Rig.noPrompt)
        rig.send(.turnOn(trigger: .manual))
        rig.send(.willSleep)
        #expect(rig.send(.disableFinished(succeeded: true)) == [.hideConfirmation]) // enable held back
        #expect(rig.restoreReason == .sleep)
        rig.send(.didWake)
        #expect(rig.tick(after: 1).isEmpty)
        #expect(rig.tick(after: 1) == [Rig.enable])
    }

    @Test func `turning on is refused while asleep and settling`() {
        var rig = Rig()
        rig.send(.willSleep)
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.notReady)])
        rig.send(.didWake)
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.notReady)])
        rig.now += 2
        #expect(rig.send(.turnOn(trigger: .manual)) == Rig.engage)
    }

    @Test func `a user restore inside the wake settle waits for it`() {
        var rig = Rig(.init(askBeforeKeeping: false, keepAfterWake: true))
        rig.activate()
        rig.send(.willSleep)
        rig.send(.didWake)
        #expect(rig.send(.turnOff) == [.hideConfirmation])
        #expect(rig.tick(after: 2) == [Rig.enable])
    }

    // MARK: Panic

    enum Stage: CaseIterable { case idle, engaging, confirming, active, restoring }

    @Test(arguments: DeskModeMachineTests.Stage.allCases.filter { $0 != .idle })
    func `panic always sends an enable`(stage: Stage) {
        var rig = Rig(stage == .active ? Rig.noPrompt : .init())
        switch stage {
        case .idle: break
        case .engaging: rig.send(.turnOn(trigger: .manual))
        case .confirming: rig.engage()
        case .active: rig.activate()
        case .restoring:
            rig.engage()
            rig.send(.revert)
        }
        #expect(rig.send(.panic) == (stage == .confirming ? Rig.restoreFromPrompt : Rig.restore))
        #expect(rig.restoreReason == .panic)
        #expect(rig.state == .switching(toOn: false))
    }

    /// The user pressed the key and can see the panel come back.
    @Test(arguments: DeskModeMachineTests.Stage.allCases.filter { $0 != .idle })
    func `panic never notifies`(stage: Stage) {
        var rig = Rig(stage == .active ? Rig.noPrompt : .init())
        switch stage {
        case .idle: break
        case .engaging: rig.send(.turnOn(trigger: .manual))
        case .confirming: rig.engage()
        case .active: rig.activate()
        case .restoring:
            rig.engage()
            rig.send(.revert)
        }
        rig.send(.panic)
        rig.send(.disableFinished(succeeded: true)) // answers the engage, if one was in flight
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown)
        #expect(rig.state == .off)
    }

    @Test func `panic from idle sends one enable and stays idle`() {
        var rig = Rig()
        #expect(rig.send(.panic) == [Rig.enable])
        #expect(rig.phase == .idle)
        #expect(rig.state == .off)
        #expect(!rig.machine.needsTicks)
        #expect(rig.send(.enableFinished(succeeded: false)).isEmpty)
        #expect(rig.tick(after: 5).isEmpty) // no retries
        #expect(rig.send(.enableFinished(succeeded: true)).isEmpty) // no notification
        #expect(rig.phase == .idle)
    }

    @Test func `panic from idle targets the panel the reading still remembers`() {
        var rig = Rig(snapshot: Desk.reading([DisplayFixtures.lg], lid: .closed))
        #expect(rig.send(.panic) == [Rig.enable])
        #expect(rig.phase == .idle)
    }

    @Test func `panic from idle sends nothing while asleep`() {
        var rig = Rig()
        rig.send(.willSleep)
        #expect(rig.send(.panic).isEmpty)
        rig.send(.didWake)
        #expect(rig.send(.panic) == [Rig.enable]) // inside the wake settle
        #expect(rig.phase == .idle)
    }

    @Test func `panic uses the captured panel even if the reading lost it`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.snapshot(DeskModeSnapshot(builtInOnline: false, builtInDisplayID: nil, externals: Desk.panelOff.externals)))
        #expect(rig.send(.panic) == Rig.restore)
    }

    // MARK: Failures

    @Test func `a failed enable is retried every interval, forever`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.turnOff)
        for _ in 0..<200 {
            #expect(rig.send(.enableFinished(succeeded: false)).isEmpty)
            #expect(rig.tick(after: 0.5).isEmpty)
            #expect(rig.tick(after: 0.5) == [Rig.enable])
        }
        #expect(rig.restoreReason == .user)
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown)
    }

    @Test func `turning off again retries a failed enable at once`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.turnOff)
        rig.send(.enableFinished(succeeded: false))
        #expect(rig.send(.turnOff) == [Rig.enable])
        #expect(rig.send(.turnOff).isEmpty) // one in flight
    }

    @Test func `an enable that never answers is sent again`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.turnOff)
        #expect(rig.tick(after: 11).isEmpty)
        #expect(rig.tick(after: 1) == [Rig.enable])
    }

    @Test func `a failed disable restores and says so`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        #expect(rig.send(.disableFinished(succeeded: false)) == Rig.restore)
        #expect(rig.restoreReason == .engageFailed)
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown + [.notifyRestored(.engageFailed)])
    }

    @Test func `a disable that never answers times out`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        #expect(rig.tick(after: 11).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restore)
        #expect(rig.restoreReason == .engageFailed)
    }

    /// The hung disable finally lands after the machine went idle: the panel is dark with no guard.
    @Test func `a late disable after the timeout is guarded and undone`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        rig.tick(after: 12)
        rig.send(.enableFinished(succeeded: true))
        #expect(rig.phase == .idle)
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.busy)])
        #expect(rig.send(.disableFinished(succeeded: true)) == Array(Rig.engage.prefix(3)) + Rig.restore)
        #expect(rig.restoreReason == .engageFailed)
    }

    @Test func `two failed engages within the window latch Desk Mode`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: false))
        rig.send(.enableFinished(succeeded: true))
        rig.now += 30
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: false))
        rig.send(.enableFinished(succeeded: true))
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.latched(until: 1330))])
        rig.now = 1329
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.latched(until: 1330))])
        rig.now = 1330
        #expect(rig.send(.turnOn(trigger: .manual)) == Rig.engage)
    }

    @Test func `a timed-out engage counts toward the latch`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: false))
        rig.send(.enableFinished(succeeded: true))
        rig.send(.turnOn(trigger: .manual))
        rig.tick(after: 12)
        rig.send(.enableFinished(succeeded: true))
        rig.send(.disableFinished(succeeded: false)) // the hung call gives up
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.latched(until: 1312))])
    }

    @Test func `failures further apart than the window don't latch`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: false))
        rig.send(.enableFinished(succeeded: true))
        rig.now += 61
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: false))
        rig.send(.enableFinished(succeeded: true))
        #expect(rig.send(.turnOn(trigger: .manual)) == Rig.engage)
    }

    @Test func `a successful engage resets the failure count`() {
        var rig = Rig(Rig.noPrompt)
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: false))
        rig.send(.enableFinished(succeeded: true))
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: true))
        rig.send(.turnOff)
        rig.send(.enableFinished(succeeded: true))
        rig.send(.turnOn(trigger: .manual))
        rig.send(.disableFinished(succeeded: false))
        rig.send(.enableFinished(succeeded: true))
        #expect(rig.send(.turnOn(trigger: .manual)) == Rig.engage)
    }

    // MARK: Holding the enable

    /// In clamshell the panel can't come online; an enable a second would only churn.
    @Test func `a restore with the lid closed waits for the lid to open`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.snapshot(Desk.reading([DisplayFixtures.lg], lid: .closed)))
        #expect(rig.send(.turnOff) == [.hideConfirmation])
        #expect(rig.restoreReason == .user)
        for _ in 0..<30 { #expect(rig.tick(after: 1).isEmpty) }
        #expect(rig.send(.snapshot(Desk.reading([DisplayFixtures.lg]))) == [Rig.enable])
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown)
    }

    @Test func `opening the lid with the panel back finishes the restore`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.snapshot(Desk.reading([DisplayFixtures.lg], lid: .closed)))
        rig.send(.snapshot(Desk.reading([], lid: .closed)))
        rig.tick(after: 1)
        #expect(rig.restoreReason == .externalLost(displayName: "LG ULTRAGEAR"))
        #expect(rig.tick(after: 5).isEmpty)
        #expect(rig.send(.snapshot(Desk.reading([DisplayFixtures.builtIn]))) == Rig.standDown + [.notifyRestored(.externalLost(displayName: "LG ULTRAGEAR"))])
    }

    @Test func `a failed enable stops retrying once the lid closes`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.turnOff)
        rig.send(.enableFinished(succeeded: false))
        rig.send(.snapshot(Desk.reading([DisplayFixtures.lg], lid: .closed)))
        for _ in 0..<30 { #expect(rig.tick(after: 1).isEmpty) }
        #expect(rig.send(.turnOff).isEmpty)
        #expect(rig.send(.snapshot(Desk.reading([DisplayFixtures.lg], lid: .unknown))) == [Rig.enable])
    }

    /// The key always gets its enable; only the retries wait for the lid.
    @Test func `panic with the lid closed sends one enable, then waits`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.snapshot(Desk.reading([DisplayFixtures.lg], lid: .closed)))
        #expect(rig.send(.panic) == Rig.restore)
        #expect(rig.send(.enableFinished(succeeded: false)).isEmpty)
        for _ in 0..<10 { #expect(rig.tick(after: 1).isEmpty) }
        #expect(rig.send(.snapshot(Desk.reading([DisplayFixtures.lg]))) == [Rig.enable])
    }

    /// A disable that outlived its timeout lands when nothing remembers the panel any more.
    @Test func `a restore with no panel known waits for one`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        rig.tick(after: 12)
        rig.send(.enableFinished(succeeded: true))
        rig.send(.snapshot(DeskModeSnapshot(builtInOnline: false, builtInDisplayID: nil, externals: Desk.panelOff.externals)))
        #expect(rig.send(.disableFinished(succeeded: true)) == [.holdActivity(true), .writeMarker(.engaging), .hideConfirmation])
        #expect(rig.restoreReason == .engageFailed)
        #expect(rig.tick(after: 5).isEmpty)
        // Recovery names the panel: the restore keeps its reason and sends the enable.
        #expect(rig.send(.resumeRestore(displayID: 1, uuid: Rig.uuid, method: .disconnect)) == [Rig.enable])
        #expect(rig.restoreReason == .engageFailed)
    }

    // MARK: Resuming a restore

    @Test func `resuming a restore from idle guards it and keeps trying`() {
        var rig = Rig()
        #expect(rig.send(.resumeRestore(displayID: 7, uuid: "PANEL", method: .disconnect)) == [
            .holdActivity(true),
            .armWatchdog(displayID: 7, uuid: "PANEL", method: .disconnect),
            .writeMarker(.engaging),
            .enable(displayID: 7, uuid: "PANEL", method: .disconnect),
        ])
        #expect(rig.phase == .restoring(reason: .recovery, method: .disconnect, lastAttempt: 1000))
        #expect(rig.state == .switching(toOn: false))
        #expect(rig.machine.needsTicks)
        for _ in 0..<5 {
            #expect(rig.send(.enableFinished(succeeded: false)).isEmpty)
            #expect(rig.tick(after: 1) == [.enable(displayID: 7, uuid: "PANEL", method: .disconnect)])
        }
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown) // no notification
        #expect(rig.phase == .idle)
    }

    @Test func `a resumed restore finishes when the panel shows up`() {
        var rig = Rig(snapshot: Desk.panelOff)
        rig.send(.resumeRestore(displayID: 1, uuid: Rig.uuid, method: .disconnect))
        #expect(rig.send(.snapshot(Desk.panelBack)) == Rig.standDown)
    }

    @Test func `a resumed restore carries its method`() {
        var rig = Rig()
        let commands = rig.send(.resumeRestore(displayID: 1, uuid: Rig.uuid, method: .blackout))
        #expect(commands.last == .enable(displayID: 1, uuid: Rig.uuid, method: .blackout))
        #expect(rig.phase == .restoring(reason: .recovery, method: .blackout, lastAttempt: 1000))
    }

    @Test func `a resumed restore with the lid closed waits for it to open`() {
        var rig = Rig(snapshot: Desk.reading([DisplayFixtures.lg], lid: .closed))
        #expect(rig.send(.resumeRestore(displayID: 1, uuid: Rig.uuid, method: .disconnect)) == Array(Rig.engage.prefix(3)))
        #expect(rig.tick(after: 5).isEmpty)
        #expect(rig.send(.snapshot(Desk.panelOff)) == [Rig.enable])
    }

    @Test func `resuming during a restore keeps it`() {
        var rig = Rig()
        rig.engage()
        rig.send(.revert)
        #expect(rig.send(.resumeRestore(displayID: 7, uuid: "OTHER", method: .blackout)).isEmpty)
        #expect(rig.restoreReason == .declined)
        rig.send(.enableFinished(succeeded: false))
        #expect(rig.tick(after: 1) == [Rig.enable]) // still the panel it switched off
    }

    @Test func `resuming while Desk Mode is on restores`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.resumeRestore(displayID: 1, uuid: Rig.uuid, method: .disconnect)) == Rig.restore)
        #expect(rig.restoreReason == .recovery)
        #expect(rig.send(.enableFinished(succeeded: true)) == Rig.standDown)
    }

    // MARK: Refusals

    @Test(arguments: [
        Desk.reading(Desk.Fixtures.thisMac, lid: .closed),
        Desk.reading(Desk.Fixtures.thisMac, lid: .unknown),
        Desk.reading([Desk.Fixtures.builtIn]),
        Desk.reading([Desk.Fixtures.lg]),
        Desk.reading(Desk.Fixtures.thisMac, sessionActive: false),
        Desk.reading(Desk.Fixtures.thisMac, systemSleeping: true),
        Desk.reading([Desk.mirroredBuiltIn, Desk.Fixtures.lg]),
        DeskModeSnapshot(builtInDisplayID: nil, externals: Desk.atDesk.externals),
    ])
    func `turning on is refused when the reading isn't ready`(snapshot: DeskModeSnapshot) {
        var rig = Rig(snapshot: snapshot)
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.notReady)])
        #expect(rig.phase == .idle)
    }

    @Test func `turning on is refused while unavailable`() {
        var rig = Rig(availability: .unsupportedMac)
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.unavailable(.unsupportedMac))])
        rig.send(.availability(.needsDisplay))
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.unavailable(.needsDisplay))])
        rig.send(.availability(nil))
        #expect(rig.send(.turnOn(trigger: .manual)) == Rig.engage)
    }

    @Test(arguments: DeskModeMachineTests.Stage.allCases.filter { $0 != .idle })
    func `turning on is refused while busy`(stage: Stage) {
        var rig = Rig(stage == .active ? Rig.noPrompt : .init())
        switch stage {
        case .idle: break
        case .engaging: rig.send(.turnOn(trigger: .manual))
        case .confirming: rig.engage()
        case .active: rig.activate()
        case .restoring:
            rig.engage()
            rig.send(.revert)
        }
        let before = rig.machine
        #expect(rig.send(.turnOn(trigger: .manual)) == [.refused(.busy)])
        #expect(rig.machine == before)
    }

    // MARK: Session, quit, time limit

    @Test func `the session resigning restores, even while settling`() {
        var rig = Rig()
        rig.engage()
        #expect(rig.send(.snapshot(Desk.reading([DisplayFixtures.lg], sessionActive: false))) == Rig.restoreFromPrompt)
        #expect(rig.restoreReason == .sessionChanged)
        #expect(rig.send(.enableFinished(succeeded: true)).last == .notifyRestored(.sessionChanged))
    }

    @Test func `the session resigning mid-engage restores once the disable lands`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        #expect(rig.send(.snapshot(Desk.reading(Desk.Fixtures.thisMac, sessionActive: false))).isEmpty)
        let commands = rig.send(.disableFinished(succeeded: true))
        #expect(Array(commands.suffix(3)) == Rig.restoreFromPrompt)
        #expect(rig.restoreReason == .sessionChanged)
    }

    @Test(arguments: DeskModeMachineTests.Stage.allCases.filter { $0 != .idle })
    func `quitting restores and stands down at once`(stage: Stage) {
        var rig = Rig(stage == .active ? Rig.noPrompt : .init())
        switch stage {
        case .idle: break
        case .engaging: rig.send(.turnOn(trigger: .manual))
        case .confirming: rig.engage()
        case .active: rig.activate()
        case .restoring:
            rig.engage()
            rig.send(.revert)
        }
        #expect(rig.send(.willTerminate) == Rig.restore + Rig.standDown)
        #expect(rig.phase == .idle)
        #expect(rig.send(.enableFinished(succeeded: true)).isEmpty)
    }

    @Test func `quitting while idle sends nothing`() {
        var rig = Rig()
        #expect(rig.send(.willTerminate).isEmpty)
    }

    @Test func `quitting while asleep still enables`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        rig.send(.willSleep)
        #expect(rig.send(.willTerminate) == Rig.restore + Rig.standDown)
    }

    @Test func `the debug time limit ends an active Desk Mode`() {
        var rig = Rig(.init(askBeforeKeeping: false, maxDuration: 300))
        rig.activate()
        #expect(rig.tick(after: 297).isEmpty)
        #expect(rig.tick(after: 1) == Rig.restore)
        #expect(rig.restoreReason == .timeLimit)
        #expect(rig.send(.enableFinished(succeeded: true)).last == .notifyRestored(.timeLimit))
    }

    @Test func `without a time limit Desk Mode runs on`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.tick(after: 86_400).isEmpty)
        #expect(rig.isActive)
    }

    @Test func `availability changes don't end Desk Mode`() {
        var rig = Rig(Rig.noPrompt)
        rig.activate()
        #expect(rig.send(.availability(.lidClosed)).isEmpty)
        #expect(rig.isActive)
        #expect(rig.state == .on(since: Rig.date, trigger: .manual))
    }

    // MARK: State

    @Test func `idle maps to off or unavailable`() {
        var rig = Rig()
        #expect(rig.state == .off)
        #expect(!rig.machine.needsTicks)
        rig.send(.availability(.needsDisplay))
        #expect(rig.state == .unavailable(.needsDisplay))
        rig.send(.availability(nil))
        #expect(rig.state == .off)
    }

    @Test func `ticks are wanted whenever the machine isn't idle`() {
        var rig = Rig()
        rig.send(.turnOn(trigger: .manual))
        #expect(rig.machine.needsTicks)
        rig.send(.disableFinished(succeeded: true))
        #expect(rig.machine.needsTicks)
        rig.send(.revert)
        #expect(rig.machine.needsTicks)
        rig.send(.enableFinished(succeeded: true))
        #expect(!rig.machine.needsTicks)
    }

    @Test func `the same events give the same machine`() {
        func run() -> (DeskModeMachine, [[DeskModeCommand]]) {
            var rig = Rig()
            var log: [[DeskModeCommand]] = []
            log.append(rig.send(.turnOn(trigger: .automatic(displayName: "LG ULTRAGEAR"))))
            log.append(rig.send(.disableFinished(succeeded: true)))
            log.append(rig.send(.snapshot(Desk.panelOff)))
            log.append(rig.tick(after: 3))
            log.append(rig.send(.keep))
            log.append(rig.send(.willSleep))
            log.append(rig.send(.didWake))
            log.append(rig.tick(after: 2))
            return (rig.machine, log)
        }
        let (a, logA) = run()
        let (b, logB) = run()
        #expect(a == b)
        #expect(logA == logB)
        #expect(a.phase == .restoring(reason: .sleep, method: .disconnect, lastAttempt: 1005))
    }
}
