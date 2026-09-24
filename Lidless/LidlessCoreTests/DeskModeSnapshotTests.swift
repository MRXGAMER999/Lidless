import Testing
@testable import LidlessCore

struct DeskModeSnapshotTests {
    typealias Fixtures = DisplayFixtures

    func snapshot(_ facts: [DisplayFacts], previous: DeskModeSnapshot? = nil, screensAsleep: Bool = false) -> DeskModeSnapshot {
        DeskModeSnapshot(
            facts: facts, previous: previous, lid: .open, screensAsleep: screensAsleep,
            systemSleeping: false, sessionActive: true, power: .adapter, names: Fixtures.names
        )
    }

    func external(_ id: UInt32, uuid: String, originX: Double, isMain: Bool = false) -> DisplayFacts {
        var facts = Fixtures.lg
        facts.displayID = id
        facts.uuid = uuid
        facts.originX = originX
        facts.isMain = isMain
        return facts
    }

    @Test func `this Mac's snapshot`() {
        let result = snapshot(Fixtures.thisMac)
        #expect(result.builtInOnline)
        #expect(result.builtInDisplayID == 1)
        #expect(result.builtInUUID == Fixtures.builtInUUID)
        #expect(!result.builtInMirrored)
        #expect(result.externals == [ExternalPresence(uuid: Fixtures.lgUUID, displayID: 2, name: "LG ULTRAGEAR", isPresent: true, isUsable: true)])
        #expect(result.usableExternals.count == 1)
        #expect(result.presentExternals.count == 1)
    }

    @Test func `the system flags are passed through`() {
        let result = DeskModeSnapshot(
            facts: Fixtures.thisMac, previous: nil, lid: .closed, screensAsleep: true,
            systemSleeping: true, sessionActive: false, power: .battery(percent: 40), names: Fixtures.names
        )
        #expect(result.lid == .closed)
        #expect(result.screensAsleep)
        #expect(result.systemSleeping)
        #expect(!result.sessionActive)
        #expect(result.power == .battery(percent: 40))
    }

    /// Desk Mode takes the panel out of the online list; the restore still needs its ID and UUID.
    @Test func `the built-in's identity is kept while it is offline`() {
        let previous = snapshot(Fixtures.thisMac)
        let result = snapshot([Fixtures.lg], previous: previous)
        #expect(!result.builtInOnline)
        #expect(result.builtInDisplayID == 1)
        #expect(result.builtInUUID == Fixtures.builtInUUID)
    }

    @Test func `no built-in and no previous one gives no identity`() {
        let result = snapshot([Fixtures.lg])
        #expect(!result.builtInOnline)
        #expect(result.builtInDisplayID == nil)
        #expect(result.builtInUUID == nil)
    }

    @Test func `a fresh built-in replaces the previous identity`() {
        var previous = snapshot(Fixtures.thisMac)
        previous.builtInDisplayID = 7
        previous.builtInUUID = "OLD"
        let result = snapshot(Fixtures.thisMac, previous: previous)
        #expect(result.builtInDisplayID == 1)
        #expect(result.builtInUUID == Fixtures.builtInUUID)
    }

    /// WindowServer's 'unkn'/'virt' stand-in claims to be built in; it must never pass for the panel.
    @Test func `the headless stand-in is neither the built-in nor an external`() {
        let result = snapshot([Fixtures.lg, Fixtures.standIn])
        #expect(!result.builtInOnline)
        #expect(result.builtInDisplayID == nil)
        #expect(result.externals.map(\.displayID) == [2])
    }

    @Test func `the stand-in alone gives no usable external`() {
        let result = snapshot([Fixtures.builtIn, Fixtures.standIn, Fixtures.emptySlot(3)])
        #expect(result.builtInOnline)
        #expect(result.externals.isEmpty)
        #expect(result.usableExternals.isEmpty)
    }

    @Test func `virtual displays never count as externals`() {
        var dummy = Fixtures.lg
        dummy.displayID = 12
        dummy.uuid = "DUMMY"
        dummy.ioLocation = nil
        dummy.isVirtualDevice = true
        var airPlay = external(13, uuid: "AIRPLAY", originX: 4000)
        airPlay.isAirPlay = true
        let result = snapshot([Fixtures.builtIn, Fixtures.sidecar, dummy, airPlay])
        #expect(result.externals.isEmpty)
    }

    /// Display sleep makes every display inactive and asleep; the monitor is still present and usable.
    @Test func `an asleep external is present and usable`() {
        var lg = Fixtures.lg
        lg.isActive = false
        lg.isAsleep = true
        let result = snapshot([lg], screensAsleep: true)
        #expect(result.externals.first?.isPresent == true)
        #expect(result.externals.first?.isUsable == true)
    }

    @Test func `an inactive, awake external is present but not usable`() {
        var lg = Fixtures.lg
        lg.isActive = false
        let result = snapshot([Fixtures.builtIn, lg])
        #expect(result.presentExternals.count == 1)
        #expect(result.usableExternals.isEmpty)
    }

    @Test func `a mirror follower counts as usable`() {
        var lg = Fixtures.lg
        lg.isActive = false
        lg.isInMirrorSet = true
        lg.mirrorsDisplay = 1
        #expect(snapshot([Fixtures.builtIn, lg]).usableExternals.count == 1)
    }

    @Test(arguments: [(true, UInt32(0)), (false, UInt32(2)), (true, UInt32(2))])
    func `a built-in in a mirror set is mirrored`(inMirrorSet: Bool, mirrorsDisplay: UInt32) {
        var builtIn = Fixtures.builtIn
        builtIn.isInMirrorSet = inMirrorSet
        builtIn.mirrorsDisplay = mirrorsDisplay
        #expect(snapshot([builtIn, Fixtures.lg]).builtInMirrored)
    }

    @Test func `the main display comes first, then left to right`() {
        let result = snapshot([
            external(3, uuid: "A", originX: 1920),
            external(4, uuid: "B", originX: 0),
            external(5, uuid: "C", originX: 3840, isMain: true),
            external(6, uuid: "D", originX: 0),
        ])
        #expect(result.externals.map(\.uuid) == ["C", "B", "D", "A"])
    }

    @Test(arguments: [
        ("LG ULTRAGEAR", "LG Monitor", "LG ULTRAGEAR"),
        (nil, "LG Monitor", "LG Monitor"),
        (nil, nil, "Display"),
        ("  LG ULTRAGEAR ", nil, "LG ULTRAGEAR"),
        ("", " ", "Display"),
    ] as [(String?, String?, String)])
    func `external names follow the popover's rule`(screenName: String?, productName: String?, expected: String) {
        var lg = Fixtures.lg
        lg.screenName = screenName
        lg.productName = productName
        #expect(snapshot([lg]).externals.first?.name == expected)
    }

    @Test func `input order doesn't matter`() {
        let facts = Fixtures.thisMac + [Fixtures.emptySlot(3), Fixtures.sidecar, Fixtures.standIn]
        #expect(snapshot(facts) == snapshot(facts.reversed()))
    }
}
