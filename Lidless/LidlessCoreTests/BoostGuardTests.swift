import Foundation
import Testing
@testable import LidlessCore

struct BoostGuardTests {
    static let settings = BoostSettings.defaults

    static func block(_ conditions: BoostConditions, _ settings: BoostSettings = Self.settings) -> BoostBlock? {
        BoostGuard.block(conditions, settings: settings)
    }

    @Test func `nothing blocks at the desk on the adapter`() {
        #expect(Self.block(BoostConditions()) == nil)
        #expect(Self.block(BoostConditions(lid: .unknown)) == nil)
        #expect(Self.block(BoostConditions(power: .unknown)) == nil)
    }

    @Test func `Boost switched off is not allowed`() {
        var settings = Self.settings
        settings.allowed = false
        #expect(Self.block(BoostConditions(), settings) == .notAllowed)
    }

    @Test func `a panel without headroom is unsupported`() {
        #expect(Self.block(BoostConditions(panelSupportsBoost: false)) == .unsupported)
    }

    @Test(arguments: [
        BoostConditions(lid: .closed),
        BoostConditions(builtInOnline: false),
        BoostConditions(deskModeEngaged: true),
    ])
    func `the built-in is unavailable with the lid closed, offline or in Desk Mode`(conditions: BoostConditions) {
        #expect(Self.block(conditions) == .builtInUnavailable)
    }

    @Test(arguments: [
        BoostConditions(screensAsleep: true),
        BoostConditions(screenLocked: true),
        BoostConditions(sessionActive: false),
    ])
    func `sleep, lock and another user's session suspend Boost`(conditions: BoostConditions) {
        #expect(Self.block(conditions) == .screenAsleepOrLocked)
    }

    @Test func `the single conditions map to their blocks`() {
        #expect(Self.block(BoostConditions(reconfiguring: true)) == .reconfiguring)
        #expect(Self.block(BoostConditions(lowPowerMode: true)) == .lowPower)
        #expect(Self.block(BoostConditions(hdrSuppressed: true)) == .hdrSuppressed)
    }

    @Test(arguments: [
        (ThermalLevel.fair, ThermalLevel.nominal, false), (.fair, .fair, true), (.fair, .critical, true),
        (.serious, .fair, false), (.serious, .serious, true), (.serious, .critical, true),
        (.critical, .serious, false), (.critical, .critical, true),
    ])
    func `Boost pauses at or above the heat level`(pauseAt: ThermalLevel, thermal: ThermalLevel, hot: Bool) {
        var settings = Self.settings
        settings.pauseAtHeat = pauseAt
        #expect(Self.block(BoostConditions(thermal: thermal), settings) == (hot ? .hot : nil))
    }

    @Test(arguments: [
        (PowerSource.battery(percent: 29), 30 as Int?, true),
        (.battery(percent: 0), 10, true),
        (.battery(percent: 30), 30, false),
        (.battery(percent: 80), 50, false),
        (.battery(percent: nil), 30, false),
        (.battery(percent: 5), nil, false),
        (.adapter, 50, false),
        (.unknown, 50, false),
    ])
    func `Boost pauses on battery below the level`(power: PowerSource, threshold: Int?, low: Bool) {
        var settings = Self.settings
        settings.pauseBelowBattery = threshold
        #expect(Self.block(BoostConditions(power: power), settings) == (low ? .lowBattery : nil))
    }

    @Test func `blocks come in their documented order`() {
        var settings = Self.settings
        settings.allowed = false
        var c = BoostConditions(
            thermal: .critical, power: .battery(percent: 5), lowPowerMode: true, lid: .closed,
            builtInOnline: false, deskModeEngaged: true, screensAsleep: true, screenLocked: true,
            sessionActive: false, reconfiguring: true, hdrSuppressed: true, panelSupportsBoost: false
        )
        #expect(Self.block(c, settings) == .notAllowed)
        settings.allowed = true
        #expect(Self.block(c, settings) == .unsupported)
        c.panelSupportsBoost = true
        #expect(Self.block(c, settings) == .builtInUnavailable)
        c.lid = .open
        c.builtInOnline = true
        c.deskModeEngaged = false
        #expect(Self.block(c, settings) == .screenAsleepOrLocked)
        c.screensAsleep = false
        c.screenLocked = false
        c.sessionActive = true
        #expect(Self.block(c, settings) == .reconfiguring)
        c.reconfiguring = false
        #expect(Self.block(c, settings) == .hot)
        c.thermal = .nominal
        #expect(Self.block(c, settings) == .lowBattery)
        c.power = .adapter
        #expect(Self.block(c, settings) == .lowPower)
        c.lowPowerMode = false
        #expect(Self.block(c, settings) == .hdrSuppressed)
        c.hdrSuppressed = false
        #expect(Self.block(c, settings) == nil)
    }

    @Test func `only hot and low battery notify`() {
        let all: [BoostBlock] = [.hot, .lowBattery, .lowPower, .builtInUnavailable, .screenAsleepOrLocked, .reconfiguring, .hdrSuppressed, .notAllowed, .unsupported]
        #expect(all.filter(\.notifies) == [.hot, .lowBattery])
    }

    @Test(arguments: [
        (ThermalLevel.critical, ThermalLevel.nominal, Double.infinity),
        (.critical, .fair, .infinity),
        (.critical, .serious, 1.2),
        (.critical, .critical, .infinity),
        (.serious, .fair, .infinity),
        (.serious, .serious, .infinity),
        (.fair, .serious, .infinity),
    ])
    func `serious heat caps the factor only when it doesn't pause`(pauseAt: ThermalLevel, thermal: ThermalLevel, cap: Double) {
        var settings = Self.settings
        settings.pauseAtHeat = pauseAt
        #expect(BoostGuard.thermalCap(thermal, settings: settings) == cap)
    }

    @Test func `the pause rail sees heat and battery whatever else blocks`() {
        #expect(BoostGuard.pause(BoostConditions(thermal: .serious, screenLocked: true), settings: Self.settings) == .hot)
        #expect(BoostGuard.pause(BoostConditions(power: .battery(percent: 5), lid: .closed), settings: Self.settings) == .lowBattery)
        #expect(BoostGuard.pause(BoostConditions(thermal: .critical, power: .battery(percent: 5)), settings: Self.settings) == .hot)
        #expect(BoostGuard.pause(BoostConditions(thermal: .fair, power: .battery(percent: 80), lowPowerMode: true), settings: Self.settings) == nil)
    }
}
