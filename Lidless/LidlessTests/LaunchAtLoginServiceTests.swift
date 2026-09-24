import Foundation
import Testing
@testable import Lidless

/// `LaunchAtLoginService` over a fake ServiceManagement, so nothing is
/// registered on the machine running the tests.
@MainActor
struct LaunchAtLoginServiceTests {
    private final class FakeBackend: LoginItemBackend {
        var isAvailable = true
        var status: LoginItemStatus = .notRegistered
        /// What `register()` leaves behind; nil throws without changing it.
        var statusAfterRegister: LoginItemStatus? = .enabled
        var registerCalls = 0
        var unregisterCalls = 0
        var openCalls = 0
        var failUnregister = false

        struct Failure: Error {}

        func register() throws {
            registerCalls += 1
            guard let statusAfterRegister else { throw Failure() }
            status = statusAfterRegister
        }

        func unregister() throws {
            unregisterCalls += 1
            if failUnregister { throw Failure() }
            status = .notRegistered
        }

        func openSettings() { openCalls += 1 }
    }

    @Test func `reads the live status every time`() {
        let backend = FakeBackend()
        let service = LaunchAtLoginService(backend: backend)
        #expect(!service.isEnabled)
        backend.status = .enabled
        #expect(service.isEnabled)
        backend.status = .requiresApproval
        #expect(!service.isEnabled)
        #expect(service.needsApproval)
    }

    @Test func `switching on registers, and succeeds only once enabled`() {
        let backend = FakeBackend()
        let service = LaunchAtLoginService(backend: backend)
        #expect(service.setEnabled(true))
        #expect(backend.registerCalls == 1)
        #expect(service.isEnabled)

        // Already on: no second register (it would fail with "already registered").
        #expect(service.setEnabled(true))
        #expect(backend.registerCalls == 1)
    }

    @Test func `a register that needs approval or throws reports failure`() {
        let backend = FakeBackend()
        backend.statusAfterRegister = .requiresApproval
        let service = LaunchAtLoginService(backend: backend)
        #expect(!service.setEnabled(true))
        #expect(service.needsApproval)

        backend.status = .notFound
        backend.statusAfterRegister = nil
        #expect(!service.setEnabled(true))
        #expect(!service.isEnabled)
    }

    @Test func `switching off unregisters only when registered`() {
        let backend = FakeBackend()
        let service = LaunchAtLoginService(backend: backend)
        #expect(service.setEnabled(false))
        #expect(backend.unregisterCalls == 0)

        backend.status = .requiresApproval
        #expect(service.setEnabled(false))
        #expect(backend.unregisterCalls == 1)

        backend.status = .enabled
        backend.failUnregister = true
        #expect(!service.setEnabled(false))
        #expect(service.isEnabled)
    }

    @Test func `unavailable below macOS 13`() {
        let backend = FakeBackend()
        backend.isAvailable = false
        backend.status = .enabled
        let service = LaunchAtLoginService(backend: backend)
        #expect(!service.isAvailable)
        #expect(!service.isEnabled)
        #expect(!service.needsApproval)
        #expect(!service.setEnabled(true))
        service.openLoginItemsSettings()
        #expect(backend.registerCalls == 0)
        #expect(backend.openCalls == 0)
    }

    @Test func `opens Login Items`() {
        let backend = FakeBackend()
        LaunchAtLoginService(backend: backend).openLoginItemsSettings()
        #expect(backend.openCalls == 1)
    }
}
