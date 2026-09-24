import Foundation
import Testing
@testable import LidlessCore

struct DeskModeRuleTests {
    static func lg(present: Bool = true, usable: Bool = true) -> ExternalPresence {
        ExternalPresence(uuid: "LG", displayID: 2, name: "LG UltraFine 27", isPresent: present, isUsable: usable)
    }

    static func studio(present: Bool = true, usable: Bool = true) -> ExternalPresence {
        ExternalPresence(uuid: "STUDIO", displayID: 3, name: "Studio Display", isPresent: present, isUsable: usable)
    }

    static func snapshot(_ externals: [ExternalPresence], power: PowerSource = .adapter, systemSleeping: Bool = false) -> DeskModeSnapshot {
        DeskModeSnapshot(externals: externals, systemSleeping: systemSleeping, power: power)
    }

    /// An engine that saw no externals at launch.
    static func engine() -> DeskModeRuleEngine {
        var engine = DeskModeRuleEngine()
        engine.baseline(snapshot([]))
        return engine
    }

    let rule = DeskModeRule()

    // MARK: Firing

    @Test func `a display plugged in fires after the delay`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 100)
        #expect(engine.pending == .init(uuid: "LG", displayName: "LG UltraFine 27", fireAt: 103))
        #expect(engine.due(now: 102.9, snapshot: Self.snapshot([Self.lg()]), rule: rule) == nil)
        #expect(engine.pending != nil)
        #expect(engine.due(now: 103, snapshot: Self.snapshot([Self.lg()]), rule: rule) == "LG UltraFine 27")
        #expect(engine.pending == nil)
        #expect(engine.due(now: 110, snapshot: Self.snapshot([Self.lg()]), rule: rule) == nil)
    }

    @Test(arguments: DeskModeRule.delayChoices)
    func `the delay is the rule's`(delay: Int) {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: DeskModeRule(delaySeconds: delay), now: 50)
        #expect(engine.pending?.fireAt == 50 + TimeInterval(delay))
    }

    @Test func `displays present at launch never fire`() {
        var engine = DeskModeRuleEngine()
        engine.baseline(Self.snapshot([Self.lg()]))
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        #expect(engine.pending == nil)
        #expect(engine.due(now: 100, snapshot: Self.snapshot([Self.lg()]), rule: rule) == nil)
    }

    @Test func `the first snapshot without a baseline is the baseline`() {
        var engine = DeskModeRuleEngine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        #expect(engine.pending == nil)
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 1)
        #expect(engine.pending?.uuid == "STUDIO")
    }

    @Test func `a baseline after wake forgets what was pending`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        engine.baseline(Self.snapshot([Self.lg()]))
        #expect(engine.pending == nil)
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 1)
        #expect(engine.pending == nil)
    }

    @Test func `snapshots during system sleep don't count and cancel`() {
        var engine = Self.engine()
        engine.baseline(Self.snapshot([Self.lg()]))
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 0)
        #expect(engine.pending?.uuid == "STUDIO")
        engine.observe(Self.snapshot([], systemSleeping: true), rule: rule, now: 1)
        #expect(engine.pending == nil)
        // Back from sleep with the same displays: nothing is new.
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 2)
        #expect(engine.pending == nil)
    }

    @Test func `a display that comes up before it is usable still counts`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg(usable: false)]), rule: rule, now: 0)
        #expect(engine.pending?.uuid == "LG")
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg()]), rule: rule) == "LG UltraFine 27")
    }

    @Test func `a pending display that isn't usable when due doesn't fire`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg(usable: false)]), rule: rule) == nil)
        #expect(engine.pending == nil)
    }

    @Test func `an absent external isn't new`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg(present: false)]), rule: rule, now: 0)
        #expect(engine.pending == nil)
    }

    @Test func `a second display doesn't push back the first`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 2)
        #expect(engine.pending?.uuid == "LG")
        #expect(engine.pending?.fireAt == 3)
    }

    @Test func `a second display takes over when the pending one is unplugged`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 2)
        engine.observe(Self.snapshot([Self.studio()]), rule: rule, now: 2.5)
        // Its own delay, from when it connected.
        #expect(engine.pending == .init(uuid: "STUDIO", displayName: "Studio Display", fireAt: 5))
        #expect(engine.due(now: 5, snapshot: Self.snapshot([Self.studio()]), rule: rule) == "Studio Display")
    }

    @Test func `a waiting display past its delay fires right away`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: DeskModeRule(delaySeconds: 10), now: 0)
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: DeskModeRule(delaySeconds: 10), now: 1)
        engine.observe(Self.snapshot([Self.studio()]), rule: DeskModeRule(delaySeconds: 3), now: 9)
        #expect(engine.pending?.uuid == "STUDIO")
        #expect(engine.pending?.fireAt == 9)
    }

    @Test func `a waiting display that was unplugged doesn't take over`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 1)
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 1.5)
        engine.observe(Self.snapshot([]), rule: rule, now: 2)
        #expect(engine.pending == nil)
    }

    @Test func `a waiting display the user declined doesn't take over`() {
        var engine = Self.engine()
        engine.baseline(Self.snapshot([Self.studio()]))
        engine.userDeclined(currentExternals: [Self.studio()])
        engine.observe(Self.snapshot([Self.studio(), Self.lg()]), rule: rule, now: 0)
        #expect(engine.pending?.uuid == "LG")
        engine.observe(Self.snapshot([Self.studio()]), rule: rule, now: 1)
        #expect(engine.pending == nil)
    }

    @Test func `a waiting display that no longer matches doesn't take over`() {
        var engine = Self.engine()
        let rule = DeskModeRule(onlyOnPower: true)
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 1)
        engine.observe(Self.snapshot([Self.studio()], power: .battery(percent: 70)), rule: rule, now: 2)
        #expect(engine.pending == nil)
    }

    @Test func `displays plugged in together fire once`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 1)
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg(), Self.studio()]), rule: rule) == "LG UltraFine 27")
        engine.observe(Self.snapshot([Self.studio()]), rule: rule, now: 4)
        #expect(engine.pending == nil)
    }

    // MARK: Matching

    @Test func `a rule for one display ignores the others`() {
        let rule = DeskModeRule(displayUUID: "STUDIO", displayName: "Studio Display")
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        #expect(engine.pending == nil)
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 1)
        #expect(engine.pending?.uuid == "STUDIO")
        #expect(engine.due(now: 4, snapshot: Self.snapshot([Self.lg(), Self.studio()]), rule: rule) == "Studio Display")
    }

    @Test(arguments: [
        DeskModeRule(isEnabled: false),
        DeskModeRule(action: .on),
        DeskModeRule(displayUUID: "OTHER"),
    ])
    func `a rule that doesn't apply never fires`(rule: DeskModeRule) {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        #expect(engine.pending == nil)
    }

    @Test(arguments: [
        (PowerSource.adapter, true),
        (.battery(percent: 80), false),
        (.battery(percent: nil), false),
        (.unknown, false),
    ])
    func `only on power needs the adapter`(power: PowerSource, fires: Bool) {
        var engine = Self.engine()
        let rule = DeskModeRule(onlyOnPower: true)
        engine.observe(Self.snapshot([Self.lg()], power: power), rule: rule, now: 0)
        #expect((engine.due(now: 3, snapshot: Self.snapshot([Self.lg()], power: power), rule: rule) != nil) == fires)
    }

    @Test func `battery ignores only on power when it is off`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()], power: .battery(percent: 50)), rule: rule, now: 0)
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg()], power: .battery(percent: 50)), rule: rule) == "LG UltraFine 27")
    }

    @Test func `a rule changed while pending is checked again when due`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg()]), rule: DeskModeRule(isEnabled: false)) == nil)
        #expect(engine.pending == nil)
    }

    @Test func `unplugging the charger while pending cancels an only-on-power rule`() {
        var engine = Self.engine()
        let rule = DeskModeRule(onlyOnPower: true)
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg()], power: .battery(percent: 90)), rule: rule) == nil)
    }

    // MARK: Disconnects and declines

    @Test func `unplugging the pending display cancels it`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        engine.observe(Self.snapshot([Self.lg(present: false)]), rule: rule, now: 1)
        #expect(engine.pending == nil)
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg()]), rule: rule) == nil)
    }

    @Test func `unplugging another display keeps it pending`() {
        var engine = Self.engine()
        engine.baseline(Self.snapshot([Self.studio()]))
        engine.observe(Self.snapshot([Self.studio(), Self.lg()]), rule: rule, now: 0)
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 1)
        #expect(engine.pending?.uuid == "LG")
    }

    @Test func `plugging back in fires again`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg()]), rule: rule) != nil)
        engine.observe(Self.snapshot([]), rule: rule, now: 10)
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 20)
        #expect(engine.pending?.fireAt == 23)
    }

    @Test func `a declined display doesn't fire until it reconnects`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg()]), rule: rule) != nil)
        engine.userDeclined(currentExternals: [Self.lg()])

        // A flicker that the snapshot misses doesn't count; a real unplug does.
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 5)
        #expect(engine.pending == nil)
        engine.observe(Self.snapshot([]), rule: rule, now: 6)
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 7)
        #expect(engine.pending?.uuid == "LG")
    }

    @Test func `declining while pending cancels it`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        engine.userDeclined(currentExternals: [Self.lg()])
        #expect(engine.pending == nil)
        #expect(engine.due(now: 3, snapshot: Self.snapshot([Self.lg()]), rule: rule) == nil)
    }

    @Test func `declining marks only present displays`() {
        var engine = Self.engine()
        engine.userDeclined(currentExternals: [Self.lg(), Self.studio(present: false)])
        engine.observe(Self.snapshot([Self.lg(), Self.studio()]), rule: rule, now: 0)
        #expect(engine.pending?.uuid == "STUDIO")
    }

    @Test func `a declined display dropped at a baseline is forgotten`() {
        var engine = Self.engine()
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 0)
        engine.userDeclined(currentExternals: [Self.lg()])
        engine.baseline(Self.snapshot([]))
        engine.observe(Self.snapshot([Self.lg()]), rule: rule, now: 10)
        #expect(engine.pending?.uuid == "LG")
    }

    // MARK: Saved settings

    @Test func `settings round-trip`() throws {
        let settings = DeskModeSettings(
            method: .blackout,
            askBeforeKeeping: false,
            keepAfterWake: true,
            rule: DeskModeRule(isEnabled: false, displayUUID: "LG", displayName: "LG UltraFine 27", action: .on, delaySeconds: 10, onlyOnPower: true)
        )
        let decoded = try JSONDecoder().decode(DeskModeSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func `saved settings use stable key names`() throws {
        let data = try JSONEncoder().encode(DeskModeSettings.defaults)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["method", "askBeforeKeeping", "keepAfterWake", "rule"])
        #expect(object["method"] as? String == "disconnect")
        let rule = try #require(object["rule"] as? [String: Any])
        #expect(Set(rule.keys) == ["isEnabled", "action", "delaySeconds", "onlyOnPower"])
        #expect(rule["action"] as? String == "off")
    }

    @Test func `missing settings keys fall back to the defaults`() throws {
        let empty = try JSONDecoder().decode(DeskModeSettings.self, from: Data("{}".utf8))
        #expect(empty == .defaults)

        let partial = #"{"keepAfterWake": true, "rule": {"delaySeconds": 10}}"#
        let decoded = try JSONDecoder().decode(DeskModeSettings.self, from: Data(partial.utf8))
        #expect(decoded.method == .disconnect)
        #expect(decoded.askBeforeKeeping)
        #expect(decoded.keepAfterWake)
        #expect(decoded.rule == DeskModeRule(delaySeconds: 10))
    }

    @Test func `the default rule turns the screen off 3 seconds after any display`() {
        let rule = DeskModeSettings.defaults.rule
        #expect(rule.isEnabled)
        #expect(rule.displayUUID == nil)
        #expect(rule.action == .off)
        #expect(rule.delaySeconds == 3)
        #expect(!rule.onlyOnPower)
    }
}
