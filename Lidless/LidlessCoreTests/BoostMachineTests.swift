import Foundation
import Testing
@testable import LidlessCore

/// A machine plus a monotonic clock.
private struct Rig {
    static let ramp = 0.4
    /// This Mac at max native brightness: ≈ 1600 / 600.
    static let fullHeadroom = 2.66

    var machine: BoostMachine
    var now: TimeInterval = 1000

    /// Most tests follow the headroom from the start; the hold has its own tests.
    init(_ configuration: BoostMachine.Configuration = .init(headroomHold: 0)) {
        machine = BoostMachine(configuration: configuration)
    }

    var status: BoostStatus { machine.status }

    @discardableResult
    mutating func send(_ event: BoostEvent) -> [BoostCommand] {
        machine.handle(event, now: now)
    }

    @discardableResult
    mutating func request(_ factor: Double) -> [BoostCommand] {
        send(.request(factor: factor))
    }

    @discardableResult
    mutating func conditions(_ conditions: BoostConditions, _ settings: BoostSettings = .defaults) -> [BoostCommand] {
        send(.conditions(conditions, settings))
    }

    @discardableResult
    mutating func headroom(_ value: Double) -> [BoostCommand] {
        send(.headroom(value))
    }

    @discardableResult
    mutating func tick(after seconds: TimeInterval) -> [BoostCommand] {
        now += seconds
        return send(.tick)
    }

    /// Ticks every 0.25 s for `seconds`, collecting everything.
    @discardableResult
    mutating func run(for seconds: TimeInterval) -> [BoostCommand] {
        var commands: [BoostCommand] = []
        for _ in 0..<Int((seconds / 0.25).rounded()) { commands += tick(after: 0.25) }
        return commands
    }

    /// Requests `factor` and lets the engine report full headroom half a second later.
    mutating func engage(_ factor: Double = 1.5) {
        request(factor)
        now += 0.5
        headroom(Self.fullHeadroom)
    }

    /// Requests and lets the engage try time out with no headroom: one strike.
    mutating func failEngage(_ factor: Double = 1.5) {
        request(factor)
        headroom(1.0)
        tick(after: machine.configuration.engageTimeout)
    }
}

private func shows(_ commands: [BoostCommand]) -> [Double] {
    commands.compactMap { if case .show(let factor, _) = $0 { factor } else { nil } }
}

struct BoostMachineTests {
    static let hotSettings: BoostSettings = {
        var settings = BoostSettings.defaults
        settings.pauseAtHeat = .critical
        return settings
    }()

    // MARK: Engaging

    @Test func `the machine starts off and needs no ticks`() {
        let rig = Rig()
        #expect(rig.status == .off)
        #expect(!rig.machine.needsTicks)
    }

    @Test func `a request above 1 shows the overlay at 1 and engages`() {
        var rig = Rig()
        #expect(rig.request(1.5) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
        #expect(rig.machine.needsTicks)
    }

    @Test func `the engine asks for the ceiling whatever the slider`() {
        var rig = Rig()
        rig.request(1.2)
        #expect(rig.machine.wantedFactor == BoostMachine.Configuration().maxFactor)
        rig.request(3)
        #expect(rig.machine.wantedFactor == BoostMachine.Configuration().maxFactor)
    }

    @Test func `with a hold the factor stays 1 until the headroom is all there`() {
        var rig = Rig(.init(headroomHold: 4))
        rig.request(1.5)
        rig.now += 0.1
        // Spare headroom at normal brightness: not yet what was asked for.
        #expect(!rig.headroom(1.2).contains { if case .show(let f, _) = $0 { f > 1 } else { false } })
        rig.run(for: 1)
        rig.headroom(1.5)
        rig.run(for: 1)
        #expect(rig.status == .engaging)
        let commands = rig.headroom(1.77) + rig.run(for: 0.5)
        #expect(commands.contains(.show(factor: 1.5, rampSeconds: Rig.ramp)))
        #expect(rig.status == .on(factor: 1.5))
    }

