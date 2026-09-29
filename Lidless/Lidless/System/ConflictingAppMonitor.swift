import AppKit
import Combine
import LidlessCore
import os

/// Posts the conflict warnings `ConflictAdvisor` decides on.
protocol ConflictNotifier: AnyObject {
    func conflict(_ notice: ConflictNotice)
}

extension UserNotifier: ConflictNotifier {}

/// Warns when another display utility that fights Lidless is running
/// (BetterDisplay, Lunar, BrightIntosh…; the table is `ConflictingApps`).
///
/// Reads the running apps at `start()` and follows launches and quits from
/// NSWorkspace. Watches the stores for Desk Mode, Boost and external dimming
/// turning on, so neither controller needs a hook. Only warns: it never quits
/// or changes the other app.
final class ConflictingAppMonitor {
    private static let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Conflicts")

    private let model: AppModel
    private weak var notifier: (any ConflictNotifier)?
    private let workspace: NSWorkspace
    private var advisor = ConflictAdvisor()
    /// Bundle identifiers of running apps, by process: two copies of an app share one.
    private var running: [pid_t: String] = [:]
    private var active: Set<ConflictFeature> = []
    /// Quiet until onboarding is done: the first warning also asks for
    /// notification permission, which shouldn't land on top of the welcome.
    private var quiet = true
    /// Kept for the app's lifetime, like the monitor itself.
    private var observers: [NSObjectProtocol] = []
    private var subscriptions: Set<AnyCancellable> = []

    /// External brightness below this counts as Lidless dimming the display.
    nonisolated static let dimmedBelow = 0.99

    init(model: AppModel, notifier: any ConflictNotifier, workspace: NSWorkspace = .shared) {
        self.model = model
        self.notifier = notifier
        self.workspace = workspace
    }

    func start() {
        guard observers.isEmpty else { return }
        for app in workspace.runningApplications {
            if let id = app.bundleIdentifier { running[app.processIdentifier] = id }
        }
        let center = workspace.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: workspace, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let pid = app?.processIdentifier, let id = app?.bundleIdentifier else { return }
                MainActor.assumeIsolated { self?.launched(id, pid: pid) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: workspace, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let pid = app?.processIdentifier else { return }
                MainActor.assumeIsolated { _ = self?.running.removeValue(forKey: pid) }
            },
        ]

        // Read the features first, so the launch warning names one that's on.
        active = currentFeatures()
        model.preferences.$general.map(\.onboardingCompleted).removeDuplicates()
            .sink { [weak self] done in if done { self?.speak() } }
            .store(in: &subscriptions)

        model.deskMode.$state.map(\.isOn).removeDuplicates()
            .sink { [weak self] on in self?.set(.deskMode, on: on) }
            .store(in: &subscriptions)
        model.boostStatus.$status.map(Self.isBoosting).removeDuplicates()
            .sink { [weak self] on in self?.set(.boost, on: on) }
            .store(in: &subscriptions)
        model.externalBrightness.$levels.map(Self.isDimming).removeDuplicates()
            .sink { [weak self] on in self?.set(.externalBrightness, on: on) }
            .store(in: &subscriptions)
    }

    /// Ends the quiet start: warns about everything already running.
    private func speak() {
        guard quiet else { return }
        quiet = false
        post(advisor.appsSeen(running.values, activeFeatures: active))
    }

    private func launched(_ bundleID: String, pid: pid_t) {
        running[pid] = bundleID
        guard !quiet else { return }
        post(advisor.appsSeen([bundleID], activeFeatures: active))
    }

    /// Warns only on a change to on; `@Published` also sends the current value
    /// when subscribing, which `start()` already covered.
    private func set(_ feature: ConflictFeature, on: Bool) {
        guard on else {
            active.remove(feature)
            return
        }
        guard active.insert(feature).inserted, !quiet else { return }
        post(advisor.featureTurnedOn(feature, runningBundleIDs: running.values))
    }

    private func post(_ notices: [ConflictNotice]) {
        for notice in notices {
            Self.log.notice("\(notice.app.name, privacy: .public) is running and conflicts with \(notice.feature.rawValue, privacy: .public)")
            notifier?.conflict(notice)
        }
    }

    private func currentFeatures() -> Set<ConflictFeature> {
        var features: Set<ConflictFeature> = []
        if model.deskMode.state.isOn { features.insert(.deskMode) }
        if Self.isBoosting(model.boostStatus.status) { features.insert(.boost) }
        if Self.isDimming(model.externalBrightness.levels) { features.insert(.externalBrightness) }
        return features
    }

    nonisolated static func isBoosting(_ status: BoostStatus) -> Bool {
        switch status {
        case .engaging, .on: true
        case .off, .blocked, .unavailable: false
        }
    }

    nonisolated static func isDimming(_ levels: [String: Double]) -> Bool {
        levels.values.contains { $0 < dimmedBelow }
    }
}
