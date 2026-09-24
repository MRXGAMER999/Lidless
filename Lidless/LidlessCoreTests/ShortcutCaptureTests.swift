import Foundation
import Testing
@testable import LidlessCore

struct ShortcutCaptureTests {
    typealias Mods = KeyShortcut.Modifiers

    private static let ctrlOptCmd: Mods = [.control, .option, .command]

    private static func press(
        _ keyCode: UInt16,
        _ modifiers: Mods,
        label: String? = "K",
        slot: ShortcutSet.Slot = .toggleDeskMode,
        shortcuts: ShortcutSet = .defaults,
        allowsClearing: Bool = true
    ) -> ShortcutCapture.Outcome {
        ShortcutCapture.keyDown(
            keyCode: keyCode,
            modifiers: modifiers,
            layoutLabel: label,
            slot: slot,
            shortcuts: shortcuts,
            allowsClearing: allowsClearing
        )
    }

    // MARK: Recording

    @Test func `a free combination is recorded with the layout's label`() {
        #expect(Self.press(0x28, Self.ctrlOptCmd, label: "k") == .record(KeyShortcut(keyCode: 0x28, keyLabel: "K", modifiers: Self.ctrlOptCmd)))
    }

    @Test func `the recorded label comes from the layout, not the key position`() {
        // Key code 0x0B is B on QWERTY and X on Dvorak.
        guard case .record(let shortcut) = Self.press(0x0B, [.control, .command], label: "X") else {
            Issue.record("Expected a recording")
            return
        }
        #expect(shortcut.keyLabel == "X")
        #expect(shortcut.keyCode == 0x0B)
    }

    @Test func `a slot may record the keys it already has`() {
        let outcome = Self.press(KeyShortcut.defaultDeskMode.keyCode, KeyShortcut.defaultDeskMode.modifiers, label: "D")
        #expect(outcome == .record(.defaultDeskMode))
    }

    // MARK: Modifier rules (ShortcutSet decides)

    @Test(arguments: [Mods(), [.shift], [.option], [.option, .shift]])
    func `keys without control or command are refused`(modifiers: Mods) {
        #expect(Self.press(0x28, modifiers) == .rejected(.problem(.needsControlOrCommand)))
    }

    @Test(arguments: [Mods.control, .command, [.control, .shift], [.option, .command]])
    func `control or command is enough`(modifiers: Mods) {
        #expect(Self.press(0x28, modifiers) == .record(KeyShortcut(keyCode: 0x28, keyLabel: "K", modifiers: modifiers)))
    }

    @Test func `modifier presses only update what is held`() {
        #expect(ShortcutCapture.flagsChanged(modifiers: [.control, .option]) == .modifiers([.control, .option]))
        #expect(ShortcutCapture.flagsChanged(modifiers: []) == .modifiers([]))
    }

    @Test(arguments: [UInt16(0x37), 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x36, 0x66, 0x68])
    func `modifier and input-mode keys arriving as key downs are ignored`(keyCode: UInt16) {
        #expect(Self.press(keyCode, Self.ctrlOptCmd, label: nil) == .ignore)
    }

    @Test func `a key nothing can name is ignored`() {
        #expect(Self.press(0x0A, Self.ctrlOptCmd, label: nil) == .ignore)
        #expect(Self.press(0x0A, Self.ctrlOptCmd, label: " \u{7}") == .ignore)
    }

    // MARK: Esc, Tab, Delete

    @Test(arguments: [Mods(), .shift])
    func `escape cancels`(modifiers: Mods) {
        #expect(Self.press(0x35, modifiers, label: nil) == .cancel)
    }

    @Test func `escape with command is a combination (Force Quit is reserved)`() {
        #expect(Self.press(0x35, [.option, .command], label: nil) == .rejected(.problem(.reservedBySystem)))
        #expect(Self.press(0x35, [.control, .command], label: nil) == .record(KeyShortcut(keyCode: 0x35, keyLabel: "⎋", modifiers: [.control, .command])))
    }

    @Test(arguments: [Mods(), .shift])
    func `tab leaves the recorder`(modifiers: Mods) {
        #expect(Self.press(0x30, modifiers, label: nil) == .moveFocus)
    }

    @Test func `command tab is reserved, control tab is fine`() {
        #expect(Self.press(0x30, .command, label: nil) == .rejected(.problem(.reservedBySystem)))
        #expect(Self.press(0x30, .control, label: nil) == .record(KeyShortcut(keyCode: 0x30, keyLabel: "⇥", modifiers: .control)))
    }

