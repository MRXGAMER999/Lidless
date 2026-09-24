import Carbon.HIToolbox
import Foundation
import LidlessCore

/// Names keys the way the keyboard layout in use prints them.
///
/// A shortcut fires on a key position, so the key recorded as B on a US layout
/// types X on Dvorak; showing the recorded label there would name the wrong key.
enum KeyboardLayout {
    /// The keycap label for `keyCode` on the current layout, or nil when the key
    /// types nothing printable (Space, Return, F-keys).
    ///
    /// - Parameter commandHeld: Some layouts (Dvorak – QWERTY ⌘, Russian)
    ///   switch to QWERTY while ⌘ is down, which is what a ⌘ shortcut presses.
    static func label(forKeyCode keyCode: UInt16, commandHeld: Bool) -> String? {
        // The ASCII-capable layout, like menus: with Russian or Japanese input the
        // shortcut keys still read as Latin letters.
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return label(forKeyCode: keyCode, commandHeld: commandHeld, in: source)
    }

    static func label(forKeyCode keyCode: UInt16, commandHeld: Bool, in source: TISInputSource) -> String? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let modifierKeyState: UInt32 = commandHeld ? UInt32(cmdKey >> 8) & 0xFF : 0
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var characters = [UniChar](repeating: 0, count: maxLength)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                modifierKeyState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                maxLength,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let label = String(utf16CodeUnits: characters, count: length).uppercased()
        let printable = label.unicodeScalars.allSatisfy { scalar in
            !scalar.properties.isWhitespace && scalar.properties.generalCategory != .control
        }
        return printable ? label : nil
    }
}

/// Calls back on the main actor when the user picks another keyboard layout
/// or input source, so key names can be worked out again.
final class KeyboardLayoutObserver: NSObject {
    static let selectionDidChange = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)

    private let onChange: () -> Void

    init(name: Notification.Name = selectionDidChange, onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        // AppKit holds back distributed notifications while the app is inactive,
        // which a menu bar app nearly always is.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: name,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private nonisolated func selectionDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.onChange() }
    }
}

extension KeyShortcut {
    /// The key as the current keyboard layout names it, or the label recorded with the shortcut.
    var displayKeyLabel: String {
        KeyboardLayout.label(forKeyCode: keyCode, commandHeld: modifiers.contains(.command)) ?? keyLabel
    }
}
