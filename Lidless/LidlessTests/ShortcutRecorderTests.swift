import AppKit
import LidlessCore
import Testing
@testable import Lidless

// No real event monitors or VoiceOver: every recorder here gets fakes.

@MainActor
private final class FakeEventMonitor {
    private(set) var handler: ((NSEvent) -> NSEvent?)?
    private(set) var mask: NSEvent.EventTypeMask = []
    private(set) var adds = 0
    private(set) var removes = 0

    var isInstalled: Bool { handler != nil }

    var monitor: ShortcutRecorderModel.EventMonitor {
        ShortcutRecorderModel.EventMonitor(
            add: { [self] mask, handler in
                adds += 1
                self.mask = mask
                self.handler = handler
                return NSObject()
            },
            remove: { [self] _ in
                removes += 1
                handler = nil
            }
        )
    }
}

/// What the recorder did to the outside world: pauses, commits, announcements.
@MainActor
private final class Log {
    var recording: [Bool] = []
    var commits: [KeyShortcut?] = []
    var announcements: [String] = []
}

@MainActor
private struct Harness {
    let monitor = FakeEventMonitor()
    let log = Log()
    let notifications = NotificationCenter()
    let recorder: ShortcutRecorderModel

    init() {
        let log = log
        recorder = ShortcutRecorderModel(
            monitor: monitor.monitor,
            notificationCenter: notifications,
            // A QWERTY stand-in: K, B, D, Q, = and nothing else. A key it can't
            // name is ignored, so every key a test presses must be here.
            layoutLabel: { code, _ in [0x28: "k", 0x0B: "b", 0x02: "d", 0x0C: "q", 0x18: "="][code] },
            displayLabel: { $0.keyLabel },
            observesKeyboardLayout: false,
            announce: { log.announcements.append($0) }
        )
    }

    func start(
        _ slot: ShortcutSet.Slot = .toggleDeskMode,
        shortcuts: ShortcutSet = .defaults,
        allowsClearing: Bool = true,
        on recorder: ShortcutRecorderModel? = nil
    ) {
        let log = log
        (recorder ?? self.recorder).start(ShortcutRecorderModel.Request(
            slot: slot,
            shortcuts: shortcuts,
            allowsClearing: allowsClearing,
            commit: { log.commits.append($0) },
            setRecording: { log.recording.append($0) }
        ))
    }
}

private let ctrlOptCmd: NSEvent.ModifierFlags = [.control, .option, .command]

@MainActor
struct ShortcutRecorderTests {
    // MARK: Listening

    @Test func `starting installs one monitor and pauses hot keys`() {
        let h = Harness()
        h.start()
        #expect(h.recorder.isListening)
        #expect(h.monitor.adds == 1)
        #expect(h.monitor.mask.contains(.keyDown))
        #expect(h.monitor.mask.contains(.flagsChanged))
        #expect(h.monitor.mask.contains(.leftMouseDown))
        #expect(h.log.recording == [true])
        #expect(h.log.announcements == [ShortcutRecorderModel.instructions(allowsClearing: true)])
    }

    @Test func `escape cancels, removes the monitor and resumes hot keys`() {
        let h = Harness()
        h.start()
        #expect(h.recorder.handleKeyDown(keyCode: 0x35, flags: []))
        #expect(!h.recorder.isListening)
        #expect(!h.monitor.isInstalled)
        #expect(h.monitor.removes == 1)
        #expect(h.log.recording == [true, false])
        #expect(h.log.commits.isEmpty)
    }

    @Test func `cancelling twice resumes hot keys once`() {
        let h = Harness()
        h.start()
        h.recorder.cancel()
        h.recorder.cancel()
        #expect(h.log.recording == [true, false])
        #expect(h.monitor.removes == 1)
    }

    @Test func `tab stops listening and passes the key on`() {
        let h = Harness()
        h.start()
        #expect(!h.recorder.handleKeyDown(keyCode: 0x30, flags: []), "Tab must reach the window to move focus")
        #expect(!h.recorder.isListening)
        #expect(h.log.recording == [true, false])
    }

