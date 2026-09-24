import Foundation
import Testing
@testable import LidlessCore

struct KeyShortcutTests {
    @Test func `keycaps follow the macOS modifier order`() {
        let shortcut = KeyShortcut(keyCode: 0x0B, keyLabel: "B", modifiers: [.command, .shift, .option, .control])
        #expect(shortcut.keycaps == ["⌃", "⌥", "⇧", "⌘", "B"])
        #expect(shortcut.keycaps(keyLabel: "X") == ["⌃", "⌥", "⇧", "⌘", "X"])
    }

    /// Key codes are key positions (kVK_ANSI_B, kVK_ANSI_D, kVK_ANSI_Equal).
    @Test(arguments: zip(
        [KeyShortcut.defaultPanic, .defaultDeskMode, .defaultBoost],
        [UInt16(0x0B), 0x02, 0x18]
    ))
    func `defaults are ⌃⌥⌘ on fixed keys`(shortcut: KeyShortcut, keyCode: UInt16) {
        #expect(shortcut.keyCode == keyCode)
        #expect(shortcut.modifiers == [.control, .option, .command])
        #expect(shortcut.isUsableAsGlobalShortcut)
    }

    @Test(arguments: [
        ([], false),
        ([.shift], false),
        ([.option], false),
        ([.option, .shift], false),
        ([.control], true),
        ([.command], true),
        ([.option, .command], true),
        ([.control, .shift], true),
    ] as [(KeyShortcut.Modifiers, Bool)])
    func `a global shortcut needs control or command`(modifiers: KeyShortcut.Modifiers, usable: Bool) {
        #expect(KeyShortcut(keyCode: 0x0B, keyLabel: "B", modifiers: modifiers).isUsableAsGlobalShortcut == usable)
    }

    @Test func `the same keys are the same shortcut whatever label was recorded`() {
        let us = KeyShortcut(keyCode: 0x0B, keyLabel: "B", modifiers: [.control, .command])
        let dvorak = KeyShortcut(keyCode: 0x0B, keyLabel: "X", modifiers: [.control, .command])
        #expect(us == dvorak)
        #expect(Set([us, dvorak]).count == 1)
        #expect(us != KeyShortcut(keyCode: 0x0B, keyLabel: "B", modifiers: [.control, .option, .command]))
        #expect(us != KeyShortcut(keyCode: 0x02, keyLabel: "B", modifiers: [.control, .command]))
    }

    /// Saved shortcuts store the modifiers' raw value; reordering the options would remap them.
    @Test func `saved form keeps its modifier bits`() throws {
        let data = try JSONEncoder().encode(KeyShortcut.defaultPanic)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["keyCode"] as? Int == 0x0B)
        #expect(object["keyLabel"] as? String == "B")
        #expect(object["modifiers"] as? Int == 0b1011)
        let decoded = try JSONDecoder().decode(KeyShortcut.self, from: data)
        #expect(decoded == .defaultPanic)
        #expect(decoded.keyLabel == "B")
    }
}
