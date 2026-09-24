import AppKit
import Carbon.HIToolbox
import LidlessCore
import Testing
@testable import Lidless

// No real global keys: every test registers through a fake registrar.

@MainActor
private final class FakeRegistrar: HotKeyRegistrar {
    struct Call: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        let id: UInt32
        let exclusive: Bool
    }

    var onPress: (@MainActor (UInt32) -> Bool)?
    /// Status for each attempt; `noErr` when empty.
    var exclusiveStatus: OSStatus = noErr
    var sharedStatus: OSStatus = noErr
    private(set) var calls: [Call] = []
    private(set) var unregistered: [UInt32] = []
    private(set) var held: Set<UInt32> = []

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, exclusive: Bool) -> OSStatus {
        calls.append(Call(keyCode: keyCode, modifiers: modifiers, id: id, exclusive: exclusive))
        let status = exclusive ? exclusiveStatus : sharedStatus
        if status == noErr { held.insert(id) }
        return status
    }

    func unregister(id: UInt32) {
        unregistered.append(id)
        held.remove(id)
    }

    /// What Carbon would do on a press: returns whether the handler took it.
    func press(_ id: HotKeyID) -> Bool {
        onPress?(id.rawValue) ?? false
    }
}

@MainActor
private final class FakeKeyMonitor {
    private(set) var handler: ((NSEvent) -> NSEvent?)?
    private(set) var adds = 0
    private(set) var removes = 0

