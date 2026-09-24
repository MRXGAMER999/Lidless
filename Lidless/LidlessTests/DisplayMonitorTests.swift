import AppKit
import LidlessCore
import Testing
@testable import Lidless

// Read-only: these tests query displays and post notifications, mostly to
// private centers. Nothing here changes a display or its brightness.

/// Reads the online list without the code under test.
private enum OnlineDisplays {
    static func ids() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        let capacity = count
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        guard CGGetOnlineDisplayList(capacity, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func info(_ id: CGDirectDisplayID) -> [String: Any]? {
        CoreDisplayAPI.infoDictionary?(id)?.takeRetainedValue() as? [String: Any]
    }

    static var hasBuiltIn: Bool {
        ids().contains { CGDisplayIsBuiltin($0) == 1 }
    }

    /// Not built in, and CoreDisplay calls it neither virtual nor AirPlay.
    static var hasWiredExternal: Bool {
        ids().contains { id in
            guard CGDisplayIsBuiltin(id) != 1, let info = info(id) else { return false }
            return !DisplayReadingHelpers.flag(info, DisplayReadingHelpers.InfoKey.isVirtualDevice)
                && !DisplayReadingHelpers.flag(info, DisplayReadingHelpers.InfoKey.isAirPlay)
        }
    }
}

@MainActor
struct LiveDisplayReaderTests {
    let reader = LiveDisplayReader()

    @Test func `snapshot lists every online display`() {
        #expect(reader.snapshot().map(\.displayID) == OnlineDisplays.ids())
    }

    @Test(.enabled(if: OnlineDisplays.hasBuiltIn))
    func `this Mac classifies into one built-in panel`() throws {
        let facts = reader.snapshot()
        #expect(facts.filter { DisplayClassifier.kind(of: $0) == .builtIn }.count == 1)

        let names = DisplayNames(builtIn: "Fallback built-in", unknownExternal: "Fallback external")
        let inventory = DisplayInventory(facts: facts, previousBuiltIn: nil, names: names)
        let builtIn = try #require(inventory.builtIn)
        #expect(inventory.builtInOnline)
        #expect(builtIn.isBuiltIn)
        #expect(builtIn.pixelWidth > 1 && builtIn.pixelHeight > 1)
        #expect(!builtIn.name.isEmpty)
    }

    @Test(.enabled(if: OnlineDisplays.hasBuiltIn))
    func `built-in native size is the panel, not the scaled mode`() throws {
        let builtIn = try #require(reader.snapshot().first { $0.isBuiltIn })
        let info = try #require(OnlineDisplays.info(builtIn.displayID))
        let width = try #require((info[DisplayReadingHelpers.InfoKey.pixelWidth] as? NSNumber)?.intValue)
        let height = try #require((info[DisplayReadingHelpers.InfoKey.pixelHeight] as? NSNumber)?.intValue)
        #expect(builtIn.nativePixelWidth == width)
        #expect(builtIn.nativePixelHeight == height)
    }

    @Test(.enabled(if: OnlineDisplays.hasWiredExternal))
    func `external monitors are physical`() throws {
        let externals = reader.snapshot().filter { !$0.isBuiltIn && !$0.isVirtualDevice && !$0.isAirPlay }
        try #require(!externals.isEmpty)
        for external in externals {
            #expect(external.ioLocation?.contains("/dispext") == true)
            #expect(DisplayClassifier.kind(of: external) == .physicalExternal)
            #expect(external.uuid != nil)
            #expect((external.screenName ?? external.productName) != nil)
        }
    }

    /// The test host is always 26 or later, so the snapshot never takes the
    /// fallback that macOS 12–25 users run.
    @Test func `the macOS 12–25 screen number matches the display ID`() {
        for screen in NSScreen.screens {
            #expect(LiveDisplayReader.screenNumber(of: screen) == screen.cgDirectDisplayID)
        }
    }

    @Test func `two snapshots in a row are equal`() {
        #expect(reader.snapshot() == reader.snapshot())
    }

