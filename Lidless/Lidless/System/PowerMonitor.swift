import Foundation
import IOKit.ps
import LidlessCore
import notify

/// Reads the power source and battery charge from IOPowerSources (about 0.15 ms).
enum PowerReader {
    static func read() -> PowerSource {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .unknown }
        let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
        let samples = list.compactMap { source -> PowerSourceSample? in
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { return nil }
            return PowerSourceSample(description: description)
        }
        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        return PowerSource(providing: providing, sources: samples)
    }
}

/// Says when the power source or battery charge may have changed.
final class PowerMonitor {
    // TimeRemaining also fires on source changes; Source and Attach make those
    // immediate. AnyPowerSource is avoided: it fires far more often.
    nonisolated static let systemNames = [kIOPSNotifyTimeRemaining, kIOPSNotifyPowerSource, kIOPSNotifyAttach]

    private let names: [String]
    private var tokens: [Int32] = []

    var isObserving: Bool { !tokens.isEmpty }

    /// - Parameter names: notify(3) names; tests pass a private one they can post.
    init(names: [String] = PowerMonitor.systemNames) {
        self.names = names
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard tokens.isEmpty else { return }
        for name in names {
            var token: Int32 = NOTIFY_TOKEN_INVALID
            // The handler is inferred @MainActor: any queue but .main traps at run time.
            let status = notify_register_dispatch(name, &token, .main) { _ in onChange() }
            if status == NOTIFY_STATUS_OK { tokens.append(token) }
        }
    }

    func stop() {
        tokens.forEach { notify_cancel($0) }
        tokens = []
    }

    deinit {
        tokens.forEach { notify_cancel($0) }
    }
}
