import Foundation

/// Says when `ProcessInfo.thermalState` changes.
final class ThermalMonitor {
    // Non-Sendable handle removed in deinit.
    nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

    var isObserving: Bool { observer != nil }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard observer == nil else { return }
        // Foundation only posts the notification to processes that have read the state.
        _ = ProcessInfo.processInfo.thermalState
        // Posted on a global queue; queue: nil would run the block there and trap.
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