    @Test func `later snapshots are fast`() {
        _ = reader.snapshot()
        let clock = ContinuousClock()
        let durations = (0..<5).map { _ in clock.measure { _ = reader.snapshot() } }.sorted()
        #expect(durations[durations.count / 2] < .milliseconds(20))
    }
}

struct DisplayReadingHelpersTests {
    typealias Helpers = DisplayReadingHelpers
    typealias Mode = DisplayReadingHelpers.ModeSize
    typealias Size = DisplayReadingHelpers.PixelSize

    static let builtInLocation = "IOService:/AppleARMPE/arm-io@10F00000/AppleSoCIO/disp0@88000000/IOMobileFramebufferShim"
    static let lgLocation = "IOService:/AppleARMPE/arm-io@10F00000/AppleSoCIO/dispext0@B0000000/IOMobileFramebufferShim"

    @Test(arguments: [(boolean_t(1), true), (0, false), (-1, false)])
    func `only 1 counts as true from a CoreGraphics getter`(value: boolean_t, expected: Bool) {
        #expect(Helpers.isTrue(value) == expected)
    }

    @Test(arguments: [
        ("37D8832A-2D66-02CA-B9F7-8F30A301B230", "37D8832A-2D66-02CA-B9F7-8F30A301B230"),
        ("00000000-0000-0000-0000-000000000000", nil),
        (nil, nil),
    ] as [(String?, String?)])
    func `an all-zero UUID means no panel`(uuid: String?, expected: String?) {
        #expect(Helpers.panelUUID(uuid) == expected)
    }

    @Test func `product name follows the preferred language`() {
        let info: [String: Any] = [Helpers.InfoKey.productName: ["en_US": "Color LCD", "en_GB": "Colour LCD"]]
        #expect(Helpers.productName(info, preferredLanguages: ["en-GB"]) == "Colour LCD")
        #expect(Helpers.productName(info, preferredLanguages: ["en-US"]) == "Color LCD")

        let german: [String: Any] = [Helpers.InfoKey.productName: ["de_DE": "Farb-LCD", "en_US": "Color LCD"]]
        #expect(Helpers.productName(german, preferredLanguages: ["ar"]) == "Color LCD")
    }

    @Test func `product name may be a plain string, and empty means none`() {
        let key = Helpers.InfoKey.productName
        #expect(Helpers.productName([key: "LG ULTRAGEAR"], preferredLanguages: ["en"]) == "LG ULTRAGEAR")
        #expect(Helpers.productName([key: " "], preferredLanguages: ["en"]) == nil)
        #expect(Helpers.productName([key: ["en_US": ""]], preferredLanguages: ["en"]) == nil)
        #expect(Helpers.productName([key: ["en_US": "", "de_DE": "Monitor"]], preferredLanguages: ["en"]) == "Monitor")
        #expect(Helpers.productName([:], preferredLanguages: ["en"]) == nil)
    }

    @Test func `native size is the flagged mode, not the largest or the current one`() {
        let modes = [
            Mode(pixelWidth: 3600, pixelHeight: 2338, ioFlags: 0x7),
            Mode(pixelWidth: 3024, pixelHeight: 1964, ioFlags: 0x0200_0007),
            Mode(pixelWidth: 1512, pixelHeight: 982, ioFlags: 0x0200_0003),
            Mode(pixelWidth: 1800, pixelHeight: 1169),
        ]
        let size = Helpers.nativeSize(modes: modes, info: [:], current: Mode(pixelWidth: 3600, pixelHeight: 2338))
        #expect(size == Size(width: 3024, height: 1964))
    }

    @Test func `without a native flag the size comes from CoreDisplay, then the current mode`() {
        let modes = [Mode(pixelWidth: 2048, pixelHeight: 1152), Mode(pixelWidth: 1920, pixelHeight: 1080)]
        let info: [String: Any] = [Helpers.InfoKey.pixelWidth: 1920, Helpers.InfoKey.pixelHeight: 1080]
        let current = Mode(pixelWidth: 2048, pixelHeight: 1152)
        #expect(Helpers.nativeSize(modes: modes, info: info, current: current) == Size(width: 1920, height: 1080))
        #expect(Helpers.nativeSize(modes: modes, info: [:], current: current) == Size(width: 2048, height: 1152))

        let emptySlot: [String: Any] = [Helpers.InfoKey.pixelWidth: 1, Helpers.InfoKey.pixelHeight: 1]
        #expect(Helpers.nativeSize(modes: [], info: emptySlot, current: nil) == Size(width: 0, height: 0))
    }

