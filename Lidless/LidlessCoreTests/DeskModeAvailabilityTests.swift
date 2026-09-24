import Foundation
import Testing
@testable import LidlessCore

struct DeskModeAvailabilityTests {
    typealias Inputs = DeskModeAvailability.Inputs

    /// This Mac's readings, with any of them overridden.
    static func inputs(
        model: String? = "Mac17,9",
        lid: LidState = .open,
        panel: Bool = true,
        externals: Int = 1,
        calls: Bool = true
    ) -> Inputs {
        Inputs(modelIdentifier: model, lid: lid, hasBuiltInPanel: panel, usableExternalCount: externals, systemCallsPresent: calls)
    }

    @Test func `this Mac can use Desk Mode`() {
        #expect(DeskModeAvailability.reason(for: Self.inputs()) == nil)
    }

    @Test(arguments: [
        (inputs(model: "Mac15,3"), DeskModeState.UnavailableReason.unsupportedMac),
        // No clamshell key: a desktop or a VM.
        (inputs(model: "Mac14,13", lid: .unknown, panel: false), .unsupportedMac),
        (inputs(panel: false), .unsupportedMac),
        (inputs(calls: false), .unsupportedSystem),
        (inputs(lid: .closed), .lidClosed),
        (inputs(externals: 0), .needsDisplay),
    ])
    func `each reason on its own`(inputs: Inputs, expected: DeskModeState.UnavailableReason) {
        #expect(DeskModeAvailability.reason(for: inputs) == expected)
    }

    /// Permanent reasons win over passing ones, so the card doesn't flicker.
    @Test(arguments: [
        (inputs(model: "Mac15,3", lid: .closed), DeskModeState.UnavailableReason.unsupportedMac),
        (inputs(externals: 0, calls: false), .unsupportedSystem),
        (inputs(lid: .closed, externals: 0), .lidClosed),
        // A cold start with the lid closed never sees the panel.
        (inputs(lid: .closed, panel: false), .lidClosed),
        (inputs(lid: .open, panel: false, externals: 0), .unsupportedMac),
        (inputs(lid: .unknown, externals: 0, calls: false), .unsupportedMac),
    ])
    func `reasons take precedence from permanent to passing`(inputs: Inputs, expected: DeskModeState.UnavailableReason) {
        #expect(DeskModeAvailability.reason(for: inputs) == expected)
    }

    /// The Desk Mode controller owns these states, so availability leaves them alone.
    @Test(arguments: [
        DeskModeState.on(since: .distantPast, trigger: .manual),
        .switching(toOn: true),
        .switching(toOn: false),
    ])
    func `applying availability keeps on and switching`(state: DeskModeState) {
        #expect(state.applying(availability: .needsDisplay) == state)
        #expect(state.applying(availability: nil) == state)
    }

    @Test(arguments: [DeskModeState.off, .unavailable(.lidClosed), .unavailable(.needsDisplay)])
    func `applying availability maps off and unavailable`(state: DeskModeState) {
        #expect(state.applying(availability: nil) == .off)
        #expect(state.applying(availability: .needsDisplay) == .unavailable(.needsDisplay))
        #expect(state.applying(availability: .unsupportedSystem) == .unavailable(.unsupportedSystem))
    }
}

struct ScreenSleepLatchTests {
    var latch = ScreenSleepLatch()

    @Test mutating func `follows the live count while awake`() {
        #expect(!latch.screensAsleep)
        #expect(latch.count(for: 1) == 1)
        #expect(latch.count(for: 0) == 0)
        #expect(latch.count(for: 2) == 2)
    }

    /// Asleep displays can drop out of the lists, which would flash "Needs a display".
    @Test mutating func `holds the last awake count while asleep`() {
        _ = latch.count(for: 1)
        latch.screensDidSleep()
        #expect(latch.screensAsleep)
        #expect(latch.count(for: 0) == 1)
        #expect(latch.count(for: 3) == 1)
        latch.screensDidWake()
        #expect(!latch.screensAsleep)
        #expect(latch.count(for: 0) == 0)
    }

    @Test mutating func `returns the live count when asleep before any awake reading`() {
        latch.screensDidSleep()
        #expect(latch.count(for: 2) == 2)
        #expect(latch.count(for: 0) == 0)
    }
}
