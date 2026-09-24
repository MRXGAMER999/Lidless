import AppKit
import LidlessCore

/// Lid, power, heat, sleep and session events, each delivered on the main actor
/// as it happens.
final class SystemEventMonitor: SystemEventSource {
    private static let workspaceEvents: [(Notification.Name, SystemEvent)] = [
        (NSWorkspace.didWakeNotification, .didWake),
        (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
        (NSWorkspace.screensDidWakeNotification, .screensDidWake),
        (NSWorkspace.sessionDidBecomeActiveNotification, .sessionDidBecomeActive),
    ]

    private let lid = LidMonitor()
    private let power = PowerMonitor()
    private let thermal = ThermalMonitor()
    // Workspace notifications reach only observers of this center.
    private let workspaceCenter = NSWorkspace.shared.notificationCenter
    // Non-Sendable handles removed in deinit.
    nonisolated(unsafe) private var workspaceObservers: [any NSObjectProtocol] = []
    private var isStarted = false

    func start(handler: @escaping @MainActor (SystemEvent) -> Void) {
        guard !isStarted else { return }
        isStarted = true
        lid.start { handler(.lid) }
        power.start { handler(.power) }
        thermal.start { handler(.thermal) }
        // One observer per name, so the block needs nothing from the Notification.
        workspaceObservers = Self.workspaceEvents.map { name, event in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(event) }
            }
        }
    }

    func stop() {
        lid.stop()
        power.stop()
        thermal.stop()
        for observer in workspaceObservers { workspaceCenter.removeObserver(observer) }
        workspaceObservers = []
        isStarted = false
    }

    deinit {
        for observer in workspaceObservers { workspaceCenter.removeObserver(observer) }
    }
}
