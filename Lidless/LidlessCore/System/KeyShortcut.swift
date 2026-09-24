import Foundation

/// A global keyboard shortcut, stored as a virtual key code plus modifiers.
///
/// Two shortcuts are equal when they press the same keys. The key code is a
/// position on the keyboard, so `keyLabel` is only what that key typed when the
/// shortcut was recorded; show the current layout's name for it (the app's
/// `DeskModeStore.panicKeys`).
public struct KeyShortcut: Sendable, Hashable, Codable {
    public struct Modifiers: OptionSet, Sendable, Hashable, Codable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// Virtual key code (`kVK_*` in Carbon's Events.h).
    public var keyCode: UInt16
    /// The character the key typed when it was recorded ("B", "D", "="). A
    /// fallback for display when the current layout can't name the key.
    public var keyLabel: String
    public var modifiers: Modifiers

    public init(keyCode: UInt16, keyLabel: String, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.keyLabel = keyLabel
        self.modifiers = modifiers
    }

    public static func == (lhs: KeyShortcut, rhs: KeyShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }

    /// Keycap labels in macOS order: ⌃ ⌥ ⇧ ⌘, then the recorded key label.
    public var keycaps: [String] {
        keycaps(keyLabel: keyLabel)
    }

    /// Keycap labels in macOS order: ⌃ ⌥ ⇧ ⌘, then `keyLabel`.
    public func keycaps(keyLabel: String) -> [String] {
        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }
        caps.append(keyLabel)
        return caps
    }

    /// A global shortcut needs ⌃ or ⌘: with only ⌥ and ⇧ the key types a
    /// character (⌥L is "@" on a German keyboard), and some macOS 15 releases
    /// refuse to register such hotkeys.
    public var isUsableAsGlobalShortcut: Bool {
        !modifiers.intersection([.control, .command]).isEmpty
    }

    /// ⌃⌥⌘B brings the built-in screen back.
    public static let defaultPanic = KeyShortcut(keyCode: 0x0B, keyLabel: "B", modifiers: [.control, .option, .command])
    /// ⌃⌥⌘D turns Desk Mode on or off.
    public static let defaultDeskMode = KeyShortcut(keyCode: 0x02, keyLabel: "D", modifiers: [.control, .option, .command])
    /// ⌃⌥⌘= turns Boost on or off.
    public static let defaultBoost = KeyShortcut(keyCode: 0x18, keyLabel: "=", modifiers: [.control, .option, .command])
}
