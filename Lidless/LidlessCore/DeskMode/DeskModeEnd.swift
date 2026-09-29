import Foundation

/// How a Desk Mode session ended, for the one log line every ending gets, so a
/// `log stream` capture always says why the built-in screen came back.
public enum DeskModeEnd: Sendable, Equatable {
    /// The machine started bringing the panel back for this reason.
    case restoring(DeskModeRestoreReason)
    /// The panel was back without an enable of ours (a lid cycle, another app,
    /// macOS itself): Desk Mode stood down without touching it.
    case cameBackOnItsOwn
    /// Quit, a signal, log out or power off: the exit path enabled the panel.
    case exiting

    /// The ending a transition makes, or nil when it doesn't end a session:
    /// the panel was off or going off (`engaging`, `confirming`, `active`)
    /// before the event, and isn't after it.
    public static func detect(from before: DeskModeMachine.Phase, to after: DeskModeMachine.Phase, on event: DeskModeEvent) -> DeskModeEnd? {
        guard before.isSession, !after.isSession else { return nil }
        switch after {
        case .restoring(let reason, _, _): return .restoring(reason)
        case .idle: return event == .willTerminate ? .exiting : .cameBackOnItsOwn
        case .engaging, .confirming, .active: return nil
        }
    }

    /// How long the session had been going at `now`: since the disable started
    /// (engaging), since it landed (confirming, from the prompt's deadline), or
    /// since the panel was verified off (active). nil when unknown.
    public static func sessionLength(of phase: DeskModeMachine.Phase, now: TimeInterval, confirmationSeconds: TimeInterval) -> TimeInterval? {
        switch phase {
        case .engaging(_, _, let startedAt): max(0, now - startedAt)
        case .confirming(_, _, _, let deadline): max(0, now - (deadline - confirmationSeconds))
        case .active(_, _, _, let engagedAt): max(0, now - engagedAt)
        case .idle, .restoring: nil
        }
    }

    /// A short, stable key for log filtering ("externalLost", "timeLimit", …).
    public var key: String {
        switch self {
        case .restoring(let reason): reason.logKey
        case .cameBackOnItsOwn: "cameBackOnItsOwn"
        case .exiting: "exiting"
        }
    }

    /// Why, in plain words. Display names stay out of it.
    public var explanation: String {
        switch self {
        case .restoring(let reason):
            switch reason {
            case .user: "switched off (popover switch, Desk Mode key, Shortcuts, or Black out's cover went away)"
            case .panic: "the panic key or its Shortcuts action"
            case .externalLost: "the last external display left the display list"
            case .confirmationTimedOut: "nobody answered the keep-or-revert prompt in time"
            case .declined: "Turn Back On in the keep-or-revert prompt"
            case .sleep: "the Mac slept during the prompt, or woke without \"Keep Desk Mode after wake\""
            case .sessionChanged: "the login session left the console (fast user switching)"
            case .engageFailed: "the disable failed or couldn't be verified"
            case .timeLimit: "the Debug time limit ran out (LidlessDeskModeTimeLimit)"
            case .terminating: "the app is quitting"
            case .recovery: "carrying on a restore that launch recovery or log out couldn't confirm"
            }
        case .cameBackOnItsOwn:
            "the built-in screen was back without Lidless (a lid cycle, another app or macOS), so Desk Mode stood down"
        case .exiting:
            "quit, a signal, log out or power off"
        }
    }
}

private extension DeskModeMachine.Phase {
    /// The panel is off or going off.
    var isSession: Bool {
        switch self {
        case .engaging, .confirming, .active: true
        case .idle, .restoring: false
        }
    }
}

public extension DeskModeRestoreReason {
    /// A short, stable name for the log. Display names stay out of it.
    var logKey: String {
        switch self {
        case .user: "user"
        case .panic: "panic"
        case .externalLost: "externalLost"
        case .confirmationTimedOut: "confirmationTimedOut"
        case .declined: "declined"
        case .sleep: "sleep"
        case .sessionChanged: "sessionChanged"
        case .engageFailed: "engageFailed"
        case .timeLimit: "timeLimit"
        case .terminating: "terminating"
        case .recovery: "recovery"
        }
    }
}
