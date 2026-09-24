import Testing
@testable import LidlessCore

struct DisplayInventoryTests {
    typealias Fixtures = DisplayFixtures

    func inventory(_ facts: [DisplayFacts], previousBuiltIn: DisplayDescriptor? = nil) -> DisplayInventory {
        DisplayInventory(facts: facts, previousBuiltIn: previousBuiltIn, names: Fixtures.names)
    }

    func external(_ id: UInt32, uuid: String, originX: Double, isMain: Bool = false) -> DisplayFacts {
        var facts = Fixtures.lg
        facts.displayID = id
        facts.uuid = uuid
        facts.originX = originX
        facts.isMain = isMain
        return facts
    }

    @Test func `this Mac's snapshot gives the expected descriptors`() {
        let result = inventory(Fixtures.thisMac)
        #expect(result.builtIn == DisplayDescriptor(
            id: Fixtures.builtInUUID, displayID: 1, name: "Built-in Retina Display", isBuiltIn: true,
            pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120, role: .extended,
            isVirtual: false, supportsBoost: true, brightnessControl: .native
        ))
        #expect(result.externals == [DisplayDescriptor(
            id: Fixtures.lgUUID, displayID: 2, name: "LG ULTRAGEAR", isBuiltIn: false,
            pixelWidth: 1920, pixelHeight: 1080, refreshRate: 144, role: .main,
            isVirtual: false, supportsBoost: false, brightnessControl: .ddc
        )])
        #expect(result.builtInOnline)
        #expect(!result.builtInPresetLocksBrightness)
        #expect(result.usableExternalCount == 1)
        #expect(result.virtualCount == 0)
        #expect(result.externals.first?.resolutionClass == "1080p")
    }

    @Test func `the main display comes first, then left to right`() {
        let result = inventory([
            external(3, uuid: "A", originX: 1920, isMain: true),
            external(4, uuid: "B", originX: 0),
            external(5, uuid: "C", originX: -2560),
            external(6, uuid: "D", originX: 0),
        ])
        #expect(result.externals.map(\.id) == ["A", "C", "B", "D"])
        #expect(result.usableExternalCount == 4)
    }

    /// Two identical monitors can share a UUID, and SwiftUI rows need unique IDs.
    @Test func `duplicate UUIDs get unique IDs`() {
        let result = inventory([
            external(8, uuid: "SAME", originX: 1920),
            external(7, uuid: "SAME", originX: 0),
        ])
        #expect(result.externals.map(\.id) == ["SAME", "SAME#8"])
        #expect(result.externals.map(\.displayID) == [7, 8])
    }

    /// The panel leaves the online list while the lid is closed or Desk Mode is on.
    @Test func `the built-in stays when it drops out`() throws {
        let previous = try #require(inventory(Fixtures.thisMac).builtIn)
        let result = inventory([Fixtures.lg], previousBuiltIn: previous)
        #expect(result.builtIn == previous)
        #expect(!result.builtInOnline)
        #expect(result.externals.count == 1)
    }

    @Test func `a fresh built-in replaces the previous one`() throws {
        var older = try #require(inventory(Fixtures.thisMac).builtIn)
        older.displayID = 7
        let result = inventory(Fixtures.thisMac, previousBuiltIn: older)
        #expect(result.builtIn?.displayID == 1)
        #expect(result.builtInOnline)
    }

    @Test func `no built-in and no previous one stays nil`() {
        let result = inventory([Fixtures.lg])
        #expect(result.builtIn == nil)
        #expect(!result.builtInOnline)
    }

    @Test(arguments: [nil, "", "  \n"] as [String?])
    func `the built-in is never named Color LCD`(screenName: String?) {
        var builtIn = Fixtures.builtIn
        builtIn.screenName = screenName
        #expect(inventory([builtIn]).builtIn?.name == Fixtures.names.builtIn)
    }

    @Test(arguments: [
        ("LG ULTRAGEAR", "LG Monitor", "LG ULTRAGEAR"),
        (nil, "LG Monitor", "LG Monitor"),
        (nil, nil, "Display"),
        ("  LG ULTRAGEAR ", nil, "LG ULTRAGEAR"),
        // Blank names count as missing.
        ("", "LG Monitor", "LG Monitor"),
        (" ", "\t", "Display"),
    ] as [(String?, String?, String)])
    func `external names fall back from screen to product to a generic name`(screenName: String?, productName: String?, expected: String) {
        var lg = Fixtures.lg
        lg.screenName = screenName
        lg.productName = productName
        #expect(inventory([lg]).externals.first?.name == expected)
    }

    @Test func `virtual displays are counted, not listed`() {
        var airPlay = Fixtures.sidecar
        airPlay.displayID = 10
        airPlay.uuid = "0A1B2C3D-0000-4000-8000-00000000000A"
        airPlay.isAirPlay = true
        let result = inventory(Fixtures.thisMac + [Fixtures.sidecar, airPlay])
        #expect(result.virtualCount == 2)
        #expect(result.externals.map(\.id) == [Fixtures.lgUUID])
        #expect(result.usableExternalCount == 1)
    }

    @Test func `placeholders are ignored`() {
        let slots = [Fixtures.emptySlot(3), Fixtures.emptySlot(4), Fixtures.emptySlot(5), Fixtures.standIn]
        #expect(inventory(Fixtures.thisMac + slots) == inventory(Fixtures.thisMac))
        #expect(inventory(slots) == .empty)
    }

    @Test func `an inactive, awake external is listed but not usable`() {
        var lg = Fixtures.lg
        lg.isActive = false
        let result = inventory([lg, Fixtures.builtIn])
        #expect(result.externals.count == 1)
        #expect(result.usableExternalCount == 0)
    }

    @Test func `a reference preset locks the built-in brightness`() {
        var builtIn = Fixtures.builtIn
        builtIn.referenceHeadroom = 1
        #expect(inventory([Fixtures.lg, builtIn]).builtInPresetLocksBrightness)
    }

    @Test(arguments: [0, -60, .nan, .infinity] as [Double])
    func `an unusable refresh rate reads as nil`(refreshRate: Double) {
        var lg = Fixtures.lg
        lg.refreshRate = refreshRate
        #expect(inventory([lg]).externals.first?.refreshRate == nil)
    }

    @Test func `input order doesn't matter`() {
        let facts = Fixtures.thisMac + [Fixtures.emptySlot(3), Fixtures.sidecar, external(4, uuid: Fixtures.lgUUID, originX: 3024)]
        let expected = inventory(facts)
        #expect(inventory(facts.reversed()) == expected)
        #expect(inventory(facts.shuffled()) == expected)
        #expect(expected.externals.map(\.id) == [Fixtures.lgUUID, "\(Fixtures.lgUUID)#4"])
    }
}
