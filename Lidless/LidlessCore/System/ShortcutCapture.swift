import Foundation

/// What the shortcut recorder does with a key press while it listens.
///
/// Pure, so the rules run in tests on Linux: the app's `ShortcutRecorder`
/// turns key events into calls here and acts on the outcome. Which combinations
/// are allowed is `ShortcutSet.problem(assigning:to:)`'s call (⌃ or ⌘ needed,
/// no keys another slot uses, none macOS keeps for itself).
public enum ShortcutCapture {
    public enum Outcome: Sendable, Equatable {
        /// Only modifiers are down (or none any more): keep listening and show them.
        case modifiers(KeyShortcut.Modifiers)
        /// Esc: stop listening and keep the old shortcut.
        case cancel
        /// Tab or ⇧Tab without ⌃⌥⌘: stop listening and let the press move
        /// keyboard focus, so a keyboard user can always leave the recorder.
        case moveFocus
        /// ⌫ or ⌦ where the shortcut may be removed.
        case clear
        /// Keys this slot can't take; keep listening and say why.
        case rejected(Rejection)
        /// Save these keys.
        case record(KeyShortcut)
        /// A key that can't be named or bound (Caps Lock, fn, input-mode keys): keep listening.
        case ignore
    }

    public enum Rejection: Sendable, Equatable {
        case problem(ShortcutSet.Problem)
        /// ⌫ on a shortcut that can be changed but never removed (the panic key).
        case cannotClear
    }

    /// Decides what a key down means.
    ///
    /// Esc, Tab and ⌫ steer the recorder only without ⌃, ⌥ and ⌘ (⇧ may be
    /// down: ⇧Tab moves focus back); with them they are ordinary keys, so
    /// ⌃⌘⌫ can be a shortcut and ⌥⌘Esc is refused as Force Quit.
    ///
    /// - Parameters:
    ///   - modifiers: The modifiers down with the key (Caps Lock and fn left out).
    ///   - layoutLabel: What the key types on the current keyboard layout, or
    ///     nil when it types nothing printable. Keys in `specialKeyLabel(for:)`
    ///     are named from that table instead.
    ///   - allowsClearing: Whether ⌫ may remove the shortcut (false for the panic key).
    public static func keyDown(
        keyCode: UInt16,
        modifiers: KeyShortcut.Modifiers,
        layoutLabel: String?,
        slot: ShortcutSet.Slot,
        shortcuts: ShortcutSet,
        allowsClearing: Bool
    ) -> Outcome {
        if modifierKeyCodes.contains(keyCode) { return .ignore }
        if modifiers.isDisjoint(with: [.control, .option, .command]) {
            switch keyCode {
            case KeyCode.escape: return .cancel
            case KeyCode.tab: return .moveFocus
            case KeyCode.delete, KeyCode.forwardDelete:
                return allowsClearing ? .clear : .rejected(.cannotClear)
            default: break
            }
        }
        guard let label = specialKeyLabel(for: keyCode) ?? layoutLabel.flatMap(cleaned) else { return .ignore }
        let shortcut = KeyShortcut(keyCode: keyCode, keyLabel: label, modifiers: modifiers)
        if let problem = shortcuts.problem(assigning: shortcut, to: slot) {
            return .rejected(.problem(problem))
        }
        return .record(shortcut)
    }

    /// A modifier key went down or up (`flagsChanged`).
    public static func flagsChanged(modifiers: KeyShortcut.Modifiers) -> Outcome {
        .modifiers(modifiers)
    }

    /// Keycap labels for keys that type nothing printable, in the symbols
    /// macOS menus use. Nil for keys the keyboard layout names.
    public static func specialKeyLabel(for keyCode: UInt16) -> String? {
        specialKeyLabels[keyCode]
    }

    /// Uppercased and trimmed, or nil when nothing printable is left.
    private static func cleaned(_ label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }

    // Carbon virtual key codes (Events.h). LidlessCore doesn't import Carbon.
    private enum KeyCode {
        static let tab: UInt16 = 0x30
        static let delete: UInt16 = 0x33
        static let escape: UInt16 = 0x35
        static let forwardDelete: UInt16 = 0x75
    }

    /// ⌘ ⇧ Caps Lock ⌥ ⌃ (left and right), fn, and the JIS Eisu/Kana keys:
    /// none of them can carry a hot key.
    private static let modifierKeyCodes: Set<UInt16> = [
        0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x66, 0x68,
    ]

    private static let specialKeyLabels: [UInt16: String] = [
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
        0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
        0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
        0x24: "↩", // Return
        0x4C: "⌤", // Keypad Enter
        0x30: "⇥", // Tab
        0x31: "Space",
        0x33: "⌫", // Delete
        0x75: "⌦", // Forward Delete
        0x35: "⎋", // Escape
        0x47: "⌧", // Keypad Clear
        0x72: "Help",
        0x73: "↖", // Home
        0x77: "↘", // End
        0x74: "⇞", // Page Up
        0x79: "⇟", // Page Down
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]
}
