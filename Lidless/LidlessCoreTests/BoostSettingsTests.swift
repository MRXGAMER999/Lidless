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

    @Test(arguments: [
        (500.0, 550...1000),
        (600, 650...1000), (601, 700...1000), (650, 700...1000),
        (950, 1000...1000), (960, nil), (1000, nil), (1600, nil),
        // Unknown normal maximum: the whole range.
        (0, 550...1000), (-1, 550...1000), (.nan, 550...1000), (.infinity, 550...1000),
    ] as [(Double, ClosedRange<Double>?)])
    func `the ceiling range starts one step above the panel's normal max`(normal: Double, expected: ClosedRange<Double>?) {
        #expect(BoostSettings.ceilingRange(normalMaxNits: normal) == expected)
    }

    @Test(arguments: [
        // normal max, stored 550, stored 600, stored 1000
        (500.0, 550, 600, 1000),
        (600, 650, 650, 1000),
        (950, 1000, 1000, 1000),
        (1000, nil, nil, nil),
        (.nan, 550, 600, 1000),
        (0, 550, 600, 1000),
    ] as [(Double, Double?, Double?, Double?)])
    func `the effective ceiling fits the panel`(normal: Double, at550: Double?, at600: Double?, at1000: Double?) {
        for (stored, expected) in [(550.0, at550), (600, at600), (1000, at1000)] {
            var settings = BoostSettings.defaults
            settings.ceilingNits = stored
            #expect(settings.effectiveCeiling(normalMaxNits: normal) == expected)
            #expect(BoostSettings.effectiveCeiling(stored, normalMaxNits: normal) == expected)
            // The stored value is never rewritten.
            #expect(settings.ceilingNits == stored)
        }
    }

    @Test(arguments: [
        (620.0, 650.0), (675, 700), (800, 800), (1200, 1000), (.nan, 1000), (.infinity, 1000), (-.infinity, 650),
    ])
    func `the effective ceiling snaps odd stored values`(stored: Double, expected: Double) {
        #expect(BoostSettings.effectiveCeiling(stored, normalMaxNits: 600) == expected)
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
