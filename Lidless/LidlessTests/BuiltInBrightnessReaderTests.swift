import CoreGraphics
import Foundation
import LidlessCore
import Testing
@testable import Lidless

// Read-only: these tests read brightness and register for change callbacks.
// Calling the C callback directly is not a brightness change.

/// This Mac's online displays, from CG getters.
private enum BrightnessTestDisplays {
    static var online: [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static var builtIn: CGDirectDisplayID? {
        online.first { CGDisplayIsBuiltin($0) == 1 }
    }

    /// An external monitor macOS can't dim itself, such as one on HDMI.
    static var undimmableExternal: CGDirectDisplayID? {
        online.first { CGDisplayIsBuiltin($0) != 1 && DisplayServicesAPI.canChangeBrightness?($0) == false }
    }

    static var canObserve: Bool {
        DisplayServicesAPI.registerForBrightnessChanges != nil
    }
}

@MainActor
private final class ChangeLog {
    private(set) var count = 0
    private(set) var allOnMainThread = true

    func record() {
        count += 1
        allOnMainThread = allOnMainThread && Thread.isMainThread
    }
}

// Serialized because BrightnessChangeRelay is process-wide.
@MainActor
@Suite(.serialized)
struct BuiltInBrightnessReaderTests {
    // IDs no real display uses, so only the tests' own callbacks can reach them,
    // never a live auto-brightness change.
    private static let standIn: CGDirectDisplayID = 0x7E57_0001
    private static let otherStandIn: CGDirectDisplayID = 0xFFFF_FF02

    @Test(.enabled(if: BrightnessTestDisplays.builtIn != nil))
    func `panel info on this Mac has a curve ending at the normal max`() throws {
        let reader = DisplayServicesBrightnessReader()
        let info = reader.panelInfo()
        let userMax = try #require(info.userMaxNits)
        #expect(userMax > 0)
        let curve = try #require(info.curve)
        #expect(abs(curve.maxNits - userMax) < 0.5)
        if let outdoorMax = info.outdoorMaxNits {
            #expect(outdoorMax >= userMax)
        }
        #expect(reader.panelInfo() == info)
    }

    @Test(.enabled(if: BrightnessTestDisplays.builtIn != nil))
    func `the built-in level reads within 0…1`() throws {
        let builtIn = try #require(BrightnessTestDisplays.builtIn)
        let reading = try #require(DisplayServicesBrightnessReader().level(of: builtIn))
        #expect((0...1).contains(reading.level))
        if let linear = reading.linear {
            #expect(linear >= 0)
        }
    }

    @Test(.enabled(if: BrightnessTestDisplays.undimmableExternal != nil))
    func `monitors macOS doesn't dim read nil`() throws {
        let external = try #require(BrightnessTestDisplays.undimmableExternal)
        #expect(DisplayServicesBrightnessReader().level(of: external) == nil)
    }

    @Test(arguments: [0, 0xDEAD] as [CGDirectDisplayID])
    func `an unknown display reads nil`(display: CGDirectDisplayID) {
        #expect(DisplayServicesBrightnessReader().level(of: display) == nil)
    }

    @Test(.enabled(if: BrightnessTestDisplays.builtIn != nil && BrightnessTestDisplays.canObserve))
    func `observe returns true and stopObserving is idempotent`() throws {
        let builtIn = try #require(BrightnessTestDisplays.builtIn)
        let reader = DisplayServicesBrightnessReader()
        reader.stopObserving()
        #expect(reader.observe(builtIn) {})
        reader.stopObserving()
        reader.stopObserving()
    }

    @Test func `display 0 is never observed`() {
        let reader = DisplayServicesBrightnessReader()
        #expect(!reader.observe(0) {})
        reader.stopObserving()
    }

    @Test(.enabled(if: BrightnessTestDisplays.canObserve))
    func `callbacks coalesce into one main-actor call`() async throws {
        let reader = DisplayServicesBrightnessReader()
        defer { reader.stopObserving() }
        let log = ChangeLog()
        try #require(reader.observe(Self.standIn) { log.record() })

        await Self.deliverCallbacks(5, observer: BrightnessChangeRelay.observer(for: Self.standIn))
        try await Self.settle(until: { log.count > 0 })

        #expect(log.count == 1)
        #expect(log.allOnMainThread)
    }

    @Test(.enabled(if: BrightnessTestDisplays.canObserve))
    func `callbacks for other displays are ignored`() async throws {
        let reader = DisplayServicesBrightnessReader()
        defer { reader.stopObserving() }
        let log = ChangeLog()
        try #require(reader.observe(Self.standIn) { log.record() })

        await Self.deliverCallbacks(3, observer: BrightnessChangeRelay.observer(for: Self.otherStandIn))
        try await Self.settle()

        #expect(log.count == 0)
    }

    @Test(.enabled(if: BrightnessTestDisplays.canObserve))
    func `observing another display replaces the first`() async throws {
        let reader = DisplayServicesBrightnessReader()
        defer { reader.stopObserving() }
        let first = ChangeLog()
        let second = ChangeLog()
        try #require(reader.observe(Self.standIn) { first.record() })
        try #require(reader.observe(Self.otherStandIn) { second.record() })

        await Self.deliverCallbacks(1, observer: BrightnessChangeRelay.observer(for: Self.standIn))
        await Self.deliverCallbacks(1, observer: BrightnessChangeRelay.observer(for: Self.otherStandIn))
        try await Self.settle(until: { second.count > 0 })

        #expect(first.count == 0)
        #expect(second.count == 1)
    }

    @Test(.enabled(if: BrightnessTestDisplays.canObserve))
    func `no handler after stopObserving`() async throws {
        let reader = DisplayServicesBrightnessReader()
        let log = ChangeLog()
        try #require(reader.observe(Self.standIn) { log.record() })
        reader.stopObserving()

        await Self.deliverCallbacks(3, observer: BrightnessChangeRelay.observer(for: Self.standIn))
        try await Self.settle()

        #expect(log.count == 0)
    }

    /// Calls the C callback the way DisplayServices does: off the main thread.
    private static func deliverCallbacks(_ count: Int, observer: UnsafeRawPointer?) async {
        let bits = UInt(bitPattern: observer)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                for _ in 0..<count {
                    brightnessDidChange(nil, UnsafeMutableRawPointer(bitPattern: bits), nil, nil, nil)
                }
                done.resume()
            }
        }
    }

    /// Lets the relay's 50–100 ms debounce run: 0.3 s, extended up to 1 s while
    /// an expected call hasn't arrived (a busy test host can delay the main queue).
    private static func settle(until arrived: () -> Bool = { false }) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        try await Task.sleep(for: .milliseconds(300))
        while !arrived(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
