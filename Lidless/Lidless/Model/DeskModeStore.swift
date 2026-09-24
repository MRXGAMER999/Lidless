import Combine
import Foundation
import LidlessCore

/// Desk Mode state and the shortcut that always brings the built-in screen back.
///
/// Phase 3 connects this to the display controller and safety net; until then
/// `setOn(_:)` only changes the published state.
final class DeskModeStore: ObservableObject {
    @Published private(set) var state: DeskModeState
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

    func setOn(_ on: Bool) {
        guard state.isAvailable, on != state.isOn else { return }
        state = on ? .on(since: .now, trigger: .manual) : .off
    }

    /// Used by the system layer when availability changes (displays plugged in or out).
    func update(_ newState: DeskModeState) {
        guard newState != state else { return }
        state = newState
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
