import CoreGraphics
import Foundation
import LidlessCore
import os

/// Feeds the stores from the live system. The app delegate creates one for a
/// normal launch only; sample launches, previews, tests and safe mode never do.
///
/// It only reads: nothing here changes a display or its brightness. Desk Mode
/// gets every reading and event through `deskMode`, which decides and acts.
final class SystemController {
    /// Receives the display facts, lid, power, system events and availability
    /// after the stores are updated. Set by the app delegate in a normal launch.
    weak var deskMode: DeskModeController? {
        didSet {
            // Desk Mode re-reads the displays on its ticks, so losing the
            // external never depends on a reconfiguration callback alone.
            deskMode?.readDisplays = { [weak self] in
                guard let self, self.isRunning else { return }
                self.refreshDisplays()
            }
        }
    }

    private let model: AppModel
    private let displays: DisplayReader
    private let displayChanges: DisplayChangeSource
    private let system: SystemReader
    private let systemEvents: SystemEventSource
    private let brightness: BrightnessReader
    private let names: DisplayNames
    private let pollInterval: TimeInterval

    private(set) var inventory = DisplayInventory.empty
    private var latch = ScreenSleepLatch()
    private var panel = PanelBrightnessInfo()
    private var isRunning = false
    private var isPopoverShown = false
    /// A clamshell that reported closed has a built-in panel, even one not seen
    /// yet: after a clamshell launch the panel comes online only after the lid opens.
    private var lidSeenClosed = false
    private var observedBuiltIn: CGDirectDisplayID?
    private var pollTimer: Timer?
    /// One read when the user hold ends after the popover closed. Tests fire it by hand.
    private(set) var catchUpRead: Timer?
    private var loggedSummary: Summary?
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "System")

    init(
        model: AppModel,
        displays: DisplayReader,
        displayChanges: DisplayChangeSource,
        system: SystemReader,
        systemEvents: SystemEventSource,
        brightness: BrightnessReader,
        names: DisplayNames = .localized,
        pollInterval: TimeInterval = 0.5
    ) {
        self.model = model
        self.displays = displays
        self.displayChanges = displayChanges
        self.system = system
        self.systemEvents = systemEvents
        self.brightness = brightness
        self.names = names
        self.pollInterval = pollInterval
    }

    static func live(model: AppModel) -> SystemController {
        SystemController(
            model: model,
            displays: LiveDisplayReader(),
            displayChanges: DisplayChangeMonitor(),
            system: LiveSystemReader(),
            systemEvents: SystemEventMonitor(),
            brightness: DisplayServicesBrightnessReader()
        )
    }

    /// True while the popover is open and the built-in's level is polled.
    var isPolling: Bool { pollTimer != nil }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        panel = brightness.panelInfo()
        // The lid without judging availability: judged before the displays are
        // read, launch would publish "Not available" and then "Off".
        readSystem()
        refreshDisplays()
        refreshBrightness()
        displayChanges.start { [weak self] in self?.refreshDisplays() }
        systemEvents.start { [weak self] event in self?.handle(event) }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        displayChanges.stop()
        systemEvents.stop()
        stopBrightnessUpdates()
        cancelCatchUpRead()
    }

    func popoverWillShow() {
        isPopoverShown = true
        cancelCatchUpRead()
        if isRunning { startBrightnessUpdates() }
    }

    func popoverDidClose() {
        isPopoverShown = false
        stopBrightnessUpdates()
        // A drag the close cut short never reports its release.
        model.brightness.setTracking(false)
        scheduleCatchUpRead()
    }

    // MARK: Refresh

    func handle(_ event: SystemEvent) {
        // First, so the fresh readings below reach Desk Mode after the event
        // that explains them (a wake before the displays that came back).
        deskMode?.handle(event)
        switch event {
        case .lid, .power, .thermal:
            refreshSystem()
        case .screensDidSleep:
            latch.screensDidSleep()
        case .screensDidWake:
            latch.screensDidWake()
            // Availability once, against fresh displays: judged against the
            // snapshot from while the screens slept, the awake latch would
            // flash "Needs a display".
            readSystem()
            refreshDisplays()
        case .didWake, .sessionDidBecomeActive:
            // Lid and power events can be lost around sleep.
            readSystem()
            refreshDisplays()
        case .willSleep, .sessionDidResignActive, .willPowerOff:
            // Desk Mode's business. Nothing to read: during willSleep no
            // display call may run, and the others change no reading.
            break
        }
    }

    func refreshSystem() {
        readSystem()
        deskMode?.systemDidChange(lid: model.system.lid, power: model.system.power)
        updateAvailability()
    }

    func refreshDisplays() {
        let facts = displays.snapshot()
        let new = DisplayInventory(facts: facts, previousBuiltIn: inventory.builtIn, names: names)
        inventory = new
        model.system.update(displays: new)
        // A reference preset pins the panel's brightness, so it has no Boost range.
        let canBoost = new.builtIn?.supportsBoost == true && !new.builtInPresetLocksBrightness
        model.brightness.applyScale(BrightnessScale(panel: panel, canBoost: canBoost))
        // The facts before availability, so a lost display reads as lost
        // rather than as Desk Mode becoming unavailable.
        deskMode?.displaysDidChange(facts: facts, lid: model.system.lid, power: model.system.power)
        updateAvailability()
        // Display IDs can be re-issued; follow the built-in's.
        if isPopoverShown { startBrightnessUpdates() }
    }

    func refreshBrightness() {
        guard let id = builtInDisplayID, let reading = brightness.level(of: id) else { return }
        model.brightness.applyRead(reading)
    }

    private func readSystem() {
        let lid = system.lid()
        if lid == .closed { lidSeenClosed = true }
        model.system.update(lid: lid, power: system.power(), thermal: system.thermal())
    }

    /// Never read an offline built-in: its ID may already belong to another display.
    private var builtInDisplayID: CGDirectDisplayID? {
        inventory.builtInOnline ? inventory.builtIn?.displayID : nil
    }

    private func updateAvailability() {
        let inputs = DeskModeAvailability.Inputs(
            modelIdentifier: system.modelIdentifier,
            lid: model.system.lid,
            // Opening the lid after a clamshell launch reports the lid before
            // the panel: without the closed lid as proof, "Not available on
            // this Mac" would flash until the display refresh.
            hasBuiltInPanel: inventory.builtIn != nil || lidSeenClosed,
            usableExternalCount: latch.count(for: inventory.usableExternalCount),
            systemCallsPresent: system.deskModeCallsPresent
        )
        let reason = DeskModeAvailability.reason(for: inputs)
        model.deskMode.applyAvailability(reason)
        deskMode?.availabilityDidChange(reason)
        logSummaryIfChanged(usable: inputs.usableExternalCount)
    }

    // MARK: Brightness while the popover is open

    private func startBrightnessUpdates() {
        let id = builtInDisplayID
        if id != observedBuiltIn {
            brightness.stopObserving()
            observedBuiltIn = nil
            if let id {
                brightness.observe(id) { [weak self] in self?.refreshBrightness() }
                observedBuiltIn = id
            }
        }
        if pollTimer == nil {
            // Insurance: DisplayServices can't report a failed registration.
            // Common modes keep it running while the slider is tracked.
            let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshBrightness() }
            }
            timer.tolerance = pollInterval / 5
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
        refreshBrightness()
    }

    private func stopBrightnessUpdates() {
        pollTimer?.invalidate()
        pollTimer = nil
        if observedBuiltIn != nil {
            brightness.stopObserving()
            observedBuiltIn = nil
        }
    }

    /// Closed within the hold after a user edit, the slider would keep the edit
    /// (and the menu bar its Boost glyph) until the popover opens again, so
    /// read once more when the hold ends.
    private func scheduleCatchUpRead() {
        cancelCatchUpRead()
        guard isRunning, let remaining = model.brightness.remainingUserHold() else { return }
        let timer = Timer(timeInterval: remaining + 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.catchUpRead = nil
                self.refreshBrightness()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        catchUpRead = timer
    }

    private func cancelCatchUpRead() {
        catchUpRead?.invalidate()
        catchUpRead = nil
    }

    // MARK: Logging

    private struct Summary: Equatable {
        var desk: DeskModeState.UnavailableReason?
        var externals: Int
        var usable: Int
    }

    /// One line at launch, then one whenever availability or the external count changes.
    private func logSummaryIfChanged(usable: Int) {
        guard isRunning else { return }
        let summary = Summary(desk: model.deskMode.unavailableReason, externals: inventory.externals.count, usable: usable)
        guard summary != loggedSummary else { return }
        loggedSummary = summary

        let lid = String(describing: model.system.lid)
        let power = Self.describe(model.system.power)
        let desk = Self.describe(model.deskMode.state)
        let builtIn = inventory.builtIn == nil ? "none" : inventory.builtInOnline ? "online" : "offline"
        let scale = model.brightness.scale
        let curve = scale.curve.map { "\($0.stops.count) stops" } ?? "none"
        let externals = inventory.externals.map { "\($0.resolutionClass) \($0.role)" }.joined(separator: ", ")
        let names = inventory.externals.map(\.name).joined(separator: ", ")
        log.info("""
            Live: lid=\(lid, privacy: .public) power=\(power, privacy: .public) \
            externals=\(summary.externals, privacy: .public) usable=\(summary.usable, privacy: .public) \
            virtual=\(self.inventory.virtualCount, privacy: .public) desk=\(desk, privacy: .public) \
            builtIn=\(builtIn, privacy: .public) scale=\(Int(scale.normalMaxNits), privacy: .public)/\(Int(scale.ceilingNits), privacy: .public) \
            curve=\(curve, privacy: .public) model=\(self.system.modelIdentifier ?? "?", privacy: .public) \
            [\(externals, privacy: .public)] names=[\(names, privacy: .private)]
            """)
    }

    private static func describe(_ power: PowerSource) -> String {
        switch power {
        case .adapter: "adapter"
        case .battery(let percent): percent.map { "battery(\($0)%)" } ?? "battery"
        case .unknown: "unknown"
        }
    }

    private static func describe(_ state: DeskModeState) -> String {
        switch state {
        case .off: "off"
        case .on: "on"
        case .switching(let toOn): toOn ? "switchingOn" : "switchingOff"
        case .unavailable(let reason): String(describing: reason)
        }
    }
}

extension DisplayNames {
    /// Names for displays macOS reports without one.
    static var localized: DisplayNames {
        DisplayNames(
            builtIn: String(
                localized: "Display.Name.BuiltIn",
                defaultValue: "Built-in Display",
                comment: "Name of the Mac's own screen when macOS doesn't report one, for example while the lid is closed"
            ),
            unknownExternal: String(
                localized: "Display.Name.Unknown",
                defaultValue: "Display",
                comment: "Name of an external display that doesn't report a name"
            )
        )
    }
}
