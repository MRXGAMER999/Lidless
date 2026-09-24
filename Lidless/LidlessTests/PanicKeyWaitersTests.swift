import Foundation
import LidlessCore
import Testing
@testable import Lidless

/// "Try It" and onboarding's "Try it now": waiting for the panic key only
/// watches it. Every press still runs the whole panic.
@MainActor
struct PanicKeyWaitersTests {
    // MARK: The list

    @Test func `every waiter runs once, in order`() {
        let waiters = PanicKeyWaiters()
        var calls: [String] = []
        waiters.add { calls.append("settings") }
        waiters.add { calls.append("onboarding") }
        #expect(waiters.count == 2)

        waiters.fire()
        #expect(calls == ["settings", "onboarding"])
        #expect(!waiters.isWaiting)
        waiters.fire()
        #expect(calls == ["settings", "onboarding"])
    }

    @Test func `cancelling ends every wait`() {
        let waiters = PanicKeyWaiters()
        var fired = 0
        waiters.add { fired += 1 }
        waiters.add { fired += 1 }
        waiters.cancelAll()
        waiters.fire()
        #expect(fired == 0)
        #expect(!waiters.isWaiting)
    }

    @Test func `waiting again from the callback waits for the next press`() {
        let waiters = PanicKeyWaiters()
        var fired = 0
        func wait() { waiters.add { fired += 1; if fired == 1 { wait() } } }
        wait()
        waiters.fire()
        #expect(fired == 1)
        #expect(waiters.isWaiting)
        waiters.fire()
        #expect(fired == 2)
        #expect(!waiters.isWaiting)
    }

    // MARK: Through the controller

    @MainActor
    private struct Rig {
        let desk = DeskModeRig()
        let registrar: FakeHotKeyRegistrar
        let boost = InterlockSpy()

        init() {
            registrar = FakeHotKeyRegistrar()
            desk.controller.boost = boost
            desk.controller.bindHotKeys(.fake(registrar))
        }
    }

    @Test func `a press while waiting and idle still runs the whole panic`() {
        let rig = Rig()
        rig.desk.connect()
        _ = rig.desk.log.take()
        var fired = 0
        rig.desk.controller.awaitPanicKey { fired += 1 }

        #expect(rig.registrar.press(.panic))
        #expect(fired == 1)
        // Boost ends and shades go, and idle's enable fallback runs.
        #expect(rig.boost.panics == 1)
        #expect(rig.desk.log.take().filter(\.touchesDisplay) == [.enable(1)])

        // Once only.
        #expect(rig.registrar.press(.panic))
        #expect(fired == 1)
        #expect(rig.boost.panics == 2)
    }

    @Test func `a press while waiting brings the screen back from Desk Mode`() {
        let rig = Rig()
        rig.desk.turnOnAndKeep()
        var fired = 0
        rig.desk.controller.awaitPanicKey { fired += 1 }

        #expect(rig.registrar.press(.panic))
        #expect(rig.desk.log.take() == [.hide, .enable(1)])
        #expect(fired == 1)
    }

    @Test func `both waiting screens hear the press`() {
        let rig = Rig()
        rig.desk.connect()
        var settings = 0
        var onboarding = 0
        rig.desk.controller.awaitPanicKey { settings += 1 }
        rig.desk.controller.awaitPanicKey { onboarding += 1 }
        #expect(rig.registrar.press(.panic))
        #expect(settings == 1)
        #expect(onboarding == 1)
    }

    @Test func `a new panic shortcut keeps the wait`() {
        let rig = Rig()
        defer { rig.desk.cleanUp() }
        rig.desk.connect()
        var fired = 0
        rig.desk.controller.awaitPanicKey { fired += 1 }

        let shortcut = KeyShortcut(keyCode: 0x0F, keyLabel: "R", modifiers: [.control, .option, .command])
        rig.desk.model.preferences.shortcuts.panic = shortcut
        #expect(rig.registrar.held[HotKeyID.panic.rawValue] == UInt32(shortcut.keyCode))

        #expect(rig.registrar.press(.panic))
        #expect(fired == 1)
    }

    @Test func `recording a shortcut keeps the wait and the panic key`() {
        let registrar = FakeHotKeyRegistrar()
        let center = HotKeyCenter.fake(registrar)
        let desk = DeskModeRig()
        desk.controller.bindHotKeys(center)
        desk.connect()
        var fired = 0
        desk.controller.awaitPanicKey { fired += 1 }

        center.isPaused = true
        #expect(registrar.press(.panic))
        center.isPaused = false
        #expect(fired == 1)
    }