    @Test(arguments: [
        (120, 120, 120),
        (0, 144, 144),
        (nil, 60, 60),
        (.nan, 0, nil),
        (0, nil, nil),
    ] as [(Double?, Int?, Double?)])
    func `refresh rate falls back to the screen when the mode reports none`(mode: Double?, screen: Int?, expected: Double?) {
        #expect(Helpers.refreshRate(currentMode: mode, screenMaximumFramesPerSecond: screen) == expected)
    }

    @Test func `the built-in's readings become its facts`() {
        let raw = Helpers.RawDisplay(
            displayID: 1, uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
            vendor: 0x610, model: 0xA05E, serial: 0xFD62_6D62,
            isBuiltIn: 1, isOnline: 1, isActive: 1, isAsleep: 0, isMain: 0, isInMirrorSet: 0,
            originX: 1920,
            info: [
                Helpers.InfoKey.productName: ["en_US": "Color LCD"],
                Helpers.InfoKey.ioLocation: Self.builtInLocation,
                Helpers.InfoKey.isVirtualDevice: false,
                Helpers.InfoKey.isAirPlay: false,
            ],
            modes: [Mode(pixelWidth: 3024, pixelHeight: 1964, ioFlags: 0x0200_0007)],
            currentMode: Mode(pixelWidth: 3600, pixelHeight: 2338),
            currentRefreshRate: 120,
            screen: .init(name: "Built-in Retina Display", potentialHeadroom: 16, referenceHeadroom: 0, maximumFramesPerSecond: 120),
            canChangeBrightness: true
        )
        let expected = DisplayFacts(
            displayID: 1, uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
            vendor: 0x610, model: 0xA05E, serial: 0xFD62_6D62,
            isBuiltIn: true, originX: 1920, screenName: "Built-in Retina Display", productName: "Color LCD",
            nativePixelWidth: 3024, nativePixelHeight: 1964, refreshRate: 120,
            ioLocation: Self.builtInLocation, potentialHeadroom: 16, canChangeBrightnessNatively: true
        )
        #expect(Helpers.facts(raw, preferredLanguages: ["en-US"]) == expected)
    }

    @Test func `a display without a screen gets neutral headroom and CoreDisplay's name`() {
        let raw = Helpers.RawDisplay(
            displayID: 2, uuid: "3C1C2164-4D1D-42F7-A482-77705FA4713C",
            vendor: 0x1E6D, model: 0x5C19,
            isBuiltIn: 0, isOnline: 1, isActive: 0, isAsleep: 1, isMain: -1, isInMirrorSet: 0,
            info: [
                Helpers.InfoKey.productName: ["en_US": "LG ULTRAGEAR"],
                Helpers.InfoKey.ioLocation: Self.lgLocation,
                // Reads 1 on real monitors around display sleep.
                Helpers.InfoKey.isVirtualDevice: true,
            ],
            modes: [Mode(pixelWidth: 1920, pixelHeight: 1080, ioFlags: 0x0200_0003)],
            currentRefreshRate: 0
        )
        let facts = Helpers.facts(raw, preferredLanguages: ["en-US"])
        #expect(facts.screenName == nil)
        #expect(facts.productName == "LG ULTRAGEAR")
        #expect(facts.potentialHeadroom == 1)
        #expect(facts.referenceHeadroom == 0)
        #expect(facts.refreshRate == nil)
        #expect(!facts.isMain)
        #expect(facts.isAsleep)
        #expect(facts.isVirtualDevice)
        #expect(DisplayClassifier.kind(of: facts) == .physicalExternal)
        #expect(DisplayClassifier.isUsableExternal(facts, kind: .physicalExternal))
    }
}

@MainActor
private final class ChangeLog {
    private(set) var times: [TimeInterval] = []

