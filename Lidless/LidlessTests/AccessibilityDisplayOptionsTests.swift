import AppKit
import Combine
import Testing
@testable import Lidless

@MainActor
struct AccessibilityDisplayOptionsTests {
    private final class FakeSettings {
        var snapshot = AccessibilityDisplayOptions.Snapshot()
    }

    private let settings = FakeSettings()
    private let center = NotificationCenter()

    private func makeOptions() -> AccessibilityDisplayOptions {
        let settings = settings
        return AccessibilityDisplayOptions(read: { settings.snapshot }, notificationCenter: center)
    }

    private func systemSettingsChange() {
        center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @Test func `reads the settings when created`() {
        settings.snapshot.increaseContrast = true
        let options = makeOptions()
        #expect(options.current.increaseContrast)
        #expect(!options.current.reduceTransparency)
    }

    @Test func `follows the system's change notification`() {
        let options = makeOptions()
        settings.snapshot.reduceTransparency = true
        #expect(!options.current.reduceTransparency)
        systemSettingsChange()
        #expect(options.current.reduceTransparency)
        settings.snapshot = .init(increaseContrast: true, reduceTransparency: false)
        systemSettingsChange()
        #expect(options.current == .init(increaseContrast: true, reduceTransparency: false))
    }

    @Test func `publishes only when a setting actually changes`() {
        let options = makeOptions()
        var changes = 0
        let subscription = options.objectWillChange.sink { changes += 1 }
        systemSettingsChange()
        #expect(changes == 0)
        settings.snapshot.increaseContrast = true
        systemSettingsChange()
        systemSettingsChange()
        #expect(changes == 1)
        subscription.cancel()
    }
}