    @Test func `only one recorder listens at a time`() {
        let h = Harness()
        let other = ShortcutRecorderModel(
            monitor: FakeEventMonitor().monitor,
            notificationCenter: h.notifications,
            observesKeyboardLayout: false,
            announce: { _ in }
        )
        h.start()
        h.start(.toggleBoost, on: other)
        #expect(!h.recorder.isListening)
        #expect(other.isListening)
        #expect(h.log.recording == [true, false, true], "The first pause ends before the second starts")
        other.cancel()
    }

    @Test func `the window losing key status or closing cancels`() {
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            let h = Harness()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            let anchor = NSView(frame: NSRect(x: 10, y: 10, width: 50, height: 26))
            window.contentView?.addSubview(anchor)
            h.recorder.anchor = anchor
            h.start()
            h.notifications.post(name: name, object: window)
            #expect(!h.recorder.isListening, "\(name.rawValue)")
            #expect(h.log.recording == [true, false])
        }
    }

    @Test func `a click outside the recorder cancels, a click on it is left to the button`() {
        let h = Harness()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 10, y: 10, width: 50, height: 26))
        window.contentView?.addSubview(anchor)
        h.recorder.anchor = anchor
        h.start()

        h.recorder.handleMouseDown(in: window, at: NSPoint(x: 20, y: 20))
        #expect(h.recorder.isListening)

        h.recorder.handleMouseDown(in: window, at: NSPoint(x: 150, y: 80))
        #expect(!h.recorder.isListening)
    }

    @Test func `a click in another window cancels`() {
        let h = Harness()
        h.start()
        h.recorder.handleMouseDown(in: nil, at: .zero)
        #expect(!h.recorder.isListening)
    }

    @Test func `nothing is handled when not listening`() {
        let h = Harness()
        #expect(!h.recorder.handleKeyDown(keyCode: 0x28, flags: ctrlOptCmd))
        #expect(h.log.commits.isEmpty)
    }

    // MARK: Recording

    @Test func `a valid combination is committed and announced`() throws {
        let h = Harness()
        h.start()
        #expect(h.recorder.handleKeyDown(keyCode: 0x28, flags: ctrlOptCmd.union([.capsLock])))
        let committed = try #require(h.log.commits.first ?? nil)
        #expect(committed == KeyShortcut(keyCode: 0x28, keyLabel: "K", modifiers: [.control, .option, .command]))
        #expect(committed.keyLabel == "K")
        #expect(!h.recorder.isListening)
        #expect(h.log.recording == [true, false])
        #expect(h.log.announcements.last == "Shortcut set to Control Option Command K.")
    }

    @Test func `held modifiers show while listening`() {
        let h = Harness()
        h.start()
        h.recorder.handleFlagsChanged([.control, .option])
        #expect(h.recorder.heldModifiers == [.control, .option])
        h.recorder.handleFlagsChanged([])
        #expect(h.recorder.heldModifiers == [])
        #expect(h.recorder.isListening)
    }

    @Test func `a modifier-only key down keeps listening`() {
        let h = Harness()
        h.start()
        #expect(h.recorder.handleKeyDown(keyCode: 0x37, flags: .command))
        #expect(h.recorder.isListening)
        #expect(h.log.commits.isEmpty)
    }

    @Test func `key repeats are swallowed and ignored`() {
        let h = Harness()
        h.start()
        #expect(h.recorder.handleKeyDown(keyCode: 0x28, flags: ctrlOptCmd, isRepeat: true))
        #expect(h.recorder.isListening)
        #expect(h.log.commits.isEmpty)
    }

    @Test func `refused keys show why and keep listening`() {
        let h = Harness()
        h.start(.toggleBoost)
        let panic = KeyShortcut.defaultPanic
        #expect(h.recorder.handleKeyDown(keyCode: panic.keyCode, flags: ctrlOptCmd))
        #expect(h.recorder.rejection == .problem(.taken(by: .panic)))
        #expect(h.recorder.isListening)
        #expect(h.log.commits.isEmpty)
        #expect(h.log.announcements.last == ShortcutRecorderModel.message(for: .problem(.taken(by: .panic))))

        // A good combination afterwards still records, and the message goes.
        #expect(h.recorder.handleKeyDown(keyCode: 0x28, flags: [.control, .command]))
        #expect(h.log.commits.count == 1)
        #expect(h.recorder.rejection == nil)
    }

    @Test func `a key without control or command is refused`() {
        let h = Harness()
        h.start()
        h.recorder.handleKeyDown(keyCode: 0x28, flags: .option)
        #expect(h.recorder.rejection == .problem(.needsControlOrCommand))
    }

    @Test func `system shortcuts are refused`() {
        let h = Harness()
        h.start()
        h.recorder.handleKeyDown(keyCode: 0x0C, flags: .command) // ⌘Q
        #expect(h.recorder.rejection == .problem(.reservedBySystem))
        #expect(h.recorder.isListening)
    }

    @Test func `escape clears a refusal by ending listening`() {
        let h = Harness()
        h.start()
        h.recorder.handleKeyDown(keyCode: 0x28, flags: .option)
        h.recorder.handleKeyDown(keyCode: 0x35, flags: [])
        #expect(h.recorder.rejection == nil)
    }

    // MARK: Clearing

    @Test func `delete clears a quick key`() {
        let h = Harness()
        h.start()
        #expect(h.recorder.handleKeyDown(keyCode: 0x33, flags: []))
        #expect(h.log.commits.count == 1)
        #expect(h.log.commits.first == .some(nil))
        #expect(!h.recorder.isListening)
    }

    @Test func `delete never clears the panic key`() {
        let h = Harness()
        h.start(.panic, allowsClearing: false)
        #expect(h.recorder.handleKeyDown(keyCode: 0x33, flags: []))
        #expect(h.log.commits.isEmpty)
        #expect(h.recorder.rejection == .cannotClear)
        #expect(h.recorder.isListening)
        #expect(h.log.announcements.first == ShortcutRecorderModel.instructions(allowsClearing: false))
    }

    // MARK: Events through the monitor

    @Test func `key events from the monitor are swallowed, Tab is not`() throws {
        let h = Harness()
        h.start()
        let handler = try #require(h.monitor.handler)
        let tab = try #require(Self.keyEvent(keyCode: 0x30, flags: [], characters: "\t"))
        let optionK = try #require(Self.keyEvent(keyCode: 0x28, flags: .option, characters: "˚"))
        #expect(handler(optionK) == nil)
        #expect(h.recorder.rejection == .problem(.needsControlOrCommand))
        #expect(handler(tab) === tab)
        #expect(!h.recorder.isListening)
    }

    // MARK: Labels and copy

    @Test func `labels come from the display label and follow layout changes`() {
        var name = "K"
        let recorder = ShortcutRecorderModel(
            monitor: FakeEventMonitor().monitor,
            displayLabel: { _ in name },
            observesKeyboardLayout: false,
            announce: { _ in }
        )
        let shortcut = KeyShortcut(keyCode: 0x28, keyLabel: "K", modifiers: [.control, .command])
        #expect(recorder.labels(for: shortcut).keycaps == ["⌃", "⌘", "K"])
        name = "T"
        #expect(recorder.labels(for: shortcut).keycaps.last == "K", "Cached until the layout changes")
        recorder.keyboardLayoutDidChange()
        #expect(recorder.labels(for: shortcut).keycaps.last == "T")
        #expect(recorder.labels(for: shortcut).spokenName == "Control Command T")
    }

    @Test(arguments: [
        ShortcutCapture.Rejection.cannotClear,
        .problem(.needsControlOrCommand),
        .problem(.reservedBySystem),
        .problem(.taken(by: .panic)),
        .problem(.taken(by: .toggleDeskMode)),
        .problem(.taken(by: .toggleBoost)),
    ])
    func `every refusal has its own message`(rejection: ShortcutCapture.Rejection) {
        let all: [ShortcutCapture.Rejection] = [
            .cannotClear, .problem(.needsControlOrCommand), .problem(.reservedBySystem),
            .problem(.taken(by: .panic)), .problem(.taken(by: .toggleDeskMode)), .problem(.taken(by: .toggleBoost)),
        ]
        let message = ShortcutRecorderModel.message(for: rejection)
        #expect(!message.isEmpty)
        #expect(all.filter { ShortcutRecorderModel.message(for: $0) == message }.count == 1)
    }

    private static func keyEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
