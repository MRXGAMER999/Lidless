import CoreGraphics
import Foundation
import LidlessCore

/// Brings DisplayServices' brightness callbacks (a CoreBrightness queue) to the
/// main actor, coalesced. The observer pointer carries the display ID, so the C
/// callback never dereferences memory that could be gone after unregistering.
enum BrightnessChangeRelay {
    private static var display: CGDirectDisplayID?
    private static var handler: (@MainActor () -> Void)?
    private static var schedule = RefreshSchedule(quiet: 0.05, maxWait: 0.1)
    private static var pending: DispatchWorkItem?

    static func set(display: CGDirectDisplayID?, handler: (@MainActor () -> Void)?) {
        self.display = display
        self.handler = handler
        pending?.cancel()
        pending = nil
        schedule.fired()
    }

    static func changed(_ id: CGDirectDisplayID) {
        guard id == display else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let fireAt = schedule.eventArrived(at: now)
        pending?.cancel()
        let item = DispatchWorkItem {
            MainActor.assumeIsolated {
                schedule.fired()
                pending = nil
                handler?()
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fireAt - now), execute: item)
    }

    static func observer(for id: CGDirectDisplayID) -> UnsafeRawPointer? {
        UnsafeRawPointer(bitPattern: UInt(id))
    }
}

nonisolated let brightnessDidChange: CFNotificationCallback = { _, observer, _, _, _ in
    let id = CGDirectDisplayID(truncatingIfNeeded: UInt(bitPattern: observer))
    DispatchQueue.main.async {
        MainActor.assumeIsolated { BrightnessChangeRelay.changed(id) }
    }
}
