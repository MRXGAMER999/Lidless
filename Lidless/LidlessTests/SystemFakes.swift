import CoreGraphics
import Foundation
import LidlessCore
@testable import Lidless

// Fakes for the seams in System/SystemServices.swift, loaded with this Mac's
// real readings from `DisplayFixtures` (MacBook Pro Mac17,9 with an LG
// ULTRAGEAR over HDMI). Nothing here touches the system.

@MainActor
final class FakeDisplays: DisplayReader {
    var facts: [DisplayFacts]
    private(set) var snapshotCount = 0

    init(facts: [DisplayFacts] = DisplayFixtures.thisMac) {
        self.facts = facts
    }

    func snapshot() -> [DisplayFacts] {
        snapshotCount += 1
        return facts
    }
}

@MainActor
final class FakeDisplayChanges: DisplayChangeSource {
    private var onChange: (@MainActor () -> Void)?
    private(set) var startCount = 0
    var isRunning: Bool { onChange != nil }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard self.onChange == nil else { return }
        startCount += 1
        self.onChange = onChange
    }

    func stop() { onChange = nil }

    /// What the live monitor does after a coalesced burst of display events.
    func send() { onChange?() }
}

@MainActor
final class FakeSystem: SystemReader {
    var lidState: LidState = .open
    var powerSource: PowerSource = .adapter
    var thermalLevel: ThermalLevel = .nominal
    var modelIdentifier: String? = "Mac17,9"
    var deskModeCallsPresent = true

    func lid() -> LidState { lidState }
    func power() -> PowerSource { powerSource }
    func thermal() -> ThermalLevel { thermalLevel }
}

@MainActor
final class FakeEvents: SystemEventSource {
    private var handler: (@MainActor (SystemEvent) -> Void)?
    private(set) var startCount = 0
    var isRunning: Bool { handler != nil }

    func start(handler: @escaping @MainActor (SystemEvent) -> Void) {
        guard self.handler == nil else { return }
        startCount += 1
        self.handler = handler
    }

    func stop() { handler = nil }

    func send(_ event: SystemEvent) { handler?(event) }
}

@MainActor
final class FakeBrightness: BrightnessReader {
    var info: PanelBrightnessInfo
    /// Slider levels by display; a missing display reads nil, like an external.
    var levels: [CGDirectDisplayID: Double]
    private(set) var observed: CGDirectDisplayID?
    private(set) var observeCount = 0
    /// Every display `level(of:)` was asked about, in order.
    private(set) var reads: [CGDirectDisplayID] = []
    private var onChange: (@MainActor () -> Void)?

    init(info: PanelBrightnessInfo = DisplayFixtures.panel, levels: [CGDirectDisplayID: Double] = [1: DisplayFixtures.controlCenterLevel]) {
        self.info = info
        self.levels = levels
    }

    func panelInfo() -> PanelBrightnessInfo { info }

    func level(of display: CGDirectDisplayID) -> BrightnessLevelReading? {
        reads.append(display)
        return levels[display].map { BrightnessLevelReading(level: $0) }
    }

    @discardableResult
    func observe(_ display: CGDirectDisplayID, onChange: @escaping @MainActor () -> Void) -> Bool {
        observeCount += 1
        observed = display
        self.onChange = onChange
        return true
    }

    func stopObserving() {
        observed = nil
        onChange = nil
    }

    /// What DisplayServices does when the brightness keys are pressed.
    func sendChange() { onChange?() }
}

/// Monotonic time the tests move by hand.
@MainActor
final class FakeClock {
    var now: TimeInterval = 1_000
}

/// A controller wired to fakes, with a fake clock in the brightness store.
@MainActor
struct SystemRig {
    let clock = FakeClock()
    let model: AppModel
    let displays: FakeDisplays
    let changes = FakeDisplayChanges()
    let system = FakeSystem()
    let events = FakeEvents()
    let brightness: FakeBrightness
    let controller: SystemController

    init(
        facts: [DisplayFacts] = DisplayFixtures.thisMac,
        brightness: FakeBrightness = FakeBrightness(),
        pollInterval: TimeInterval = 0.5
    ) {
        let clock = clock
        model = AppModel(brightness: BrightnessStore(clock: { clock.now }))
        displays = FakeDisplays(facts: facts)
        self.brightness = brightness
        controller = SystemController(
            model: model,
            displays: displays,
            displayChanges: changes,
            system: system,
            systemEvents: events,
            brightness: brightness,
            names: DisplayFixtures.names,
            pollInterval: pollInterval
        )
    }

    /// The header segments the popover shows for the model right now.
    var segments: [StatusSegment] {
        StatusLine.segments(
            lid: model.system.lid,
            externalCount: model.system.externals.count,
            builtInLit: !model.deskMode.state.isOn,
            power: model.system.power
        )
    }
}

/// What the app derives from this Mac's readings. The readings themselves are
/// `DisplayFixtures` in TestSupport/, shared with LidlessCoreTests.
extension DisplayFixtures {
    /// The descriptors `builtIn` and `lg` must turn into (design §9).
    static let builtInDescriptor = DisplayDescriptor(
        id: builtInUUID, displayID: 1, name: "Built-in Retina Display", isBuiltIn: true,
        pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120, role: .extended, supportsBoost: true, brightnessControl: .native
    )

    static let lgDescriptor = DisplayDescriptor(
        id: lgUUID, displayID: 2, name: "LG ULTRAGEAR", isBuiltIn: false,
        pixelWidth: 1920, pixelHeight: 1080, refreshRate: 144, role: .main, brightnessControl: .ddc
    )

    /// Control Center's slider when the curve was measured: "51%", "≈ 140 nits".
    static let controlCenterLevel = 0.5101735
}
