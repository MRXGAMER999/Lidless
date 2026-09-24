import Foundation
import IOKit
import IOKit.pwr_mgt
import LidlessCore

/// Reads the lid from IOPMrootDomain (about 8 µs).
enum LidReader {
    static func read() -> LidState {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return .unknown }
        defer { IOObjectRelease(rootDomain) }
        // Absent on Macs without a lid (desktops, VMs).
        let value = IORegistryEntryCreateCFProperty(rootDomain, kAppleClamshellStateKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return LidState(clamshellClosed: value as? Bool)
    }
}

/// Says when the lid opens or closes. The message is only a trigger: callers
/// re-read `LidReader`, and re-read again on wake because the message can be
/// delivered late or lost around sleep.
final class LidMonitor {
    // Non-Sendable handle released in deinit.
    nonisolated(unsafe) private var port: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL
    private var rootDomain: io_service_t = IO_OBJECT_NULL
    fileprivate var onChange: (@MainActor () -> Void)?

    var isObserving: Bool { port != nil }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard port == nil else { return }
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            IOObjectRelease(rootDomain)
            return
        }
        // Delivery on the main queue is what makes assumeIsolated in the trampoline sound.
        IONotificationPortSetDispatchQueue(port, .main)
        var notifier: io_object_t = IO_OBJECT_NULL
        let result = IOServiceAddInterestNotification(
            port, rootDomain, kIOGeneralInterest, lidInterest,
            Unmanaged.passUnretained(self).toOpaque(), &notifier
        )
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            IOObjectRelease(rootDomain)
            return
        }
        self.port = port
        self.notifier = notifier
        self.rootDomain = rootDomain
        self.onChange = onChange
    }

    func stop() {
        onChange = nil
        Self.release(notifier: notifier, port: port, rootDomain: rootDomain)
        notifier = IO_OBJECT_NULL
        port = nil
        rootDomain = IO_OBJECT_NULL
    }

    deinit {
        Self.release(notifier: notifier, port: port, rootDomain: rootDomain)
    }

    // The notifier goes before its port, so no callback outlives the refCon.
    private nonisolated static func release(notifier: io_object_t, port: IONotificationPortRef?, rootDomain: io_service_t) {
        if notifier != IO_OBJECT_NULL { IOObjectRelease(notifier) }
        if let port { IONotificationPortDestroy(port) }
        if rootDomain != IO_OBJECT_NULL { IOObjectRelease(rootDomain) }
    }
}

// C callback: captures nothing; the monitor arrives through refCon. The root
// domain sends other power messages through the same interest, hence the filter.
nonisolated func lidInterest(
    _ refCon: UnsafeMutableRawPointer?,
    _ service: io_service_t,
    _ messageType: UInt32,
    _ argument: UnsafeMutableRawPointer?
) {
    guard messageType == ClamshellMessage.messageType, let refCon else { return }
    let monitor = Unmanaged<LidMonitor>.fromOpaque(refCon).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.onChange?() }
}
