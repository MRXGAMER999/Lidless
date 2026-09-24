import AppKit
import Foundation
import IOKit
import LidlessCore
import notify
import Testing
@testable import Lidless

// Everything here only reads the system or posts in-process (or private
// notify(3)) notifications. Nothing changes the lid, power, sleep or a display.

/// Read independently of the code under test, so a reader bug can't switch off
/// the test that would catch it.
private enum Host {
    static let hasClamshell: Bool = {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(rootDomain) }
        return IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) != nil
    }()

    static let hasInternalBattery: Bool = {
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { IOObjectRelease(battery) }
        return battery != IO_OBJECT_NULL
    }()

    static let hwProduct: String? = {
        var size = 0
        guard sysctlbyname("hw.product", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.product", &bytes, &size, nil, 0) == 0 else { return nil }
        let text = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return text.isEmpty ? nil : text
    }()
}

@MainActor
struct LiveSystemReaderTests {
    let reader = LiveSystemReader()

    @Test func `model identifier looks like a Mac model`() throws {
        let model = try #require(reader.modelIdentifier)
        #expect(model.range(of: #"^[A-Za-z]+\d+,\d+$"#, options: .regularExpression) != nil)
        if let product = Host.hwProduct {
            #expect(model == product)
        }
    }

    @Test(arguments: [
        (Array("Mac17,9\0".utf8), "Mac17,9"),
        (Array("Mac17,9".utf8), "Mac17,9"),
        (Array("J714s\0\0\0".utf8), "J714s"),
        ([0, 65], nil),
        ([], nil),
    ] as [([UInt8], String?)])
    func `registry and sysctl bytes decode up to the first NUL`(bytes: [UInt8], expected: String?) {
        #expect(MachineInfo.string(nulTerminated: bytes) == expected)
    }

    @Test func `live reads don't trap`() {
        _ = reader.lid()
        _ = reader.power()
        #expect(reader.thermal() == ThermalLevel(ProcessInfo.processInfo.thermalState))
    }

    @Test(.enabled(if: Host.hasClamshell))
    func `a laptop reports its lid`() {
        #expect(reader.lid() != .unknown)
    }

    @Test(.enabled(if: Host.hasInternalBattery))
    func `a laptop with a battery reports adapter or a percent 0…100`() {
        let power = reader.power()
        let isValid = switch power {
        case .adapter: true
        case .battery(let percent?): (0...100).contains(percent)
        case .battery(nil), .unknown: false
        }
        #expect(isValid, "\(power)")
    }

    @available(macOS 27, *)
    @Test func `SkyLight calls are present on this macOS`() {
        #expect(reader.deskModeCallsPresent)
    }
}

/// Records events and whether each arrived on the main thread.
@MainActor
private final class EventLog {
    private(set) var events: [SystemEvent] = []
    private(set) var allOnMainThread = true

    func record(_ event: SystemEvent) {
        allOnMainThread = allOnMainThread && Thread.isMainThread
        events.append(event)
    }

    func count(of event: SystemEvent) -> Int {
        events.filter { $0 == event }.count
    }
}

