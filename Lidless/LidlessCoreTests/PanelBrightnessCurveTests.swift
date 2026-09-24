import Foundation
import Testing
@testable import LidlessCore

struct PanelBrightnessCurveTests {
    typealias Fixtures = DisplayFixtures

    let curve = PanelBrightnessCurve(fixed1616: Fixtures.data(hex: Fixtures.marketingTableHex))

    @Test func `this Mac's marketing table parses to 17 stops`() throws {
        let curve = try #require(self.curve)
        #expect(curve.stops.count == 17)
        for (stop, expected) in zip(curve.stops, Fixtures.marketingTableNits) {
            #expect(stop.isApproximately(expected, tolerance: 0.01))
        }
        #expect(curve.maxNits == 600)
    }

    /// Stops sit at every sixteenth of the slider, so half the slider is stop 8.
    @Test(arguments: [(0.0, 0.0), (1.0 / 16, 1.0), (0.5, 140.0), (1.0, 600.0)])
    func `levels on a stop read the stop exactly`(level: Double, nits: Double) throws {
        #expect(try #require(curve).nits(atLevel: level) == nits)
    }

    /// Control Center's 51% on this Mac; the doubling steps call for geometric interpolation.
    @Test func `levels between lit stops interpolate geometrically`() throws {
        #expect(try #require(curve).nits(atLevel: 0.5102).isApproximately(144.2, tolerance: 0.1))
    }

    @Test func `levels between an unlit and a lit stop interpolate linearly`() throws {
        #expect(try #require(curve).nits(atLevel: 1.0 / 32).isApproximately(0.5))
    }

    @Test func `nits rise with the level`() throws {
        let curve = try #require(self.curve)
        let readings = stride(from: 0.0, through: 1.0, by: 0.01).map(curve.nits(atLevel:))
        #expect(zip(readings, readings.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test(arguments: [(Double.nan, 0.0), (-0.5, 0.0), (-Double.infinity, 0.0), (1.5, 600.0), (Double.infinity, 600.0)])
    func `levels outside 0 to 1 are clamped`(level: Double, nits: Double) throws {
        #expect(try #require(curve).nits(atLevel: level) == nits)
    }

    @Test(arguments: [
        [],
        [600],
        [0, 300, 200],
        [0, 0, 0],
        [-1, 600],
        [0, .infinity],
        [.nan, 600],
    ] as [[Double]])
    func `invalid stops give no curve`(stops: [Double]) {
        #expect(PanelBrightnessCurve(stops: stops) == nil)
    }

    @Test(arguments: [
        Data(),
        Data([0, 0, 1, 0, 0, 0]),
        Data([0, 0, 0x58, 0x02]),
    ])
    func `invalid bytes give no curve`(data: Data) {
        #expect(PanelBrightnessCurve(fixed1616: data) == nil)
    }

    @Test func `a flat curve that ends lit is valid`() {
        #expect(PanelBrightnessCurve(stops: [0, 0, 500])?.maxNits == 500)
    }
}

struct PanelBrightnessInfoTests {
    typealias Fixtures = DisplayFixtures

    @Test func `this Mac's backlight properties`() throws {
        let info = PanelBrightnessInfo(backlightProperties: Fixtures.backlightProperties)
        #expect(info.userMaxNits == 600)
        #expect(info.outdoorMaxNits == 1000)
        #expect(info.peakNits == 1600)
        let curve = try #require(info.curve)
        #expect(curve.stops.count == 17)
        #expect(curve.maxNits == 600)
    }

    @Test func `missing properties are nil`() {
        #expect(PanelBrightnessInfo(backlightProperties: [:]) == PanelBrightnessInfo())
    }

    @Test func `zero or unreadable values count as absent`() {
        let zero = Data(count: 4)
        let info = PanelBrightnessInfo(backlightProperties: [
            PanelBrightnessInfo.Key.userMaxNits: zero,
            PanelBrightnessInfo.Key.outdoorMaxNits: Fixtures.data(hex: "0000c07f"), // float32 NaN
            PanelBrightnessInfo.Key.peakNits: Data([1, 2]),
            PanelBrightnessInfo.Key.curve: Data(count: 68),
        ])
        #expect(info == PanelBrightnessInfo())
    }

    @Test func `the reader fetches every key`() {
        #expect(Set(PanelBrightnessInfo.Key.all) == ["user-accessible-max-nits", "aurora-maximum-nits", "LmaxProduct", "backlight-marketing-table"])
    }

    /// IORegistry data can arrive as a slice whose indices don't start at 0.
    @Test func `values decode from a data slice`() {
        let padded = Data([0xFF, 0xFF, 0x00, 0x00, 0x58, 0x02])
        #expect(FixedPoint.fixed1616(padded.dropFirst(2)) == 600)
        #expect(FixedPoint.float32(Fixtures.data(hex: "ff00007a44").dropFirst()) == 1000)
    }
}
