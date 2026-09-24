import Foundation
import os

/// Restores the built-in when a signal ends the app: `kill` and logout-time
/// SIGTERM, Ctrl-C in a terminal (SIGINT), a closed terminal (SIGHUP). Their
/// default action would end the process with the panel off until the sidecar
/// notices, so they're ignored and delivered through dispatch sources on the
/// main queue instead, where the restore can run as on a normal quit.
///
/// Keep the instance alive for the life of the app: the sources go with it.
final class SignalRestorer {
    static let signals: [Int32] = [SIGTERM, SIGINT, SIGHUP]

    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Signals")
    private var sources: [any DispatchSourceSignal] = []
    private var handler: (@MainActor () -> Void)?

    var isInstalled: Bool { !sources.isEmpty }

    /// Installs once; later calls are ignored. On a signal, `handler` runs on
    /// the main thread, then the process exits with status 0.
    func install(_ handler: @escaping @MainActor () -> Void) {
        guard sources.isEmpty else { return }
        self.handler = handler
        for sig in Self.signals {
            // Ignore first, or the default action kills the process before the source runs.
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            // The main queue runs on the main thread, so the isolation check holds.
            source.setEventHandler { @Sendable [weak self] in
                MainActor.assumeIsolated { self?.received(sig) }
            }
            source.resume()
            sources.append(source)
        }
    }

    private func received(_ sig: Int32) {
        log.notice("Received signal \(sig, privacy: .public); restoring before exit")
        handler?()
        exit(0)
    }
}