/// Lets the main queue deliver until `condition` holds or `timeout` passes.
/// Throws if the test is cancelled, instead of spinning until the deadline.
@MainActor
private func settle(timeout: Duration = .seconds(2), until condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

private func postThermalChangeFromBackground() {
    DispatchQueue.global().async {
        NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }
}

// Serialized: the tests post the same process-wide notifications.
@MainActor
@Suite(.serialized)
struct SystemEventMonitorTests {
    nonisolated static let workspaceEvents: [(Notification.Name, SystemEvent)] = [
        (NSWorkspace.didWakeNotification, .didWake),
        (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
        (NSWorkspace.screensDidWakeNotification, .screensDidWake),
        (NSWorkspace.sessionDidBecomeActiveNotification, .sessionDidBecomeActive),
    ]

    @Test func `event monitor starts and stops cleanly, twice`() async throws {
        SystemEventMonitor().stop()

        let monitor = SystemEventMonitor()
        let log = EventLog()
        for round in 1...2 {
            monitor.start { log.record($0) }
            monitor.start { log.record($0) }
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            try await settle { log.count(of: .screensDidWake) >= round }
            monitor.stop()
            monitor.stop()
        }
        #expect(log.count(of: .screensDidWake) == 2)
    }

    @Test func `each OS monitor registers and unregisters`() {
        let lid = LidMonitor()
        let power = PowerMonitor()
        let thermal = ThermalMonitor()
        lid.start {}
        power.start {}
        thermal.start {}
        #expect(lid.isObserving)
        #expect(power.isObserving)
        #expect(thermal.isObserving)
        lid.stop()
        power.stop()
        thermal.stop()
        #expect(!lid.isObserving)
        #expect(!power.isObserving)
        #expect(!thermal.isObserving)
    }

    @Test func `a thermal notification posted from a background queue reaches the handler on main as thermal`() async throws {
        let monitor = SystemEventMonitor()
        let log = EventLog()
        monitor.start { log.record($0) }
        defer { monitor.stop() }

        postThermalChangeFromBackground()
        try await settle { log.count(of: .thermal) > 0 }
        #expect(log.count(of: .thermal) == 1)
        #expect(log.allOnMainThread)
    }

    @Test(arguments: workspaceEvents)
    func `workspace notifications map to events`(name: Notification.Name, expected: SystemEvent) async throws {
        let monitor = SystemEventMonitor()
        let log = EventLog()
        monitor.start { log.record($0) }
        defer { monitor.stop() }

        NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
        try await settle { log.count(of: expected) > 0 }
        let workspaceEvents = Self.workspaceEvents.map(\.1)
        #expect(log.events.filter { workspaceEvents.contains($0) } == [expected])
        #expect(log.allOnMainThread)
    }

    @Test func `no events after stop`() async throws {
        let monitor = SystemEventMonitor()
        let log = EventLog()
        monitor.start { log.record($0) }
        monitor.stop()

        for (name, _) in Self.workspaceEvents {
            NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
        }
        postThermalChangeFromBackground()
        try await settle(timeout: .milliseconds(300)) { !log.events.isEmpty }
        #expect(log.events.isEmpty)
    }

    // The IOPS names can only be posted by the system, so a private name stands
    // in to prove the notify(3) handler really runs on main.
    @Test func `a notify post reaches the power handler on main, and stops with the monitor`() async throws {
        let name = "dev.lidless.tests.power.\(UUID().uuidString)"
        let monitor = PowerMonitor(names: [name])
        let log = EventLog()
        monitor.start { log.record(.power) }

        #expect(notify_post(name) == NOTIFY_STATUS_OK)
        try await settle { log.count(of: .power) > 0 }
        #expect(log.count(of: .power) == 1)
        #expect(log.allOnMainThread)

        monitor.stop()
        notify_post(name)
        try await settle(timeout: .milliseconds(300)) { log.count(of: .power) > 1 }
        #expect(log.count(of: .power) == 1)
    }

    // The root domain sends several power messages through the lid interest;
    // only the clamshell one may reach the handler.
    @Test(arguments: [
        (ClamshellMessage.messageType, true),
        (0xE003_4110, false),
        (0xE003_4130, false),
        (0xE003_4140, false),
        (0xE002_4100, false),
    ] as [(UInt32, Bool)])
    func `the lid callback passes only clamshell messages`(messageType: UInt32, passes: Bool) throws {
        let monitor = LidMonitor()
        let log = EventLog()
        monitor.start { log.record(.lid) }
        defer { monitor.stop() }
        try #require(monitor.isObserving)

        lidInterest(Unmanaged.passUnretained(monitor).toOpaque(), IO_OBJECT_NULL, messageType, nil)
        #expect(log.events == (passes ? [.lid] : []))
    }
}
