import Combine
import Foundation
import LidlessCore

/// Desk Mode state and the shortcut that always brings the built-in screen back.
///
/// Phase 3 connects this to the display controller and safety net; until then
/// `setOn(_:)` only changes the published state.
final class DeskModeStore: ObservableObject {
    @Published private(set) var state: DeskModeState
    /// Why Desk Mode can't be used right now; nil when it can. Kept apart from
    /// `state` so turning Desk Mode off lands on the current reason.
    private(set) var unavailableReason: DeskModeState.UnavailableReason?
    @Published var panicShortcut: KeyShortcut {
        didSet { refreshPanicKeys() }
    }

    /// `panicShortcut` named by the keyboard layout in use. Published so a
    /// layout switch reaches the views, and so their bodies never call Carbon.
    @Published private(set) var panicKeys: ShortcutLabels

    private let keyLabel: (KeyShortcut) -> String
    private var layoutObserver: KeyboardLayoutObserver?

    /// - Parameter keyLabel: Names the shortcut's key; tests pass a fake layout.
    init(
        state: DeskModeState = .off,
        panicShortcut: KeyShortcut = .defaultPanic,
        keyLabel: @escaping (KeyShortcut) -> String = { $0.displayKeyLabel }
    ) {
        self.state = state
        if case .unavailable(let reason) = state { unavailableReason = reason }
        self.panicShortcut = panicShortcut
        self.keyLabel = keyLabel
        panicKeys = ShortcutLabels(panicShortcut, keyLabel: keyLabel(panicShortcut))
        layoutObserver = KeyboardLayoutObserver { [weak self] in self?.keyboardLayoutDidChange() }
    }

    /// Desk Mode as a switch, for `Toggle` bindings. Setting it calls `setOn(_:)`.
    var isOn: Bool {
        get { state.isOn }
        set { setOn(newValue) }
    }

    /// Phase 2: only changes the published state, in live mode too; Phase 3
    /// connects it to the display controller and safety net.
    func setOn(_ on: Bool) {
        guard state.isAvailable, on != state.isOn else { return }
        state = on ? .on(since: .now, trigger: .manual) : DeskModeState.off.applying(availability: unavailableReason)
    }

    func update(_ newState: DeskModeState) {
        guard newState != state else { return }
        state = newState
    }

    /// Used by the system layer whenever lid, displays or support change.
    /// `.on` and `.switching` stay put: the Desk Mode controller owns them.
    func applyAvailability(_ reason: DeskModeState.UnavailableReason?) {
        unavailableReason = reason
        update(state.applying(availability: reason))
    }

    func keyboardLayoutDidChange() {
        refreshPanicKeys()
    }

    private func refreshPanicKeys() {
        let keys = ShortcutLabels(panicShortcut, keyLabel: keyLabel(panicShortcut))
        // Switching to Russian or Japanese input keeps the Latin layout, so the
        // same letter; skip the publish so the cards don't redraw for nothing.
        guard keys != panicKeys else { return }
        panicKeys = keys
    }
}
