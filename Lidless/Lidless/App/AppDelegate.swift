import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment: AppEnvironment
    /// The one model for the whole app. Views get it passed down; none create stores.
    let model: AppModel
    private(set) var statusItemController: StatusItemController?

    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "App")

    init(environment: AppEnvironment = .current) {
        self.environment = environment
        model = environment.sample.makeModel()
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
        let actions = PopoverActions(
            openSettings: { [weak self] tab in self?.openSettings(tab) },
            quit: { [weak self] in self?.quit() }
        )
        statusItemController = StatusItemController(model: model, actions: actions)
        if environment.showsPopoverAtLaunch {
            // Give the menu bar a moment to place the new item, so the panel opens under it.
            perform(#selector(openPopoverAfterLaunch), with: nil, afterDelay: 0.5)
        }
    }

    @objc private func openPopoverAfterLaunch() {
        statusItemController?.open()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
