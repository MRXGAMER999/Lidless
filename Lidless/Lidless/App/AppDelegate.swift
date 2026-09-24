import AppKit
import LidlessCore
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment: AppEnvironment
    /// The one model for the whole app. Views get it passed down; none create stores.
    let model: AppModel
    private(set) var statusItemController: StatusItemController?
    /// Feeds `model` from the system; only a normal launch has one.
    private(set) var systemController: SystemController?
    /// Desk Mode and its safety net; only a normal launch has one.
    private(set) var deskModeController: DeskModeController?
    /// Brightness Boost and external brightness; only a normal launch has one.
    private(set) var boostController: BoostController?
    private var hotKeys: HotKeyCenter?
    private var signalRestorer: SignalRestorer?
    private var notifier: UserNotifier?

    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "App")

    init(environment: AppEnvironment = .current) {
        self.environment = environment
        switch environment.dataSource {
        case .live: model = AppModel()
        case .sample(let scenario): model = scenario.makeModel()
        }
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(openSettingsFromMenu(_:)))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard environment.showsUserInterface else {
            log.info("Started without UI (tests, previews or safe mode)")
            return
        }
        var recoveredAfterCrash = false
        if environment.dataSource == .live {
            // Two copies would each hold their own display configuration and
            // fight over the crash marker.
            if let other = SingleInstance.otherInstance() {
                log.notice("Lidless is already running (pid \(other.processIdentifier, privacy: .public)); quitting")
                NSApp.terminate(nil)
                return
            }
            // Before the status item exists, so its first frame is already live.
            recoveredAfterCrash = startLive()
        }
        let actions = PopoverActions(
            openSettings: { [weak self] tab in self?.openSettings(tab) },
            quit: { [weak self] in self?.quit() }
        )
        let statusItemController = StatusItemController(model: model, actions: actions)
        statusItemController.onVisibilityChange = { [weak self] shown in
            shown ? self?.systemController?.popoverWillShow() : self?.systemController?.popoverDidClose()
        }
        self.statusItemController = statusItemController
        if environment.showsPopoverAtLaunch {
            // Give the menu bar a moment to place the new item, so the panel opens under it.
            perform(#selector(openPopoverAfterLaunch), with: nil, afterDelay: 0.5)
        }
        if recoveredAfterCrash { notifier?.recoveredAfterCrash() }
    }

    /// The live launch, in safety order: bring back a panel a crashed run left
    /// off, then read the system, then let Desk Mode and Boost act on it, then
    /// the keys and signals that end them. Returns whether a panel was restored.
    private func startLive() -> Bool {
        let markers = FileCrashMarkerStore()
        let skyLight = SkyLightDisplaySwitch()
        let blackout = BlackoutSwitch()
        let notifier = UserNotifier()
        self.notifier = notifier
        let recovery = recoverFromCrash(markers: markers, disconnect: skyLight, blackout: blackout)

        let system = SystemController.live(model: model)
        let deskMode = DeskModeController(
            model: model,
            services: DeskModeController.Services(
                builtIn: CompositeBuiltInSwitch(method: model.preferences.deskMode.method, disconnect: skyLight, blackout: blackout),
                confirmation: ConfirmationPanel(deskMode: model.deskMode),
                watchdog: SidecarWatchdog(),
                marker: markers,
                notifier: notifier,
                activity: ProcessActivityHolder(),
                hang: HangWatchdog()
            )
        )
        blackout.onCoverLost = { [weak deskMode] in deskMode?.coverLost() }
        let boost = BoostController(
            model: model,
            services: BoostController.Services(
                overlay: EDRBoostOverlay(),
                writer: DisplayServicesBrightnessWriter(),
                externals: ExternalBrightnessController(),
                keys: BrightnessKeyTap(),
                notifier: notifier,
                signals: BoostSignalMonitor()
            )
        )
        system.deskMode = deskMode
        system.boost = boost
        deskMode.boost = boost
        deskMode.start()
        boost.start()
        system.start()
        systemController = system
        deskModeController = deskMode
        boostController = boost
        if case let .unconfirmed(displayID, uuid, method) = recovery {
            // With the displays read, the machine retries until the panel is back.
            deskMode.resumeRestore(displayID: displayID, uuid: uuid, method: method)
        }

        let hotKeys = HotKeyCenter()
        deskMode.bindHotKeys(hotKeys)
        boost.bindHotKeys(hotKeys)
        self.hotKeys = hotKeys

        let signals = SignalRestorer()
        signals.install { [weak self] in
            // Boost first (it only removes windows, at once), so Desk Mode
            // ending doesn't put the overlay back up on the returning panel.
            self?.boostController?.terminate()
            self?.deskModeController?.terminate()
        }
        signalRestorer = signals
        if case .restored(let notify) = recovery { return notify }
        return false
    }

    private enum Recovery {
        case nothing
        case restored(notify: Bool)
        /// The enable wasn't confirmed: Desk Mode keeps trying once it runs.
        case unconfirmed(displayID: UInt32, uuid: String?, method: DeskModeMethod)
    }

    /// A marker from this boot means the last run died with the panel off:
    /// turn it back on before anything else. Never re-applies Desk Mode.
    private func recoverFromCrash(markers: any CrashMarkerStore, disconnect: any BuiltInSwitch, blackout: any BuiltInSwitch) -> Recovery {
        let (marker, fileExists) = markers.read()
        let decision = LaunchRecovery.decide(
            marker: marker,
            markerFileExists: fileExists,
            currentBootSession: markers.currentBootSession,
            otherInstanceRunning: marker.map { SingleInstance.isLive(pid: $0.pid) } ?? false
        )
        switch decision {
        case .nothing:
            return .nothing
        case .discard:
            log.info("Discarded a crash marker from an earlier boot")
            markers.clear()
            return .nothing
        case let .restore(displayID, uuid, method, notify):
            let panel: any BuiltInSwitch = method == .disconnect ? disconnect : blackout
            let ok = panel.enableNow(displayID: displayID, uuid: uuid, timeout: DeskModeController.exitRestoreTimeout)
            guard ok else {
                // The marker stays, so a crash before the retries succeed still
                // leaves it for the next launch.
                log.error("The last run ended with Desk Mode on (\(method.rawValue, privacy: .public)); couldn't confirm the built-in is back, retrying")
                return .unconfirmed(displayID: displayID, uuid: uuid, method: method)
            }
            log.notice("The last run ended with Desk Mode on (\(method.rawValue, privacy: .public)); the built-in is back")
            markers.clear()
            return .restored(notify: notify)
        }
    }

    @objc private func openPopoverAfterLaunch() {
        statusItemController?.open()
    }

    /// Quit from anywhere (the menu, the popover, logout): the panel comes back
    /// before the app goes.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Boost first: see the signal handler in `startLive`.
        boostController?.terminate()
        deskModeController?.terminate()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemController?.stop()
        statusItemController?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: Actions

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        openSettings(.deskMode)
    }

    private func openSettings(_ tab: SettingsTab) {
        statusItemController?.close()
        // The Settings window arrives in a later stage; this is its entry point.
        log.debug("Settings requested: \(tab.rawValue, privacy: .public)")
    }

    private func quit() {
        statusItemController?.prepareForTermination()
        NSApp.terminate(nil)
    }
}