    @Test func `a cancelled wait hears nothing, but the key still panics`() {
        let rig = Rig()
        rig.desk.connect()
        _ = rig.desk.log.take()
        var fired = 0
        rig.desk.controller.awaitPanicKey { fired += 1 }
        rig.desk.controller.cancelAwaitPanicKey()

        #expect(rig.registrar.press(.panic))
        #expect(fired == 0)
        #expect(rig.boost.panics == 1)
        #expect(rig.desk.log.take().filter(\.touchesDisplay) == [.enable(1)])
    }

    @Test func `only the key itself counts, not the intent's panic`() {
        let rig = Rig()
        rig.desk.connect()
        var fired = 0
        rig.desk.controller.awaitPanicKey { fired += 1 }
        rig.desk.controller.panic()
        #expect(fired == 0)
        #expect(rig.desk.controller.panicKeyWaiters.isWaiting)
    }

    @Test func `quitting drops the waits`() {
        let rig = Rig()
        rig.desk.connect()
        rig.desk.controller.awaitPanicKey {}
        rig.desk.controller.terminate()
        #expect(!rig.desk.controller.panicKeyWaiters.isWaiting)
    }

    // MARK: A panic key Carbon refuses

    @Test func `a new panic key Carbon refuses puts the old one back`() async throws {
        let registrar = RefusingHotKeyRegistrar()
        let refused = KeyShortcut(keyCode: 0x0F, keyLabel: "R", modifiers: [.control, .option, .command])
        registrar.refusedKeyCodes = [UInt32(refused.keyCode)]
        let center = HotKeyCenter(
            registrar: registrar,
            notificationCenter: NotificationCenter(),
            keyDownMonitor: HotKeyCenter.KeyDownMonitor(add: { _ in nil }, remove: { _ in })
        )
        let desk = DeskModeRig()
        defer { desk.cleanUp() }
        desk.controller.bindHotKeys(center)
        desk.connect()
        _ = desk.log.take()

        desk.model.preferences.shortcuts.panic = refused
        // At once: the old key is held again, so it never stops working.
        #expect(registrar.held[HotKeyID.panic.rawValue] == UInt32(KeyShortcut.defaultPanic.keyCode))
        #expect(center.registrations[.panic]?.isRegistered == true)
        #expect(registrar.press(.panic))
        #expect(desk.log.take().filter(\.touchesDisplay) == [.enable(1)])

        // Then the saved shortcut follows, on the next turn of the main queue.
        for _ in 0..<100 where desk.model.preferences.shortcuts.panic != .defaultPanic {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(desk.model.preferences.shortcuts.panic == .defaultPanic)
        #expect(desk.model.deskMode.panicShortcut == .defaultPanic)
        #expect(registrar.held[HotKeyID.panic.rawValue] == UInt32(KeyShortcut.defaultPanic.keyCode))
        #expect(desk.model.preferences.shortcuts.toggleDeskMode == .defaultDeskMode)
    }

    @Test func `a panic key Carbon accepts stays`() async throws {
        let registrar = RefusingHotKeyRegistrar()
        let center = HotKeyCenter(
            registrar: registrar,
            notificationCenter: NotificationCenter(),
            keyDownMonitor: HotKeyCenter.KeyDownMonitor(add: { _ in nil }, remove: { _ in })
        )
        let desk = DeskModeRig()
        defer { desk.cleanUp() }
        desk.controller.bindHotKeys(center)
        let shortcut = KeyShortcut(keyCode: 0x0F, keyLabel: "R", modifiers: [.control, .option, .command])
        desk.model.preferences.shortcuts.panic = shortcut
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(desk.model.preferences.shortcuts.panic == shortcut)
        #expect(registrar.held[HotKeyID.panic.rawValue] == UInt32(shortcut.keyCode))
    }
}

/// Carbon that refuses some key codes, as when another process holds them in
/// a way `RegisterEventHotKey` reports as an error.
@MainActor
final class RefusingHotKeyRegistrar: HotKeyRegistrar {
    var onPress: (@MainActor (UInt32) -> Bool)?
    var refusedKeyCodes: Set<UInt32> = []
    /// Key codes held, by hot key ID.
    private(set) var held: [UInt32: UInt32] = [:]

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, exclusive: Bool) -> OSStatus {
        // paramErr: anything but "exists", which the panic key would retry shared.
        guard !refusedKeyCodes.contains(keyCode) else { return -50 }
        held[id] = keyCode
        return 0
    }

    func unregister(id: UInt32) { held[id] = nil }

    func press(_ id: HotKeyID) -> Bool { onPress?(id.rawValue) ?? false }
}