    func record() {
        times.append(ProcessInfo.processInfo.systemUptime)
    }
}

/// Timing-sensitive, so one test at a time.
@MainActor
@Suite(.serialized)
struct DisplayChangeMonitorTests {
    let center = NotificationCenter()
    let workspaceCenter = NotificationCenter()

    private func makeMonitor() -> DisplayChangeMonitor {
        DisplayChangeMonitor(center: center, workspaceCenter: workspaceCenter)
    }

    private func postScreenParameters() {
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    @Test func `screen-parameter posts coalesce into one change`() async throws {
        let monitor = makeMonitor()
        let log = ChangeLog()
        var lastPost: TimeInterval = 0
        try await confirmation(expectedCount: 1) { changed in
            monitor.start {
                log.record()
                changed()
            }
            for _ in 0..<3 { postScreenParameters() }
            lastPost = uptime
            try await Task.sleep(for: .seconds(1.2))
            monitor.stop()
        }
        let delay = try #require(log.times.first) - lastPost
        #expect(delay >= 0.25 && delay < 1.0)
    }

    @Test func `a steady stream still fires within maxWait`() async throws {
        let monitor = makeMonitor()
        let log = ChangeLog()
        let firstPost = uptime
        var streamEnd: TimeInterval = 0
        try await confirmation(expectedCount: 1...3) { changed in
            monitor.start {
                log.record()
                changed()
            }
            // Never quiet for 0.3 s, so only maxWait can let a change through.
            for _ in 0..<15 {
                postScreenParameters()
                try await Task.sleep(for: .milliseconds(100))
            }
            streamEnd = uptime
            try await Task.sleep(for: .milliseconds(500))
            monitor.stop()
        }
        let first = try #require(log.times.first)
        #expect(first < streamEnd)
        #expect(first - firstPost >= 0.9 && first - firstPost < 1.3)
    }

    @Test func `stop cancels a pending change and later posts do nothing`() async throws {
        let monitor = makeMonitor()
        try await confirmation(expectedCount: 0) { changed in
            monitor.start { changed() }
            postScreenParameters()
            try await Task.sleep(for: .milliseconds(100))
            monitor.stop()
            #expect(!monitor.isRunning)
            #expect(monitor.observerCount == 0)

            postScreenParameters()
            workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await Task.sleep(for: .milliseconds(600))
        }
    }

    @Test func `start twice registers once`() async throws {
        let monitor = makeMonitor()
        try await confirmation("first handler", expectedCount: 1) { first in
            try await confirmation("second handler", expectedCount: 0) { second in
                monitor.start { first() }
                monitor.start { second() }
                #expect(monitor.isRunning)
                #expect(monitor.observerCount == 3)
                postScreenParameters()
                try await Task.sleep(for: .milliseconds(600))
                monitor.stop()
            }
        }
    }

    @Test(arguments: [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification])
    func `waking counts as a change`(name: Notification.Name) async throws {
        let monitor = makeMonitor()
        try await confirmation(expectedCount: 1) { changed in
            monitor.start { changed() }
            workspaceCenter.post(name: name, object: nil)
            try await Task.sleep(for: .milliseconds(600))
            monitor.stop()
        }
    }

    @Test func `stop before start is harmless and a stopped monitor restarts`() async throws {
        let monitor = makeMonitor()
        monitor.stop()
        #expect(!monitor.isRunning)
        try await confirmation(expectedCount: 1) { changed in
            monitor.start {}
            monitor.stop()
            monitor.start { changed() }
            postScreenParameters()
            try await Task.sleep(for: .milliseconds(600))
            monitor.stop()
        }
    }

    @Test func `the default monitor hears the app's screen-parameter notification`() async throws {
        let monitor = DisplayChangeMonitor()
        // Other posts may land in the same window, so at least one.
        try await confirmation(expectedCount: 1...) { changed in
            monitor.start { changed() }
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            try await Task.sleep(for: .milliseconds(600))
            monitor.stop()
        }
    }
}