    @Test(arguments: [UInt16(0x33), 0x75])
    func `delete clears where allowed`(keyCode: UInt16) {
        #expect(Self.press(keyCode, [], label: nil, allowsClearing: true) == .clear)
        #expect(Self.press(keyCode, .shift, label: nil, allowsClearing: true) == .clear)
    }

    @Test(arguments: [UInt16(0x33), 0x75])
    func `delete never clears the panic key`(keyCode: UInt16) {
        #expect(Self.press(keyCode, [], label: nil, slot: .panic, allowsClearing: false) == .rejected(.cannotClear))
    }

    @Test func `command delete is a combination, not a clear`() {
        #expect(Self.press(0x33, [.control, .command], label: nil) == .record(KeyShortcut(keyCode: 0x33, keyLabel: "⌫", modifiers: [.control, .command])))
    }

    // MARK: Function and special keys

    @Test func `function keys are named from the table`() {
        #expect(Self.press(0x60, [.control, .option], label: nil) == .record(KeyShortcut(keyCode: 0x60, keyLabel: "F5", modifiers: [.control, .option])))
        #expect(Self.press(0x5A, .command, label: nil) == .record(KeyShortcut(keyCode: 0x5A, keyLabel: "F20", modifiers: .command)))
    }

    @Test func `a bare function key still needs control or command`() {
        #expect(Self.press(0x60, [], label: nil) == .rejected(.problem(.needsControlOrCommand)))
    }

    @Test func `the table wins over what the layout prints`() {
        // Some layouts print a private-use glyph for F-keys or a space for Space.
        #expect(Self.press(0x31, .control, label: " ") == .rejected(.problem(.reservedBySystem)), "⌃Space switches input sources")
        #expect(Self.press(0x31, [.control, .option], label: " ") == .record(KeyShortcut(keyCode: 0x31, keyLabel: "Space", modifiers: [.control, .option])))
        #expect(Self.press(0x7A, .command, label: "\u{F704}") == .record(KeyShortcut(keyCode: 0x7A, keyLabel: "F1", modifiers: .command)))
    }

    @Test func `every special key has a label, and printable keys have none`() {
        for code: UInt16 in [0x24, 0x4C, 0x30, 0x31, 0x33, 0x75, 0x35, 0x47, 0x72, 0x73, 0x77, 0x74, 0x79, 0x7B, 0x7C, 0x7D, 0x7E] {
            #expect(ShortcutCapture.specialKeyLabel(for: code) != nil, "key code \(code)")
        }
        for code: UInt16 in [0x00, 0x0B, 0x02, 0x18, 0x12] {
            #expect(ShortcutCapture.specialKeyLabel(for: code) == nil, "key code \(code)")
        }
    }

    @Test func `arrows with control alone are Mission Control's`() {
        #expect(Self.press(0x7E, .control, label: nil) == .rejected(.problem(.reservedBySystem)))
        #expect(Self.press(0x7E, [.control, .option], label: nil) == .record(KeyShortcut(keyCode: 0x7E, keyLabel: "↑", modifiers: [.control, .option])))
    }

    // MARK: Reserved and taken

    @Test func `system shortcuts are refused`() {
        #expect(Self.press(0x0C, .command, label: "Q") == .rejected(.problem(.reservedBySystem)))
        #expect(Self.press(0x15, [.shift, .command], label: "4") == .rejected(.problem(.reservedBySystem)))
    }

    @Test func `another slot's keys are refused and named`() {
        let panic = KeyShortcut.defaultPanic
        #expect(Self.press(panic.keyCode, panic.modifiers, label: "B", slot: .toggleBoost) == .rejected(.problem(.taken(by: .panic))))
        let desk = KeyShortcut.defaultDeskMode
        #expect(Self.press(desk.keyCode, desk.modifiers, label: "D", slot: .panic, allowsClearing: false) == .rejected(.problem(.taken(by: .toggleDeskMode))))
    }

    @Test func `a cleared slot's old keys are free`() {
        let set = ShortcutSet(panic: .defaultPanic, toggleDeskMode: nil, toggleBoost: .defaultBoost)
        let desk = KeyShortcut.defaultDeskMode
        #expect(Self.press(desk.keyCode, desk.modifiers, label: "D", slot: .toggleBoost, shortcuts: set) == .record(KeyShortcut(keyCode: desk.keyCode, keyLabel: "D", modifiers: desk.modifiers)))
    }
}
