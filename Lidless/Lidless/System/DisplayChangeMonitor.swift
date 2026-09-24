import AppKit
import LidlessCore

/// Says when the display arrangement may have changed. Sources:
/// - CoreGraphics reconfiguration callbacks (hotplug, mode, mirroring, main display);
/// - AppKit's screen-parameter notification, posted after `NSScreen` is rebuilt
///   (names, EDR potential);
/// - wake, because IDs can be re-issued while displays sleep and no CG callback
///   arrives then.
///
/// A hotplug arrives as a burst and an EDR ramp as a stream, so calls are
/// coalesced by `RefreshSchedule`. Registration only; nothing here changes a display.
final class DisplayChangeMonitor: DisplayChangeSource {
    private nonisolated struct Observation {
        let center: NotificationCenter
        let token: any NSObjectProtocol
    }

    private let box = DisplayCallbackBox()
    private let center: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private var schedule: RefreshSchedule
    private var onChange: (@MainActor () -> Void)?
    // deinit reads these; they're otherwise touched on the main actor only.
    nonisolated(unsafe) private var observations: [Observation] = []
    nonisolated(unsafe) private var pending: DispatchWorkItem?
    nonisolated(unsafe) private var callbackRegistered = false

    private(set) var isRunning = false

    /// Tests pass private centers, so only their own posts arrive.
    init(
        center: NotificationCenter = .default,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        schedule: RefreshSchedule = RefreshSchedule(quiet: 0.3, maxWait: 1.0)
    ) {
        self.center = center
        self.workspaceCenter = workspaceCenter
        self.schedule = schedule
    }

    deinit {
        // The C side holds a raw pointer to `box`.
        if callbackRegistered {
            CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(box).toOpaque())
        }
        for observation in observations {
            observation.center.removeObserver(observation.token)
        }
        pending?.cancel()
    }

    /// Notification observers currently registered; for tests.
    var observerCount: Int { observations.count }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.onChange = onChange

        box.handler = { [weak self] in self?.eventArrived() }
        callbackRegistered = CGDisplayRegisterReconfigurationCallback(
            displayReconfigured, Unmanaged.passUnretained(box).toOpaque()
        ) == .success

        observe(NSApplication.didChangeScreenParametersNotification, on: center)
        observe(NSWorkspace.screensDidWakeNotification, on: workspaceCenter)
        observe(NSWorkspace.didWakeNotification, on: workspaceCenter)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if callbackRegistered {
            CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(box).toOpaque())
            callbackRegistered = false
        }
        box.handler = nil
        for observation in observations {
            observation.center.removeObserver(observation.token)
        }
        observations = []
        pending?.cancel()
        pending = nil
        schedule = RefreshSchedule(quiet: schedule.quiet, maxWait: schedule.maxWait)
        onChange = nil
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.eventArrived() }
        }
        observations.append(Observation(center: center, token: token))
    }

    private func eventArrived() {
        // A hop queued by the C callback can land after stop().
        guard isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let fireAt = schedule.eventArrived(at: now)
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fire() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fireAt - now), execute: item)
    }

    private func fire() {
        guard isRunning else { return }
        pending = nil
        schedule.fired()
        onChange?()
    }
}

/// Carries the monitor's handler through the C callback's `userInfo`. The
/// handler is written and called on the main thread only.
private nonisolated final class DisplayCallbackBox: @unchecked Sendable {
    var handler: (@MainActor () -> Void)?
}

/// Captures nothing, as a C callback must. It can run off the main thread (inside
/// a configuration transaction the app itself drives, from Phase 3 on), so it
/// only hops to main.
private nonisolated func displayReconfigured(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    // The begin pass carries no detail; the end pass follows.
    guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
    let box = Unmanaged<DisplayCallbackBox>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated { box.handler?() }
    }
}