    var monitor: HotKeyCenter.KeyDownMonitor {
        HotKeyCenter.KeyDownMonitor(
            add: { [self] handler in
                adds += 1
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

@MainActor
private final class Presses {
    private(set) var log: [String] = []
    func handler(_ name: String) -> @MainActor () -> Void {
        { [self] in log.append(name) }
    }
}

@MainActor
private func makeCenter(
    _ registrar: FakeRegistrar = FakeRegistrar(),
    monitor: FakeKeyMonitor = FakeKeyMonitor(),
    notifications: NotificationCenter = NotificationCenter()
) -> HotKeyCenter {
    HotKeyCenter(registrar: registrar, notificationCenter: notifications, keyDownMonitor: monitor.monitor)
}

private let deskKeys = KeyShortcut.defaultDeskMode
private let otherKeys = KeyShortcut(keyCode: 0x0E, keyLabel: "E", modifiers: [.control, .command])

struct HotKeyModifierTests {
    @Test func `each modifier maps to its Carbon bit`() {
        #expect(HotKeyCenter.carbonModifiers([]) == 0)
        #expect(HotKeyCenter.carbonModifiers(.control) == UInt32(controlKey))
        #expect(HotKeyCenter.carbonModifiers(.option) == UInt32(optionKey))
        #expect(HotKeyCenter.carbonModifiers(.shift) == UInt32(shiftKey))
        #expect(HotKeyCenter.carbonModifiers(.command) == UInt32(cmdKey))
    }

    @Test func `the default panic key is control option command`() {
        #expect(HotKeyCenter.carbonModifiers(KeyShortcut.defaultPanic.modifiers) == UInt32(controlKey | optionKey | cmdKey))
    }

    @Test func `event flags map back, ignoring caps lock, fn and keypad`() {
        let flags: NSEvent.ModifierFlags = [.control, .option, .command, .capsLock, .function, .numericPad]
        #expect(HotKeyCenter.modifiers(flags) == [.control, .option, .command])
        #expect(HotKeyCenter.modifiers(.shift) == .shift)
        #expect(HotKeyCenter.modifiers([]) == [])
    }
}

@MainActor
struct HotKeyRegistrationTests {
    @Test func `the panic key registers exclusively`() {
        let registrar = FakeRegistrar()
        let center = makeCenter(registrar)
        #expect(center.register(.defaultPanic, for: .panic) {} == .exclusive)
        #expect(registrar.calls == [.init(keyCode: 0x0B, modifiers: UInt32(controlKey | optionKey | cmdKey), id: 1, exclusive: true)])
        #expect(center.registrations == [.panic: .exclusive])
    }

    @Test func `the panic key falls back to shared when another app holds it exclusively`() {
        let registrar = FakeRegistrar()
        registrar.exclusiveStatus = OSStatus(eventHotKeyExistsErr)
        let center = makeCenter(registrar)
        #expect(center.register(.defaultPanic, for: .panic) {} == .shared)
        #expect(registrar.calls.map(\.exclusive) == [true, false])
    }

    @Test func `other panic errors fail without a fallback`() {
        let registrar = FakeRegistrar()
        registrar.exclusiveStatus = OSStatus(paramErr)
        let center = makeCenter(registrar)
        #expect(center.register(.defaultPanic, for: .panic) {} == .failed(OSStatus(paramErr)))
        #expect(registrar.calls.count == 1)
        #expect(center.registrations[.panic] == .failed(OSStatus(paramErr)))
    }

    @Test func `other keys register shared`() {
        let registrar = FakeRegistrar()
        let center = makeCenter(registrar)
        #expect(center.register(deskKeys, for: .toggleDeskMode) {} == .shared)
        #expect(registrar.calls.map(\.exclusive) == [false])
        #expect(registrar.calls.map(\.id) == [HotKeyID.toggleDeskMode.rawValue])
    }

    @Test func `a failed shared registration reports Carbon's status`() {
        let registrar = FakeRegistrar()
        registrar.sharedStatus = -9868
        let center = makeCenter(registrar)
        #expect(center.register(deskKeys, for: .toggleBoost) {} == .failed(-9868))
        #expect(registrar.held.isEmpty)
    }

    @Test func `a new shortcut replaces the old one`() {
        let registrar = FakeRegistrar()
        let center = makeCenter(registrar)
        center.register(deskKeys, for: .toggleDeskMode) {}
        center.register(otherKeys, for: .toggleDeskMode) {}
        #expect(registrar.unregistered == [HotKeyID.toggleDeskMode.rawValue])
        #expect(registrar.calls.last?.keyCode == 0x0E)
        #expect(registrar.held == [HotKeyID.toggleDeskMode.rawValue])
    }

    @Test func `the same shortcut again only swaps the handler`() {
        let registrar = FakeRegistrar()
        let presses = Presses()
        let center = makeCenter(registrar)
        center.register(deskKeys, for: .toggleDeskMode, handler: presses.handler("old"))
        center.register(deskKeys, for: .toggleDeskMode, handler: presses.handler("new"))
        #expect(registrar.calls.count == 1)
        #expect(registrar.unregistered.isEmpty)
        #expect(registrar.press(.toggleDeskMode))
        #expect(presses.log == ["new"])
    }

    @Test func `a combination another key holds fails without asking Carbon`() {
        let registrar = FakeRegistrar()
        let center = makeCenter(registrar)
        center.register(.defaultPanic, for: .panic) {}
        #expect(center.register(.defaultPanic, for: .toggleBoost) {} == .failed(OSStatus(eventHotKeyExistsErr)))
        #expect(registrar.calls.count == 1)
    }

    @Test func `the panic key takes its combination from another key`() {
        let registrar = FakeRegistrar()
        let center = makeCenter(registrar)
        center.register(deskKeys, for: .toggleDeskMode) {}
        #expect(center.register(deskKeys, for: .panic) {} == .exclusive)
        #expect(registrar.unregistered == [HotKeyID.toggleDeskMode.rawValue])
        #expect(center.registrations[.toggleDeskMode] == .failed(OSStatus(eventHotKeyExistsErr)))
        #expect(registrar.held == [HotKeyID.panic.rawValue])
    }

    @Test func `unregister and unregisterAll release Carbon's keys`() {
        let registrar = FakeRegistrar()
        let center = makeCenter(registrar)
        center.register(.defaultPanic, for: .panic) {}
        center.register(deskKeys, for: .toggleDeskMode) {}
        center.register(KeyShortcut.defaultBoost, for: .toggleBoost) {}
        center.unregister(.toggleBoost)
        #expect(center.registrations[.toggleBoost] == nil)
        #expect(registrar.held.count == 2)
        center.unregisterAll()
        #expect(registrar.held.isEmpty)
        #expect(center.registrations.isEmpty)
    }

    @Test func `a failed key is not unregistered`() {
        let registrar = FakeRegistrar()
        registrar.sharedStatus = OSStatus(paramErr)
        let center = makeCenter(registrar)
        center.register(deskKeys, for: .toggleDeskMode) {}
        center.unregister(.toggleDeskMode)
        #expect(registrar.unregistered.isEmpty)
    }
}

@MainActor
struct HotKeyDispatchTests {
    @Test func `a press runs the handler for its ID`() {
        let registrar = FakeRegistrar()
        let presses = Presses()
        let center = makeCenter(registrar)
        center.register(.defaultPanic, for: .panic, handler: presses.handler("panic"))
        center.register(deskKeys, for: .toggleDeskMode, handler: presses.handler("desk"))
        #expect(registrar.press(.toggleDeskMode))
        #expect(registrar.press(.panic))
        #expect(presses.log == ["desk", "panic"])
    }

    @Test func `unknown and released IDs are passed on`() {
        let registrar = FakeRegistrar()
        let presses = Presses()
        let center = makeCenter(registrar)
        center.register(deskKeys, for: .toggleDeskMode, handler: presses.handler("desk"))
        #expect(registrar.onPress?(99) == false)
        #expect(!registrar.press(.toggleBoost))
        center.unregister(.toggleDeskMode)
        #expect(!registrar.press(.toggleDeskMode))
        #expect(presses.log.isEmpty)
    }
}

@MainActor
struct HotKeyPauseTests {
    @Test func `pausing keeps only the panic key`() {
        let registrar = FakeRegistrar()
        let center = makeCenter(registrar)
        center.register(.defaultPanic, for: .panic) {}
        center.register(deskKeys, for: .toggleDeskMode) {}
        center.isPaused = true
        #expect(registrar.held == [HotKeyID.panic.rawValue])
        #expect(center.registrations == [.panic: .exclusive, .toggleDeskMode: .deferred])
        #expect(!(center.registrations[.toggleDeskMode]?.isRegistered ?? true))
        #expect(!registrar.press(.toggleDeskMode))
    }

    @Test func `resuming registers the paused keys again`() {
        let registrar = FakeRegistrar()
        let presses = Presses()
        let center = makeCenter(registrar)
        center.register(deskKeys, for: .toggleDeskMode, handler: presses.handler("desk"))
        center.isPaused = true
        center.isPaused = false
        #expect(center.registrations[.toggleDeskMode] == .shared)
        #expect(registrar.press(.toggleDeskMode))
        #expect(presses.log == ["desk"])
    }

    @Test func `keys set while paused wait for the resume`() {
        let registrar = FakeRegistrar()
        let center = makeCenter(registrar)
        center.isPaused = true
        let result = center.register(otherKeys, for: .toggleBoost) {}
        #expect(result == .deferred)
        #expect(!result.isRegistered)
        #expect(center.registrations[.toggleBoost] == .deferred)
        #expect(registrar.calls.isEmpty)
        #expect(center.register(.defaultPanic, for: .panic) {} == .exclusive)
        center.isPaused = false
        #expect(registrar.held == [HotKeyID.panic.rawValue, HotKeyID.toggleBoost.rawValue])
        #expect(center.registrations[.toggleBoost] == .shared)
    }
}

@MainActor
struct HotKeyMenuTrackingTests {
    private let panicFlags: NSEvent.ModifierFlags = [.control, .option, .command]

    @Test func `the monitor runs only while a menu is open`() {
        let monitor = FakeKeyMonitor()
        let notifications = NotificationCenter()
        let center = makeCenter(monitor: monitor, notifications: notifications)
        center.register(.defaultPanic, for: .panic) {}
        #expect(monitor.adds == 0)
        notifications.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        #expect(monitor.adds == 1)
        notifications.post(name: NSMenu.didEndTrackingNotification, object: nil)
        #expect(monitor.removes == 1)
        #expect(monitor.handler == nil)
    }

    @Test func `nested menus keep one monitor until the last closes`() {
        let monitor = FakeKeyMonitor()
        let notifications = NotificationCenter()
        let center = makeCenter(monitor: monitor, notifications: notifications)
        center.register(.defaultPanic, for: .panic) {}
        notifications.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        notifications.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        notifications.post(name: NSMenu.didEndTrackingNotification, object: nil)
        #expect(monitor.adds == 1)
        #expect(monitor.removes == 0)
        notifications.post(name: NSMenu.didEndTrackingNotification, object: nil)
        #expect(monitor.removes == 1)
    }

    @Test func `the panic combination fires while a menu is open`() {
        let presses = Presses()
        let notifications = NotificationCenter()
        let center = makeCenter(notifications: notifications)
        center.register(.defaultPanic, for: .panic, handler: presses.handler("panic"))
        #expect(!center.handleKeyDownInMenu(keyCode: 0x0B, flags: panicFlags))
        notifications.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        #expect(!center.handleKeyDownInMenu(keyCode: 0x0B, flags: [.control, .command]))
        #expect(!center.handleKeyDownInMenu(keyCode: 0x02, flags: panicFlags))
        #expect(center.handleKeyDownInMenu(keyCode: 0x0B, flags: panicFlags.union(.capsLock)))
        #expect(presses.log == ["panic"])
    }

    @Test func `other keys are left to the menu`() {
        let presses = Presses()
        let notifications = NotificationCenter()
        let center = makeCenter(notifications: notifications)
        center.register(deskKeys, for: .toggleDeskMode, handler: presses.handler("desk"))
        notifications.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        #expect(!center.handleKeyDownInMenu(keyCode: deskKeys.keyCode, flags: panicFlags))
        #expect(presses.log.isEmpty)
    }
}
