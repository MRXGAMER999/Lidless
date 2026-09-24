import Foundation
import Testing
@testable import LidlessCore

struct ShortcutSetTests {
    typealias Mods = KeyShortcut.Modifiers

    static func key(_ code: UInt16, _ modifiers: Mods, _ label: String = "?") -> KeyShortcut {
        KeyShortcut(keyCode: code, keyLabel: label, modifiers: modifiers)
    }

    @Test func `a free shortcut with control or command is fine`() {
        let set = ShortcutSet.defaults
        #expect(set.problem(assigning: Self.key(0x0B, [.control, .command], "B"), to: .panic) == nil)
        #expect(set.problem(assigning: Self.key(0x02, [.shift, .command], "D"), to: .toggleDeskMode) == nil)
    }

    @Test(arguments: [Mods(), [.shift], [.option], [.option, .shift]])
    func `a shortcut without control or command is refused`(modifiers: Mods) {
        #expect(ShortcutSet.defaults.problem(assigning: Self.key(0x0B, modifiers), to: .panic) == .needsControlOrCommand)
    }

    @Test func `keys another slot uses are taken`() {
        let set = ShortcutSet.defaults
        #expect(set.problem(assigning: .defaultPanic, to: .toggleDeskMode) == .taken(by: .panic))
        #expect(set.problem(assigning: .defaultBoost, to: .panic) == .taken(by: .toggleBoost))
        // The recorded label doesn't matter, only the keys.
        let relabelled = Self.key(KeyShortcut.defaultDeskMode.keyCode, KeyShortcut.defaultDeskMode.modifiers, "X")
        #expect(set.problem(assigning: relabelled, to: .toggleBoost) == .taken(by: .toggleDeskMode))
    }

    @Test(arguments: ShortcutSet.Slot.allCases)
    func `a slot can keep its own keys`(slot: ShortcutSet.Slot) throws {
        let set = ShortcutSet.defaults
        #expect(set.problem(assigning: try #require(set[slot]), to: slot) == nil)
    }

    @Test func `a cleared slot takes nothing`() {
        let set = ShortcutSet(panic: .defaultPanic, toggleDeskMode: nil, toggleBoost: nil)
        #expect(set.problem(assigning: .defaultDeskMode, to: .toggleBoost) == nil)
    }

    /// kVK_* codes: Q 0x0C, W 0x0D, H 0x04, M 0x2E, Tab 0x30, Space 0x31, F 0x03,
    /// 3 0x14, 4 0x15, 5 0x17, 6 0x16, Escape 0x35, ` 0x32, arrows 0x7B–0x7E.
    @Test(arguments: [
        (UInt16(0x0C), Mods.command),
        (0x0D, .command),
        (0x04, .command),
        (0x2E, .command),
        (0x30, .command),
        (0x31, .command),
        (0x31, .control),
        (0x31, [.control, .command]),
        (0x0C, [.control, .command]),
        (0x0C, [.option, .shift, .command]),
        (0x02, [.option, .command]),
        (0x03, [.control, .command]),
        (0x14, [.shift, .command]),
        (0x15, [.shift, .command]),
        (0x17, [.shift, .command]),
        (0x16, [.shift, .command]),
        (0x35, [.option, .command]),
        (0x32, .command),
        (0x7E, .control),
        (0x7D, .control),
        (0x7B, .control),
        (0x7C, .control),
    ] as [(UInt16, Mods)])
    func `system shortcuts are reserved`(code: UInt16, modifiers: Mods) {
        #expect(ShortcutSet.defaults.problem(assigning: Self.key(code, modifiers), to: .toggleBoost) == .reservedBySystem)
    }

    /// Only the exact combination is reserved; adding modifiers frees it.
    @Test func `extra modifiers make a reserved key usable`() {
        let set = ShortcutSet.defaults
        #expect(set.problem(assigning: Self.key(0x0C, [.control, .option, .command]), to: .panic) == nil)
        #expect(set.problem(assigning: Self.key(0x7E, [.control, .option]), to: .panic) == nil)
        // ⌃⌥⌘D, the default Desk Mode key, is ⌥⌘D (Dock) plus ⌃.
        #expect(set.problem(assigning: Self.key(0x02, [.control, .option, .command]), to: .toggleDeskMode) == nil)
    }

    @Test func `the subscript never clears the panic key`() {
        var set = ShortcutSet.defaults
        set[.panic] = nil
        set[.toggleDeskMode] = nil
        #expect(set.panic == .defaultPanic)
        #expect(set.toggleDeskMode == nil)
    }

    @Test func `saved shortcuts round-trip, cleared ones included`() throws {
        let set = ShortcutSet(panic: Self.key(0x0B, [.control, .command], "B"), toggleDeskMode: nil, toggleBoost: .defaultBoost)
        let decoded = try JSONDecoder().decode(ShortcutSet.self, from: JSONEncoder().encode(set))
        #expect(decoded == set)
        #expect(decoded.toggleDeskMode == nil)
    }

    @Test func `missing keys fall back to the defaults`() throws {
        let decoded = try JSONDecoder().decode(ShortcutSet.self, from: Data("{}".utf8))
        #expect(decoded == .defaults)
    }

    @Test func `a quick key saved as null stays cleared`() throws {
        let json = #"{"toggleBoost": null}"#
        let decoded = try JSONDecoder().decode(ShortcutSet.self, from: Data(json.utf8))
        #expect(decoded.panic == .defaultPanic)
        #expect(decoded.toggleDeskMode == .defaultDeskMode)
        #expect(decoded.toggleBoost == nil)
    }
}
