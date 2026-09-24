import Foundation
import Testing
@testable import LidlessCore

struct BoostSettingsTests {
    static func decode(_ json: String) throws -> BoostSettings {
        try JSONDecoder().decode(BoostSettings.self, from: Data(json.utf8))
    }

    static func encode(_ settings: BoostSettings) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func `the defaults match Settings › Brightness`() {
        let d = BoostSettings.defaults
        #expect(d.allowed)
        #expect(d.ceilingNits == 1000)
        #expect(d.pauseAtHeat == .serious)
        #expect(d.pauseBelowBattery == 30)
        #expect(d.wakeAtNormal)
        #expect(d.keysIntoBoost)
    }

    @Test(arguments: [
        (1000.0, 1000.0), (550, 550), (800, 800), (575, 600), (620, 600), (624.9, 600), (551, 550),
        (400, 550), (0, 550), (-50, 550), (1200, 1000), (1024, 1000),
        (.infinity, 1000), (-.infinity, 550), (.nan, 1000),
    ])
    func `the ceiling snaps to 50 nits and stays in range`(nits: Double, expected: Double) {
        var settings = BoostSettings.defaults
        settings.ceilingNits = nits
        #expect(settings.clampedCeiling == expected)
    }

    @Test func `settings survive a round trip`() throws {
        let settings = BoostSettings(allowed: false, ceilingNits: 750, pauseAtHeat: .critical, pauseBelowBattery: 10, wakeAtNormal: false, keysIntoBoost: false)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(BoostSettings.self, from: data) == settings)
    }

    @Test func `an empty save decodes to the defaults`() throws {
        #expect(try Self.decode("{}") == .defaults)
    }

    @Test func `missing keys come from the defaults`() throws {
        let settings = try Self.decode(#"{"allowed": false, "ceilingNits": 700}"#)
        var expected = BoostSettings.defaults
        expected.allowed = false
        expected.ceilingNits = 700
        #expect(settings == expected)
    }

    @Test func `a cleared battery rail is written as null and stays cleared`() throws {
        var settings = BoostSettings.defaults
        settings.pauseBelowBattery = nil
        let object = try Self.encode(settings)
        #expect(object["pauseBelowBattery"] is NSNull)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(BoostSettings.self, from: data).pauseBelowBattery == nil)
    }

    @Test func `every key is written`() throws {
        let object = try Self.encode(.defaults)
        #expect(Set(object.keys) == ["allowed", "ceilingNits", "pauseAtHeat", "pauseBelowBattery", "wakeAtNormal", "keysIntoBoost"])
    }

    @Test func `a missing battery rail gets its default`() throws {
        #expect(try Self.decode(#"{"wakeAtNormal": false}"#).pauseBelowBattery == 30)
    }

    @Test(arguments: [(5, 10), (10, 10), (40, 40), (50, 50), (90, 50)])
    func `the battery level is clamped to 10...50`(stored: Int, expected: Int) throws {
        #expect(try Self.decode(#"{"pauseBelowBattery": \#(stored)}"#).pauseBelowBattery == expected)
    }

    @Test func `a heat level below fair is raised to fair`() throws {
        #expect(try Self.decode(#"{"pauseAtHeat": 0}"#).pauseAtHeat == .fair)
        #expect(try Self.decode(#"{"pauseAtHeat": 3}"#).pauseAtHeat == .critical)
    }

    @Test func `unreadable values fall back to their defaults`() throws {
        let settings = try Self.decode(#"{"allowed": "yes", "pauseAtHeat": 9, "pauseBelowBattery": "low", "keysIntoBoost": false}"#)
        var expected = BoostSettings.defaults
        expected.keysIntoBoost = false
        #expect(settings == expected)
    }
}
