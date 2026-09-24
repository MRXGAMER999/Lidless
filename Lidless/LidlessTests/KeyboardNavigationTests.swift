import AppKit
import Combine
import Testing
@testable import Lidless

@MainActor
struct KeyboardNavigationTests {
    private final class FakeSetting {
        var enabled = false
    }

    private let setting = FakeSetting()
    private let center = NotificationCenter()

    private func makeNavigation() -> KeyboardNavigation {
        let setting = setting
        return KeyboardNavigation(readSetting: { setting.enabled }, notificationCenter: center)
    }

    private func windowBecomesKey() {
        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    @Test func `reads the setting when created`() {
        setting.enabled = true
        #expect(makeNavigation().isEnabled)
    }

    @Test func `reads the setting again when a window becomes key`() {
        let navigation = makeNavigation()
        setting.enabled = true
        #expect(!navigation.isEnabled)
        windowBecomesKey()
        #expect(navigation.isEnabled)
        setting.enabled = false
        windowBecomesKey()
        #expect(!navigation.isEnabled)
    }

    @Test func `publishes only when the setting actually changes`() {
        let navigation = makeNavigation()
        var changes = 0
        let subscription = navigation.objectWillChange.sink { changes += 1 }
        windowBecomesKey()
        #expect(changes == 0)
        setting.enabled = true
        windowBecomesKey()
        windowBecomesKey()
        #expect(changes == 1)
        subscription.cancel()
    }
}
