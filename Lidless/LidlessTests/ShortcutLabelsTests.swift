import Combine
import Foundation
import LidlessCore
import Testing
@testable import Lidless

@MainActor
struct ShortcutLabelsTests {
    @Test func `keycaps and spoken name use the given key label`() {
        let labels = ShortcutLabels(.defaultPanic, keyLabel: "X")
        #expect(labels.keycaps == ["⌃", "⌥", "⌘", "X"])
        #expect(labels.spokenName == "Control Option Command X")
    }

    @Test func `every modifier is spoken in macOS order`() {
        let shortcut = KeyShortcut(keyCode: 0x02, keyLabel: "D", modifiers: [.command, .shift, .option, .control])
        let labels = ShortcutLabels(shortcut, keyLabel: "D")
        #expect(labels.keycaps == ["⌃", "⌥", "⇧", "⌘", "D"])
        #expect(labels.spokenName == "Control Option Shift Command D")
    }
}

/// The panic key's labels live in the store so a keyboard layout switch reaches the popover.
@MainActor
struct DeskModePanicKeysTests {
    /// Stands in for the keyboard layout: names key code 0x0B.
    private final class FakeLayout {
        var bKey = "B"
        func label(_ shortcut: KeyShortcut) -> String {
            shortcut.keyCode == 0x0B ? bKey : shortcut.keyLabel
        }
    }

    @Test func `labels come from the layout at init`() {
        let layout = FakeLayout()
        layout.bKey = "X"
        let store = DeskModeStore(keyLabel: layout.label)
        #expect(store.panicKeys == ShortcutLabels(.defaultPanic, keyLabel: "X"))
    }

    @Test func `a layout switch renames the key and publishes once`() {
        let layout = FakeLayout()
        let store = DeskModeStore(keyLabel: layout.label)
        var changes = 0
        let cancellable = store.objectWillChange.sink { changes += 1 }

        store.keyboardLayoutDidChange()
        #expect(changes == 0, "Same letter: nothing to redraw")

        layout.bKey = "X"
        store.keyboardLayoutDidChange()
        #expect(changes == 1)
        #expect(store.panicKeys.keycaps.last == "X")
        #expect(store.panicKeys.spokenName.hasSuffix(" X"))
        cancellable.cancel()
    }

    @Test func `a new panic shortcut gets new labels`() {
        let store = DeskModeStore(keyLabel: FakeLayout().label)
        store.panicShortcut = KeyShortcut(keyCode: 0x02, keyLabel: "D", modifiers: [.control, .command])
        #expect(store.panicKeys == ShortcutLabels(store.panicShortcut, keyLabel: "D"))
    }
}

@MainActor
struct KeyboardLayoutObserverTests {
    /// Posted without "deliver immediately", like the system's own notice: the
    /// observer must still hear it while the app is inactive.
    @Test func `calls back on the main actor for a distributed notification`() async throws {
        let name = Notification.Name("io.github.mrxgamer999.LidlessTests.\(UUID().uuidString)")
        var calls = 0
        let observer = KeyboardLayoutObserver(name: name) {
            MainActor.preconditionIsolated()
            calls += 1
        }
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: false)
        for _ in 0..<80 where calls == 0 {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(calls == 1)
        withExtendedLifetime(observer) {}
    }

    @Test func `listens for keyboard input source changes`() {
        #expect(KeyboardLayoutObserver.selectionDidChange.rawValue == "com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged")
    }
}
