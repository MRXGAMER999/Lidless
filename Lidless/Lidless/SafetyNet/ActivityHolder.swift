import Foundation

/// Keeps App Nap away while Desk Mode is on or a countdown is pending. A menu
/// bar agent with no visible window is a nap candidate, and napping would
/// coalesce the 1 s tick and stretch the hang watchdog's 0.5 s beat into a
/// false abort. `.userInitiatedAllowingIdleSystemSleep` still lets the Mac
/// idle-sleep (plain `.userInitiated` would not); `.latencyCritical` keeps the
/// timers on time.
final class ProcessActivityHolder: ActivityHolder {
    private var token: (any NSObjectProtocol)?

    var isHolding: Bool { token != nil }

    /// Idempotent: repeated calls with the same value do nothing.
    func hold(_ on: Bool) {
        if on {
            guard token == nil else { return }
            token = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Desk Mode is on"
            )
        } else if let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }
}
