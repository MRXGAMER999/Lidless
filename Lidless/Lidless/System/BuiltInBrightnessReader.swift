import CoreGraphics
import Foundation
import LidlessCore

/// Built-in brightness through DisplayServices, read-only. Setting brightness
/// arrives in Phase 4; nothing here may change it.
///
/// Only one instance should observe at a time: `BrightnessChangeRelay` is a singleton.
final class DisplayServicesBrightnessReader: BrightnessReader {
    private var cachedPanelInfo: PanelBrightnessInfo?
    /// Read from `deinit`, so it stays a plain Sendable scalar.
    private var observedDisplay: CGDirectDisplayID?

    init() {}

    deinit {
        // deinit is nonisolated, so it can't reach the main-actor relay. Telling
        // DisplayServices is enough: the next observe resets the relay.
        if let display = observedDisplay {
            _ = DisplayServicesAPI.unregisterForBrightnessChanges?(display, UnsafeRawPointer(bitPattern: UInt(display)))
        }
    }

    func panelInfo() -> PanelBrightnessInfo {
        if let cachedPanelInfo { return cachedPanelInfo }
        let info = PanelInfoReader.read()
        cachedPanelInfo = info
        return info
    }

    func level(of display: CGDirectDisplayID) -> BrightnessLevelReading? {
        // CoreGraphics' own state, not the controller's inventory: that one
        // waits for the debounced display refresh, and DisplayServices is
        // untested on a display that went offline (lid closed, Desk Mode).
        guard display != 0, CGDisplayIsOnline(display) != 0,
              let getBrightness = DisplayServicesAPI.getBrightness else { return nil }
        // 1000 means macOS doesn't dim this display (most external monitors).
        var level: Float = 0
        guard getBrightness(display, &level) == 0, level.isFinite else { return nil }
        return BrightnessLevelReading(
            level: min(max(Double(level), 0), 1),
            linear: linearBrightness(of: display),
            autoBrightness: autoBrightness(of: display)
        )
    }

    @discardableResult
    func observe(_ display: CGDirectDisplayID, onChange: @escaping @MainActor () -> Void) -> Bool {
        stopObserving()
        guard display != 0, let register = DisplayServicesAPI.registerForBrightnessChanges else { return false }
        BrightnessChangeRelay.set(display: display, handler: onChange)
        // Always returns 0, even when nothing was registered, which is why the
        // controller also polls while the popover is open.
        _ = register(display, BrightnessChangeRelay.observer(for: display), brightnessDidChange)
        observedDisplay = display
        return true
    }

    func stopObserving() {
        if let display = observedDisplay {
            // DisplayServices matches registrations by observer, so pass the same pointer.
            _ = DisplayServicesAPI.unregisterForBrightnessChanges?(display, BrightnessChangeRelay.observer(for: display))
            observedDisplay = nil
            BrightnessChangeRelay.set(display: nil, handler: nil)
        }
    }

    // Not clamped: it may exceed 1 in auto-brightness's outdoor range.
    private func linearBrightness(of display: CGDirectDisplayID) -> Double? {
        guard let getLinear = DisplayServicesAPI.getLinearBrightness else { return nil }
        var linear: Float = 0
        guard getLinear(display, &linear) == 0, linear.isFinite else { return nil }
        return Double(linear)
    }

    private func autoBrightness(of display: CGDirectDisplayID) -> Bool? {
        guard let isEnabled = DisplayServicesAPI.autoBrightnessEnabled else { return nil }
        var enabled = false
        return isEnabled(display, &enabled) == 0 ? enabled : nil
    }
}
