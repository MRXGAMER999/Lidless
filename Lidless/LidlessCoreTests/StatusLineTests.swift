import Foundation
import Testing
@testable import LidlessCore

struct StatusLineTests {
    @Test func `lid open with two externals on power`() {
        let segments = StatusLine.segments(lid: .open, externalCount: 2, builtInLit: true, power: .adapter)
        #expect(segments == [.lidOpen, .displayCount(3), .onPower])
    }

    @Test func `desk mode on drops the power segment`() {
        let segments = StatusLine.segments(lid: .open, externalCount: 2, builtInLit: false, power: .adapter)
        #expect(segments == [.lidOpen, .builtInOff, .displayCount(2)])
    }

    @Test func `built-in only on battery`() {
        let segments = StatusLine.segments(lid: .open, externalCount: 0, builtInLit: true, power: .battery(percent: 64))
        #expect(segments == [.builtInOnly, .onBattery(percent: 64)])
    }

    @Test func `unknown lid and power are left out`() {
        let segments = StatusLine.segments(lid: .unknown, externalCount: 1, builtInLit: true, power: .unknown)
        #expect(segments == [.displayCount(2)])
    }

    /// Desk Mode is unavailable with the lid closed, so it reports the built-in as lit.
    @Test(arguments: [true, false])
    func `a closed lid never counts the built-in screen`(builtInLit: Bool) {
        let segments = StatusLine.segments(lid: .closed, externalCount: 2, builtInLit: builtInLit, power: .adapter)
        #expect(segments == [.lidClosed, .displayCount(2), .onPower])
    }

    @Test func `battery level is left out when unknown`() {
        let segments = StatusLine.segments(lid: .open, externalCount: 0, builtInLit: true, power: .battery(percent: nil))
        #expect(segments == [.builtInOnly, .onBattery(percent: nil)])
    }
}

struct ResolutionClassTests {
    @Test(arguments: [
        (5120, 2880, "5K"),
        (3840, 2160, "4K"),
        (2560, 1440, "1440p"),
        (1920, 1080, "1080p"),
        (6016, 3384, "6K"),
        (3440, 1440, "UWQHD"),
        (1280, 800, "1280×800"),
        (4096, 2160, "4K"),
        (7680, 4320, "8K"),
        (2560, 1600, "1600p"),
        (2160, 3840, "4K"),
        (1080, 1920, "1080p"),
        (0, 0, "0×0"),
    ])
    func `names common panel sizes`(width: Int, height: Int, expected: String) {
        #expect(ResolutionClass.name(width: width, height: height) == expected)
    }

    @Test(arguments: [
        (5120, 1440, "1440p"),
        (3840, 1080, "1080p"),
        (3840, 1600, "1600p"),
        (2560, 1080, "1080p"),
        (5120, 2160, "2160p"),
        (7680, 2160, "2160p"),
        (1440, 3440, "UWQHD"),
    ])
    func `ultrawides are named by their height`(width: Int, height: Int, expected: String) {
        #expect(ResolutionClass.name(width: width, height: height) == expected)
    }
}

struct ThermalLevelTests {
    @Test(arguments: zip(
        [ProcessInfo.ThermalState.nominal, .fair, .serious, .critical],
        [ThermalLevel.nominal, .fair, .serious, .critical]
    ))
    func `maps every process thermal state`(state: ProcessInfo.ThermalState, expected: ThermalLevel) {
        #expect(ThermalLevel(state) == expected)
    }

    @Test func `levels are ordered by heat`() {
        #expect(ThermalLevel.nominal < .fair)
        #expect(ThermalLevel.serious < .critical)
    }
}
