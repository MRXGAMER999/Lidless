import Foundation
import Testing
@testable import LidlessCore

struct LidReadingTests {
    @Test(arguments: [(true, LidState.closed), (false, .open), (nil, .unknown)] as [(Bool?, LidState)])
    func `lid state follows the clamshell key`(closed: Bool?, expected: LidState) {
        #expect(LidState(clamshellClosed: closed) == expected)
    }

    @Test(arguments: [
        (UInt(0), false, false),
        (1, true, false),
        (2, false, true),
        (3, true, true),
    ])
    func `clamshell message bits`(argument: UInt, isClosed: Bool, causesSleep: Bool) {
        let message = ClamshellMessage(argument: argument)
        #expect(message.isClosed == isClosed)
        #expect(message.causesSleep == causesSleep)
    }

    @Test func `clamshell message type is kIOPMMessageClamshellStateChange`() {
        #expect(ClamshellMessage.messageType == 0xE003_4100)
    }
}

struct PowerReadingTests {
    @Test(arguments: [
        (85, 100, 85),
        (4321, 5000, 86),
        (50, 0, nil),
        (50, -1, nil),
        (120, 100, 100),
        (-5, 100, 0),
        (nil, 100, nil),
        (50, nil, nil),
        (Int.max, 1, 100),
    ] as [(Int?, Int?, Int?)])
    func `percent is rounded and clamped`(current: Int?, max: Int?, expected: Int?) {
        #expect(PowerSourceSample.percent(current: current, max: max) == expected)
    }

    /// IOPS hands back CoreFoundation numbers and booleans, which bridge as NSNumber.
    @Test func `this Mac's battery description`() {
        let description: [String: Any] = [
            "Type": "InternalBattery",
            "Transport Type": "Internal",
            "Name": "InternalBattery-0",
            "Power Source State": "AC Power",
            "Current Capacity": NSNumber(value: 85),
            "Max Capacity": NSNumber(value: 100),
            "Is Charging": NSNumber(value: false),
            "Is Present": NSNumber(value: true),
        ]
        #expect(PowerSourceSample(description: description) == PowerSourceSample(kind: .internalBattery, percent: 85))
    }

    @Test(arguments: [
        ("UPS", PowerSourceSample.Kind.ups),
        ("InternalBattery", .internalBattery),
        ("Network", .other),
        (nil, .other),
    ] as [(String?, PowerSourceSample.Kind)])
    func `kind comes from the type key`(type: String?, expected: PowerSourceSample.Kind) {
        var description: [String: Any] = ["Current Capacity": 40, "Max Capacity": 100]
        description["Type"] = type
        #expect(PowerSourceSample(description: description).kind == expected)
    }

    @Test func `a missing present flag means present`() {
        let sample = PowerSourceSample(description: ["Type": "InternalBattery"])
        #expect(sample.isPresent)
        #expect(sample.percent == nil)
        #expect(!PowerSourceSample(description: ["Is Present": false]).isPresent)
    }

    @Test(arguments: [
        ("AC Power", [PowerSourceSample(kind: .internalBattery, percent: 85)], PowerSource.adapter),
        ("Battery Power", [PowerSourceSample(kind: .internalBattery, percent: 64)], .battery(percent: 64)),
        ("AC Power", [], .unknown),
        ("AC Power", [PowerSourceSample(kind: .ups, percent: 100)], .unknown),
        ("UPS Power", [PowerSourceSample(kind: .ups, percent: 40)], .battery(percent: 40)),
        ("Battery Power", [PowerSourceSample(kind: .internalBattery, percent: nil)], .battery(percent: nil)),
        ("AC Power", [PowerSourceSample(kind: .internalBattery, percent: 85, isPresent: false)], .unknown),
        (nil, [PowerSourceSample(kind: .internalBattery, percent: 85)], .adapter),
    ] as [(String?, [PowerSourceSample], PowerSource)])
    func `power source from the providing type and sources`(providing: String?, sources: [PowerSourceSample], expected: PowerSource) {
        #expect(PowerSource(providing: providing, sources: sources) == expected)
    }
}
