import Foundation

/// The app's global shortcuts. The panic key can be changed but never removed.
public struct ShortcutSet: Sendable, Equatable, Codable {
    public var panic: KeyShortcut
    /// nil when the user cleared it.
    public var toggleDeskMode: KeyShortcut?
    public var toggleBoost: KeyShortcut?

    public static let defaults = ShortcutSet(panic: .defaultPanic, toggleDeskMode: .defaultDeskMode, toggleBoost: .defaultBoost)

    public init(panic: KeyShortcut, toggleDeskMode: KeyShortcut?, toggleBoost: KeyShortcut?) {
        self.panic = panic
        self.toggleDeskMode = toggleDeskMode
        self.toggleBoost = toggleBoost
    }

    private enum CodingKeys: String, CodingKey {
        case panic, toggleDeskMode, toggleBoost
    }

    /// Decodes, filling missing keys from `defaults` so older saves keep working.
    /// A quick key saved as `null` stays cleared; only a missing one gets its default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ShortcutSet.defaults
        panic = try c.decodeIfPresent(KeyShortcut.self, forKey: .panic) ?? d.panic
        toggleDeskMode = c.contains(.toggleDeskMode) ? try c.decodeIfPresent(KeyShortcut.self, forKey: .toggleDeskMode) : d.toggleDeskMode
        toggleBoost = c.contains(.toggleBoost) ? try c.decodeIfPresent(KeyShortcut.self, forKey: .toggleBoost) : d.toggleBoost
    }

    /// Writes cleared quick keys as `null` (the synthesized form would drop the
    /// key, and decoding would bring the default back).
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(panic, forKey: .panic)
        try c.encode(toggleDeskMode, forKey: .toggleDeskMode)
        try c.encode(toggleBoost, forKey: .toggleBoost)
    }

    public enum Slot: String, Sendable, CaseIterable, Codable {
        case panic, toggleDeskMode, toggleBoost
    }

    public enum Problem: Sendable, Equatable {
        /// Needs ⌃ or ⌘ (see `KeyShortcut.isUsableAsGlobalShortcut`).
        case needsControlOrCommand
        /// Another slot already uses these keys.
        case taken(by: Slot)
        /// macOS or common apps use it: ⌘Q, ⌘W, ⌘Tab, ⌘Space, ⌃⌘Q, ⌥⇧⌘Q, ⌥⌘D, ⌃⌘F, ⇧⌘3/4/5 …
        case reservedBySystem
    }

    /// Why `shortcut` can't go in `slot`, or nil when it can.
    public func problem(assigning shortcut: KeyShortcut, to slot: Slot) -> Problem? {
        guard shortcut.isUsableAsGlobalShortcut else { return .needsControlOrCommand }
        if let other = Slot.allCases.first(where: { $0 != slot && self[$0] == shortcut }) {
            return .taken(by: other)
        }
        if Self.reserved.contains(shortcut) { return .reservedBySystem }
        return nil
    }

    /// Shortcuts macOS or nearly every app already answers to. A hotkey on one
    /// of these would steal it system-wide (or never fire).
    private static let reserved: Set<KeyShortcut> = {
        let cmd: KeyShortcut.Modifiers = .command
        let ctrl: KeyShortcut.Modifiers = .control
        let keys: [(UInt16, KeyShortcut.Modifiers)] = [
            (kVK_ANSI_Q, cmd), // Quit
            (kVK_ANSI_W, cmd), // Close window
            (kVK_ANSI_H, cmd), // Hide
            (kVK_ANSI_H, [.option, .command]), // Hide others
            (kVK_ANSI_M, cmd), // Minimize
            (kVK_Tab, cmd), // App switcher
            (kVK_Tab, [.shift, .command]),
            (kVK_ANSI_Grave, cmd), // Next window
            (kVK_ANSI_Grave, [.shift, .command]),
            (kVK_Space, cmd), // Spotlight
            (kVK_Space, [.option, .command]), // Finder search
            (kVK_Space, ctrl), // Input source
            (kVK_Space, [.control, .command]), // Emoji & Symbols
            (kVK_ANSI_Q, [.control, .command]), // Lock Screen
            (kVK_ANSI_Q, [.shift, .command]), // Log Out
            (kVK_ANSI_Q, [.option, .shift, .command]), // Log Out without asking
            (kVK_ANSI_D, [.option, .command]), // Show or hide the Dock
            (kVK_ANSI_F, [.control, .command]), // Full screen
            (kVK_ANSI_3, [.shift, .command]), // Screenshots
            (kVK_ANSI_4, [.shift, .command]),
            (kVK_ANSI_5, [.shift, .command]),
            (kVK_ANSI_6, [.shift, .command]),
            (kVK_Escape, [.option, .command]), // Force Quit
            (kVK_UpArrow, ctrl), // Mission Control
            (kVK_DownArrow, ctrl), // App windows
            (kVK_LeftArrow, ctrl), // Spaces
            (kVK_RightArrow, ctrl),
        ]
        return Set(keys.map { KeyShortcut(keyCode: $0.0, keyLabel: "", modifiers: $0.1) })
    }()

    public subscript(slot: Slot) -> KeyShortcut? {
        get {
            switch slot {
            case .panic: panic
            case .toggleDeskMode: toggleDeskMode
            case .toggleBoost: toggleBoost
            }
        }
        set {
            switch slot {
            case .panic: if let newValue { panic = newValue }
            case .toggleDeskMode: toggleDeskMode = newValue
            case .toggleBoost: toggleBoost = newValue
            }
        }
    }
}

// Carbon virtual key codes (Events.h). LidlessCore doesn't import Carbon.
private let kVK_ANSI_Q: UInt16 = 0x0C
private let kVK_ANSI_W: UInt16 = 0x0D
private let kVK_ANSI_H: UInt16 = 0x04
private let kVK_ANSI_D: UInt16 = 0x02
private let kVK_ANSI_M: UInt16 = 0x2E
private let kVK_ANSI_F: UInt16 = 0x03
private let kVK_ANSI_3: UInt16 = 0x14
private let kVK_ANSI_4: UInt16 = 0x15
private let kVK_ANSI_5: UInt16 = 0x17
private let kVK_ANSI_6: UInt16 = 0x16
private let kVK_ANSI_Grave: UInt16 = 0x32
private let kVK_Tab: UInt16 = 0x30
private let kVK_Space: UInt16 = 0x31
private let kVK_Escape: UInt16 = 0x35
private let kVK_LeftArrow: UInt16 = 0x7B
private let kVK_RightArrow: UInt16 = 0x7C
private let kVK_DownArrow: UInt16 = 0x7D
private let kVK_UpArrow: UInt16 = 0x7E