    @Test func `the hold gives up after its time and follows the headroom`() {
        var rig = Rig(.init(headroomHold: 4))
        rig.request(1.5)
        rig.now += 0.1
        rig.headroom(1.3)
        let early = rig.run(for: 3.5)
        #expect(!early.contains { if case .show(let f, _) = $0 { f > 1 } else { false } })
        let late = rig.run(for: 1)
        #expect(late.contains(.show(factor: 0.98 * 1.3, rampSeconds: Rig.ramp)))
    }

    @Test func `while engaging the factor follows 98 percent of the rising headroom`() {
        var rig = Rig()
        rig.request(1.5)
        #expect(rig.headroom(1.0) == [])
        rig.now += 0.25
        #expect(rig.headroom(1.1) == [.show(factor: 0.98 * 1.1, rampSeconds: Rig.ramp)])
        rig.now += 0.125
        #expect(rig.headroom(1.3) == [])
        #expect(rig.machine.needsTicks)
        #expect(rig.tick(after: 0.125) == [.show(factor: 0.98 * 1.3, rampSeconds: Rig.ramp)])
        #expect(rig.status == .engaging)
        rig.now += 0.25
        #expect(rig.headroom(Rig.fullHeadroom) == [.show(factor: 1.5, rampSeconds: Rig.ramp), .publish(.on(factor: 1.5))])
    }

