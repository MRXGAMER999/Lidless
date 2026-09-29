import Foundation
import LidlessCore

/// The note under the panic key hero's buttons in Settings › Keys & App when
/// the panic key may not work (not designed; styled like the recorder's
/// refusals). Nil, and no note, while it works.
nonisolated enum PanicKeyNotice: Equatable, Sendable {
    /// Carbon refused the keys just recorded; the app put `kept` back.
    case refused(KeyShortcut, kept: KeyShortcut)
    /// Registered, but another app holds the keys too and may get the presses.
    case shared
    /// Not registered at all, so pressing the keys does nothing.
    case notRegistered

    /// A panic key the user just recorded over `previous`.
    struct Change: Equatable, Sendable {
        let recorded: KeyShortcut
        let previous: KeyShortcut
    }

    /// What to show once the app has had its turn with a change.
    ///
    /// When a new panic key can't be registered, the app puts the previous one
    /// back into the saved shortcuts, so a recorded key that was replaced by
    /// the one before it was refused. That wins over the registration, which by
    /// then is the previous key's again.
    ///
    /// - Parameters:
    ///   - change: The last recorded change, if one is still being checked.
    ///   - saved: The panic key in the preferences now.
    ///   - registration: How Carbon holds the panic key now.
    /// - Returns: The note, and the change to keep checking (only a refusal
    ///   keeps it, so the note stays until the next recording).
    static func resolve(
        change: Change?,
        saved: KeyShortcut,
        registration: HotKeyCenter.Registration?
    ) -> (notice: PanicKeyNotice?, change: Change?) {
        if let change, change.recorded != saved, change.previous == saved {
            return (.refused(change.recorded, kept: saved), change)
        }
        switch registration {
        case .shared: return (.shared, nil)
        case .failed: return (.notRegistered, nil)
        case .exclusive, .deferred, nil: return (nil, nil)
        }
    }

    /// The note's text. `keys` names a shortcut: its keycaps ("⌃⌥⌘B") for the
    /// screen, its spoken name ("Control Option Command B") for VoiceOver.
    func message(keys: (KeyShortcut) -> String) -> String {
        switch self {
        case .refused(let recorded, let kept):
            String(localized: "Lidless couldn't use \(keys(recorded)). The panic key is still \(keys(kept)).", comment: "Note under the panic key buttons in Settings › Keys & App when macOS refused the keys just recorded. The variables are the refused keys and the panic key kept, e.g. ⌃⌥⌘K and ⌃⌥⌘B.")
        case .shared:
            String(localized: "Another app also uses these keys and may get them first. Pick new ones with Change Keys.", comment: "Note under the panic key buttons in Settings › Keys & App when another app has registered the same keys. “Change Keys” is the button beside it.")
        case .notRegistered:
            String(localized: "These keys aren't working right now. Pick new ones with Change Keys.", comment: "Note under the panic key buttons in Settings › Keys & App when the panic key couldn't be registered at all. “Change Keys” is the button beside it.")
        }
    }
}