    @Test func `no show while engaging ever passes 98 percent of the headroom`() {
        var rig = Rig()
        var factors = shows(rig.request(1.6))
        var ceiling = 1.0
        for headroom in stride(from: 1.0, through: 2.66, by: 0.07) {
            rig.now += 0.125
            let sent = shows(rig.headroom(headroom)) + shows(rig.tick(after: 0.125))
            ceiling = max(1, 0.98 * headroom)
            for factor in sent { #expect(factor <= ceiling + 1e-12) }
            factors += sent
        }
        #expect(factors.first == 1)
        #expect(factors.last == 1.6)
        #expect(factors == factors.sorted())
        #expect(rig.status == .on(factor: 1.6))
    }

    @Test(arguments: [1.0, 0.5, 0, -2, .nan])
    func `a request of 1 or less does nothing while off`(factor: Double) {
        var rig = Rig()
        #expect(rig.request(factor) == [])
        #expect(rig.status == .off)
    }

    @Test func `enough headroom turns engaging into on`() {
        var rig = Rig()
        rig.request(1.5)
        rig.now += 0.5
        #expect(rig.headroom(1.2) == [.show(factor: 0.98 * 1.2, rampSeconds: Rig.ramp)])
        #expect(rig.status == .engaging)
        rig.now += 1
        #expect(rig.headroom(Rig.fullHeadroom) == [.show(factor: 1.5, rampSeconds: Rig.ramp), .publish(.on(factor: 1.5))])
    }

    @Test func `headroom within 0.02 of the target counts as engaged`() {
        var rig = Rig()
        rig.request(1.5)
        rig.now += 1
        rig.headroom(1.49)
        #expect(rig.status == .on(factor: 0.98 * 1.49))
    }

    @Test func `after the timeout any visible factor is good enough`() {
        var rig = Rig()
        rig.request(1.5)
        rig.now += 0.5
        #expect(shows(rig.headroom(1.3)) == [0.98 * 1.3])
        #expect(rig.tick(after: 9.25) == [])
        #expect(rig.status == .engaging)
        #expect(rig.tick(after: 0.25) == [.publish(.on(factor: 0.98 * 1.3))])
    }

    @Test func `no headroom by the timeout hides and backs off as unavailable`() {
        var rig = Rig()
        rig.request(1.5)
        rig.headroom(1.0)
        #expect(rig.tick(after: 10) == [.hide(rampSeconds: Rig.ramp), .publish(.unavailable)])
        #expect(rig.machine.needsTicks)
        #expect(rig.tick(after: 29.75) == [])
        #expect(rig.tick(after: 0.25) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
    }

    @Test func `a factor of 1.01 or less at the timeout is a failed try`() {
        var rig = Rig()
        rig.request(1.5)
        rig.now += 0.5
        #expect(shows(rig.headroom(1.03)) == [0.98 * 1.03])
        #expect(rig.status == .engaging)
        #expect(rig.tick(after: 9.5) == [.hide(rampSeconds: Rig.ramp), .publish(.unavailable)])
    }

    @Test func `a factor just over 1.01 at the timeout counts as on`() {
        var rig = Rig()
        rig.request(1.5)
        rig.now += 0.5
        #expect(shows(rig.headroom(1.035)) == [0.98 * 1.035])
        #expect(rig.tick(after: 9.5) == [.publish(.on(factor: 0.98 * 1.035))])
    }

    @Test func `headroom that meets a small target without a visible factor keeps engaging`() {
        var rig = Rig()
        rig.request(1.01)
        rig.now += 0.5
        #expect(rig.headroom(1.0) == [])
        #expect(rig.headroom(1.02) == [])
        #expect(rig.status == .engaging)
        #expect(rig.headroom(1.04) == [.show(factor: 1.01, rampSeconds: Rig.ramp), .publish(.on(factor: 1.01))])
    }

    @Test func `a tiny request that is fully met is on`() {
        var rig = Rig()
        rig.request(1.003)
        rig.now += 0.5
        #expect(rig.headroom(Rig.fullHeadroom) == [.show(factor: 1.003, rampSeconds: Rig.ramp), .publish(.on(factor: 1.003))])
        rig.headroom(1.0)
        rig.tick(after: 10)
        #expect(rig.status == .engaging)
    }

    @Test func `three strikes make Boost unavailable`() {
        var rig = Rig()
        rig.failEngage()
        #expect(rig.machine.needsTicks)
        #expect(rig.run(for: 30) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
        rig.headroom(1.0)
        #expect(rig.tick(after: 10) == [.hide(rampSeconds: Rig.ramp), .publish(.unavailable)])
        #expect(rig.machine.needsTicks)
        rig.run(for: 30)
        rig.headroom(1.0)
        #expect(rig.tick(after: 10) == [.hide(rampSeconds: Rig.ramp), .publish(.unavailable)])
        #expect(!rig.machine.needsTicks)
        #expect(rig.run(for: 120) == [])
        #expect(rig.status == .unavailable)
    }

    @Test func `a new request retries after unavailable`() {
        var rig = Rig(.init(maxStrikes: 1))
        rig.failEngage()
        #expect(rig.status == .unavailable)
        #expect(rig.request(1.6) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
        rig.headroom(1.0)
        #expect(rig.tick(after: 10) == [.hide(rampSeconds: Rig.ramp), .publish(.unavailable)])
    }

    @Test func `a request during back-off doesn't cut it short`() {
        var rig = Rig()
        rig.failEngage()
        rig.now += 5
        #expect(rig.request(1.6) == [])
        #expect(rig.tick(after: 24.75) == [])
        #expect(rig.tick(after: 0.25) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
    }

    @Test func `a successful engage clears the strikes`() {
        var rig = Rig()
        rig.failEngage()
        rig.run(for: 30)
        rig.headroom(1.0)
        rig.tick(after: 10)
        rig.run(for: 30)
        rig.headroom(Rig.fullHeadroom)
        #expect(rig.status == .on(factor: 1.5))
        #expect(rig.send(.engineFailed) == [.hide(rampSeconds: 0), .publish(.unavailable)])
        // Strike one of three: back-off, then another try.
        #expect(rig.machine.needsTicks)
        #expect(shows(rig.run(for: 30)) == [1])
    }

    @Test func `going back to 100 percent ends the attempt and its strikes`() {
        var rig = Rig(.init(maxStrikes: 2))
        rig.failEngage()
        #expect(rig.request(1) == [.publish(.off)])
        rig.failEngage()
        // Strike one of two again: backing off, not given up.
        #expect(rig.status == .unavailable)
        #expect(rig.machine.needsTicks)
        rig.run(for: 30)
        #expect(rig.status == .engaging)
    }

    // MARK: Engine failures

    @Test func `an engine failure hides at once and counts as a strike`() {
        var rig = Rig(.init(maxStrikes: 2))
        rig.request(1.5)
        #expect(rig.send(.engineFailed) == [.hide(rampSeconds: 0), .publish(.unavailable)])
        #expect(rig.machine.needsTicks)
        rig.run(for: 30)
        #expect(rig.send(.engineFailed) == [.hide(rampSeconds: 0), .publish(.unavailable)])
        #expect(!rig.machine.needsTicks)
    }

    @Test func `an engine failure with no overlay up is ignored`() {
        var rig = Rig()
        #expect(rig.send(.engineFailed) == [])
        rig.failEngage()
        #expect(rig.send(.engineFailed) == [])
        #expect(rig.status == .unavailable)
        #expect(rig.machine.needsTicks)
    }

    // MARK: Caps

    @Test func `the factor never passes the fixed ceiling`() {
        var rig = Rig()
        #expect(shows(rig.request(3)) == [1])
        rig.now += 0.5
        #expect(shows(rig.headroom(16)) == [1.67])
        #expect(rig.status == .on(factor: 1.67))
    }

    @Test func `the factor never passes 98 percent of the headroom`() {
        var rig = Rig()
        rig.engage(1.6)
        var lastHeadroom = Rig.fullHeadroom
        for headroom in [2.4, 1.5, 1.9, 1.2, 1.05, 3.0, 1.62, 1.4] {
            rig.now += 0.3
            let factors = shows(rig.headroom(headroom))
            lastHeadroom = headroom
            for factor in factors { #expect(factor <= 0.98 * lastHeadroom) }
            if case .on(let factor) = rig.status { #expect(factor <= 0.98 * lastHeadroom) } else { Issue.record("not on") }
        }
    }

    @Test func `falling headroom lowers the factor with a ramp`() {
        var rig = Rig()
        rig.engage(1.6)
        rig.now += 1
        #expect(rig.headroom(1.3) == [.show(factor: 0.98 * 1.3, rampSeconds: Rig.ramp), .publish(.on(factor: 0.98 * 1.3))])
        rig.now += 1
        #expect(rig.headroom(Rig.fullHeadroom) == [.show(factor: 1.6, rampSeconds: Rig.ramp), .publish(.on(factor: 1.6))])
    }

    @Test func `headroom falling to 1 never dims and shows as engaging until it comes back`() {
        var rig = Rig()
        rig.engage()
        rig.now += 1
        #expect(rig.headroom(1.0) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
        #expect(!rig.machine.needsTicks)
        rig.now += 1
        #expect(rig.headroom(0.5) == [])
        #expect(rig.headroom(1.03) == [.show(factor: 0.98 * 1.03, rampSeconds: Rig.ramp), .publish(.on(factor: 0.98 * 1.03))])
    }

    @Test func `on is never published with a factor of 1.005 or less`() {
        var rig = Rig()
        rig.engage()
        for headroom in stride(from: 2.66, through: 0.9, by: -0.003) {
            rig.now += 0.3
            for command in rig.headroom(headroom) {
                if case .publish(.on(let factor)) = command { #expect(factor > 1.005) }
            }
            if case .on(let factor) = rig.status { #expect(factor > 1.005) }
        }
        #expect(rig.status == .engaging)
    }

    @Test(arguments: [Double.nan, 0, -1, .infinity])
    func `nonsense headroom is ignored`(headroom: Double) {
        var rig = Rig()
        rig.request(1.5)
        rig.now += 1
        #expect(rig.headroom(headroom) == [])
        #expect(rig.status == .engaging)
    }

    @Test func `serious heat below the pause level caps at 1.2`() {
        var rig = Rig()
        rig.conditions(BoostConditions(thermal: .serious), Self.hotSettings)
        #expect(shows(rig.request(1.5)) == [1])
        rig.now += 1
        #expect(shows(rig.headroom(1.25)) == [1.2])
        #expect(rig.status == .on(factor: 1.2))
    }

    @Test func `heat rising while on ramps down to the thermal cap`() {
        var rig = Rig()
        rig.conditions(BoostConditions(), Self.hotSettings)
        rig.engage()
        rig.now += 1
        #expect(rig.conditions(BoostConditions(thermal: .serious), Self.hotSettings) == [.show(factor: 1.2, rampSeconds: Rig.ramp), .publish(.on(factor: 1.2))])
        rig.now += 1
        #expect(rig.conditions(BoostConditions(thermal: .fair), Self.hotSettings) == [.show(factor: 1.5, rampSeconds: Rig.ramp), .publish(.on(factor: 1.5))])
    }

    // MARK: Blocks

    @Test func `heat at the pause level hides at once and notifies`() {
        var rig = Rig()
        rig.engage()
        #expect(rig.conditions(BoostConditions(thermal: .serious)) == [.hide(rampSeconds: 0), .notifyPaused(.hot), .publish(.blocked(.hot))])
    }

    @Test func `the hot notice goes out once per pause`() {
        var rig = Rig()
        rig.engage()
        rig.conditions(BoostConditions(thermal: .serious))
        #expect(rig.conditions(BoostConditions(thermal: .critical)) == [])
        #expect(rig.conditions(BoostConditions(thermal: .critical, screenLocked: true)) == [.publish(.blocked(.screenAsleepOrLocked))])
        #expect(rig.conditions(BoostConditions(thermal: .serious)) == [.publish(.blocked(.hot))])
        rig.request(1.6)
        #expect(rig.conditions(BoostConditions()) == [])
        #expect(rig.run(for: 10) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
        rig.now += 60
        #expect(rig.conditions(BoostConditions(thermal: .serious)) == [.hide(rampSeconds: 0), .notifyPaused(.hot), .publish(.blocked(.hot))])
    }

    @Test func `the same notice never goes out twice within the cooldown`() {
        var rig = Rig()
        rig.engage()
        #expect(rig.conditions(BoostConditions(thermal: .serious)).contains(.notifyPaused(.hot)))
        rig.conditions(BoostConditions())
        rig.run(for: 10)
        #expect(rig.status == .engaging)
        rig.now += 20
        // A new pause 30 s after the last notice: paused, but quietly.
        #expect(rig.conditions(BoostConditions(thermal: .serious)) == [.hide(rampSeconds: 0), .publish(.blocked(.hot))])
        // Another reason still gets its own notice.
        #expect(rig.conditions(BoostConditions(thermal: .serious, power: .battery(percent: 10))) == [])
        #expect(rig.conditions(BoostConditions(power: .battery(percent: 10))) == [.notifyPaused(.lowBattery), .publish(.blocked(.lowBattery))])
        rig.conditions(BoostConditions())
        rig.run(for: 10)
        rig.now += 30.25
        #expect(rig.conditions(BoostConditions(thermal: .serious)) == [.hide(rampSeconds: 0), .notifyPaused(.hot), .publish(.blocked(.hot))])
    }

    @Test func `a heat pause ends only after it stayed cool for the hold`() {
        var rig = Rig()
        rig.engage()
        rig.conditions(BoostConditions(thermal: .serious))
        #expect(!rig.machine.needsTicks)
        rig.now += 5
        #expect(rig.conditions(BoostConditions(thermal: .fair)) == [])
        #expect(rig.status == .blocked(.hot))
        #expect(rig.machine.needsTicks)
        #expect(rig.run(for: 9.75) == [])
        // Hot again just before the hold ends: the hold starts over.
        #expect(rig.conditions(BoostConditions(thermal: .serious)) == [])
        #expect(!rig.machine.needsTicks)
        rig.now += 1
        #expect(rig.conditions(BoostConditions(thermal: .nominal)) == [])
        #expect(rig.run(for: 9.75) == [])
        #expect(rig.tick(after: 0.25) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
    }

    @Test func `a flapping battery reading pauses once and resumes once`() {
        var rig = Rig()
        rig.engage()
        var commands: [BoostCommand] = []
        for percent in [29, 30, 29, 31, 29, 30, 30] {
            rig.now += 2
            commands += rig.conditions(BoostConditions(power: .battery(percent: percent)))
        }
        commands += rig.run(for: 10)
        #expect(commands == [
            .hide(rampSeconds: 0), .notifyPaused(.lowBattery), .publish(.blocked(.lowBattery)),
            .show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging),
        ])
    }

    @Test func `a hold that runs out between events ends the stretch as ticks would`() {
        func rig(ticking: Bool) -> Rig {
            var rig = Rig()
            rig.engage()
            rig.conditions(BoostConditions(thermal: .serious))
            rig.request(1)
            rig.conditions(BoostConditions())
            if ticking { rig.run(for: 15) } else { rig.now += 15 }
            rig.now += 60
            rig.conditions(BoostConditions(thermal: .serious))
            return rig
        }
        var ticked = rig(ticking: true)
        var quiet = rig(ticking: false)
        // The earlier stretch ended, so a request during the new one notifies.
        #expect(ticked.request(1.5) == [.notifyPaused(.hot), .publish(.blocked(.hot))])
        #expect(quiet.request(1.5) == [.notifyPaused(.hot), .publish(.blocked(.hot))])
    }

    @Test func `raising the heat threshold in Settings lifts a held pause at once`() {
        var rig = Rig()
        rig.engage()
        rig.conditions(BoostConditions(thermal: .serious))
        rig.conditions(BoostConditions(thermal: .fair))
        #expect(rig.status == .blocked(.hot))
        rig.now += 1
        #expect(rig.conditions(BoostConditions(thermal: .fair), Self.hotSettings) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
    }

    @Test func `a hold under a suspension needs no ticks and ends quietly`() {
        var rig = Rig()
        rig.engage()
        rig.conditions(BoostConditions(thermal: .serious))
        #expect(rig.conditions(BoostConditions(screenLocked: true)) == [.publish(.blocked(.screenAsleepOrLocked))])
        #expect(!rig.machine.needsTicks)
        rig.now += 30
        #expect(rig.conditions(BoostConditions()) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
    }

    @Test func `low battery pauses and notifies once`() {
        var rig = Rig()
        rig.engage()
        let low = BoostConditions(power: .battery(percent: 25))
        #expect(rig.conditions(low) == [.hide(rampSeconds: 0), .notifyPaused(.lowBattery), .publish(.blocked(.lowBattery))])
        #expect(rig.conditions(BoostConditions(power: .battery(percent: 24))) == [])
        #expect(rig.conditions(BoostConditions(power: .adapter)) == [])
        #expect(rig.tick(after: 9.75) == [])
        #expect(rig.tick(after: 0.25) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
    }

    @Test func `a cleared battery rail never pauses`() {
        var rig = Rig()
        var settings = BoostSettings.defaults
        settings.pauseBelowBattery = nil
        rig.conditions(BoostConditions(power: .battery(percent: 3)), settings)
        #expect(shows(rig.request(1.5)) == [1])
    }

    @Test func `a pause without a request is silent until Boost is asked for`() {
        var rig = Rig()
        #expect(rig.conditions(BoostConditions(thermal: .critical)) == [])
        #expect(rig.status == .off)
        #expect(!rig.machine.needsTicks)
        #expect(rig.request(1.5) == [.notifyPaused(.hot), .publish(.blocked(.hot))])
        #expect(rig.request(1) == [.publish(.off)])
        #expect(rig.request(1.5) == [.publish(.blocked(.hot))])
    }

    @Test(arguments: [
        (BoostConditions(lowPowerMode: true), BoostBlock.lowPower),
        (BoostConditions(reconfiguring: true), .reconfiguring),
        (BoostConditions(deskModeEngaged: true), .builtInUnavailable),
        (BoostConditions(screensAsleep: true), .screenAsleepOrLocked),
        (BoostConditions(panelSupportsBoost: false), .unsupported),
    ])
    func `silent blocks hide without a notice`(conditions: BoostConditions, block: BoostBlock) {
        var rig = Rig()
        rig.engage()
        #expect(rig.conditions(conditions) == [.hide(rampSeconds: 0), .publish(.blocked(block))])
        #expect(!rig.machine.needsTicks)
        #expect(rig.run(for: 60) == [])
    }

    @Test func `Boost switched off in Settings blocks it`() {
        var rig = Rig()
        var settings = BoostSettings.defaults
        settings.allowed = false
        rig.conditions(BoostConditions(), settings)
        #expect(rig.request(1.5) == [.publish(.blocked(.notAllowed))])
    }

    @Test func `when a block clears Boost engages again from scratch`() {
        var rig = Rig()
        rig.engage()
        rig.now += 1
        rig.conditions(BoostConditions(reconfiguring: true))
        rig.now += 3
        #expect(rig.headroom(Rig.fullHeadroom) == [])
        #expect(rig.conditions(BoostConditions()) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
        rig.now += 1
        #expect(rig.headroom(Rig.fullHeadroom) == [.show(factor: 1.5, rampSeconds: Rig.ramp), .publish(.on(factor: 1.5))])
    }

    @Test func `suspensions never count as strikes`() {
        var rig = Rig(.init(maxStrikes: 1))
        for suspension in [BoostConditions(screenLocked: true), BoostConditions(screensAsleep: true), BoostConditions(reconfiguring: true), BoostConditions(deskModeEngaged: true)] {
            rig.request(1.5)
            rig.headroom(1.0)
            rig.tick(after: 5)
            rig.conditions(suspension)
            rig.run(for: 60)
            rig.conditions(BoostConditions())
            #expect(rig.status == .engaging)
        }
        rig.headroom(1.0)
        rig.tick(after: 10)
        #expect(rig.status == .unavailable)
    }

    @Test func `back-off keeps counting through a block`() {
        var rig = Rig()
        rig.failEngage()
        rig.now += 5
        rig.conditions(BoostConditions(screenLocked: true))
        #expect(!rig.machine.needsTicks)
        rig.now += 5
        #expect(rig.conditions(BoostConditions()) == [.publish(.unavailable)])
        #expect(rig.tick(after: 19.75) == [])
        #expect(rig.tick(after: 0.25) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
    }

    @Test func `a block wins over unavailable and gives it back`() {
        var rig = Rig(.init(maxStrikes: 1))
        rig.failEngage()
        #expect(rig.conditions(BoostConditions(lowPowerMode: true)) == [.publish(.blocked(.lowPower))])
        #expect(rig.conditions(BoostConditions()) == [.publish(.unavailable)])
    }

    // MARK: Requests

    @Test func `requests within the interval are coalesced to the latest`() {
        var rig = Rig()
        rig.engage()
        rig.now += 1
        #expect(shows(rig.request(1.55)) == [1.55])
        rig.now += 0.125
        #expect(rig.request(1.6) == [.publish(.on(factor: 1.6))])
        rig.now += 0.0625
        #expect(rig.request(1.58) == [.publish(.on(factor: 1.58))])
        #expect(rig.tick(after: 0.0625) == [.show(factor: 1.58, rampSeconds: Rig.ramp)])
        #expect(rig.tick(after: 0.25) == [])
    }

    @Test func `requests spaced by the interval each go out`() {
        var rig = Rig()
        rig.engage()
        var factors: [Double] = []
        for factor in [1.1, 1.2, 1.3, 1.4] {
            rig.now += 0.25
            factors += shows(rig.request(factor))
        }
        #expect(factors == [1.1, 1.2, 1.3, 1.4])
    }

    @Test func `going back to 100 percent hides with a ramp right away`() {
        var rig = Rig()
        rig.engage()
        rig.now += 0.05
        #expect(rig.request(1) == [.hide(rampSeconds: Rig.ramp), .publish(.off)])
        #expect(!rig.machine.needsTicks)
    }

    @Test func `a new target while engaging moves the goal`() {
        var rig = Rig()
        rig.request(1.3)
        rig.now += 0.5
        rig.headroom(1.25)
        rig.now += 0.5
        #expect(rig.request(1.2) == [.show(factor: 1.2, rampSeconds: Rig.ramp), .publish(.on(factor: 1.2))])
    }

    @Test func `the ramp follows the configuration`() {
        var rig = Rig(.init(rampSeconds: 0.3))
        #expect(rig.request(1.4) == [.show(factor: 1, rampSeconds: 0.3), .publish(.engaging)])
        rig.now += 1
        #expect(rig.request(1) == [.hide(rampSeconds: 0.3), .publish(.off)])
    }

    @Test func `headroom before any overlay is ignored`() {
        var rig = Rig()
        #expect(rig.headroom(Rig.fullHeadroom) == [])
        rig.request(1.5)
        #expect(rig.status == .engaging)
    }

    // MARK: Teardown

    @Test func `teardown hides at once and stays hidden`() {
        var rig = Rig()
        rig.engage()
        #expect(rig.send(.teardown) == [.hide(rampSeconds: 0), .publish(.off)])
        #expect(!rig.machine.needsTicks)
        #expect(rig.conditions(BoostConditions(deskModeEngaged: true)) == [])
        #expect(rig.conditions(BoostConditions()) == [])
        #expect(rig.headroom(Rig.fullHeadroom) == [])
        #expect(rig.run(for: 5) == [])
        #expect(rig.request(1.5) == [.show(factor: 1, rampSeconds: Rig.ramp), .publish(.engaging)])
    }

    @Test func `teardown while paused publishes off and stays quiet`() {
        var rig = Rig()
        rig.engage()
        rig.conditions(BoostConditions(thermal: .critical))
        #expect(rig.send(.teardown) == [.publish(.off)])
        #expect(rig.request(1.5) == [.publish(.blocked(.hot))])
    }

    @Test func `teardown clears unavailable and strikes`() {
        var rig = Rig(.init(maxStrikes: 2))
        rig.failEngage()
        rig.send(.teardown)
        rig.failEngage()
        // Strike one of two, not the second: backing off.
        #expect(rig.status == .unavailable)
        #expect(rig.machine.needsTicks)
    }

    @Test func `a request of 1 after teardown keeps it hidden`() {
        var rig = Rig()
        rig.engage()
        rig.send(.teardown)
        #expect(rig.request(1) == [])
        #expect(rig.conditions(BoostConditions()) == [])
        #expect(rig.status == .off)
    }

    // MARK: Ticks

    @Test func `ticks are needed exactly while one can change something`() {
        var rig = Rig()
        #expect(!rig.machine.needsTicks)                      // off
        rig.request(1.5)
        #expect(rig.machine.needsTicks)                       // engaging
        rig.now += 0.5
        rig.headroom(Rig.fullHeadroom)
        #expect(!rig.machine.needsTicks)                      // on, settled
        rig.now += 0.125
        rig.headroom(1.3)
        #expect(rig.machine.needsTicks)                       // on, a coalesced show waits
        rig.tick(after: 0.125)
        #expect(!rig.machine.needsTicks)                      // sent
        rig.conditions(BoostConditions(lowPowerMode: true))
        #expect(!rig.machine.needsTicks)                      // blocked
        rig.conditions(BoostConditions())
        rig.headroom(1.0)
        rig.tick(after: 10)
        #expect(rig.machine.needsTicks)                       // back-off
        rig.conditions(BoostConditions(screenLocked: true))
        #expect(!rig.machine.needsTicks)                      // back-off under a block
        rig.request(1)
        #expect(!rig.machine.needsTicks)                      // off again
        rig.conditions(BoostConditions(thermal: .serious))
        rig.conditions(BoostConditions())
        #expect(!rig.machine.needsTicks)                      // a hold with nothing requested
        rig.request(1.5)
        #expect(rig.machine.needsTicks)                       // a hold that will lift the block
        rig.send(.teardown)
        #expect(!rig.machine.needsTicks)                      // torn down
    }

    @Test func `ticks while nothing needs them change nothing`() {
        var rig = Rig()
        rig.engage()
        #expect(!rig.machine.needsTicks)
        let before = rig.machine
        #expect(rig.run(for: 60) == [])
        #expect(rig.machine.status == before.status)
    }

    // MARK: Determinism

    @Test func `the same events give the same machine`() {
        var a = Rig()
        var b = Rig()
        a.engage()
        b.engage()
        #expect(a.machine == b.machine)
        a.now += 1
        a.request(1.4)
        #expect(a.machine != b.machine)
    }

    // MARK: Nits

    @Test(arguments: [2.66, 1.6, 4, 15.9])
    func `SDR white is peak over headroom`(headroom: Double) {
        #expect(NitsEstimate.sdrWhite(headroom: headroom) == 1600 / headroom)
    }

    @Test func `600 nits of SDR white give about 2.67x`() throws {
        #expect(abs(try #require(NitsEstimate.sdrWhite(headroom: 1600.0 / 600)) - 600) < 1e-9)
    }

    @Test(arguments: [1.0, 0.5, 16, 20, .nan, .infinity])
    func `no estimate at or below 1 or at the 16x cap`(headroom: Double) {
        #expect(NitsEstimate.sdrWhite(headroom: headroom) == nil)
    }
}
