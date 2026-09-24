import CoreGraphics
import Foundation
import IOKit
import LidlessCore
import os

/// DDC/CI brightness (VCP 0x10) for one external display, over the display
/// coprocessor's `IOAVService` on Apple Silicon.
///
/// Every transfer runs on the display's serial queue with MonitorControl's
/// timings (MIT): 10 ms before each of 2 write cycles, 50 ms before the read,
/// up to 5 attempts 20 ms apart; writes at least 50 ms apart. Results arrive on
/// the main actor, always asynchronously. While `isPaused`, requests complete
/// as failed without touching the bus, and queued work re-checks the gate
/// before every I2C call, so pausing also stops work already under way.
///
/// A permanent failure (the coprocessor rejects the transfer, 0xE011xxxx: the
/// LG ULTRAGEAR on the M5 Pro HDMI port) makes the link dead: every later
/// request fails at once. Handles go stale when displays are re-enumerated, so
/// pause and drop links on a display reconfiguration and make new ones after it.
final class DDCLink {
    let displayID: CGDirectDisplayID
    private let channel: DDCChannel
    private let queue: DispatchQueue

    /// Gates all traffic: display reconfiguration, Desk Mode switching, sleep.
    var isPaused = false {
        didSet { channel.setPaused(isPaused) }
    }

    /// True after a permanent failure: stop using this display's DDC.
    var isDead: Bool { channel.isDead }

    private init(displayID: CGDirectDisplayID, channel: DDCChannel, queue: DispatchQueue) {
        self.displayID = displayID
        self.channel = channel
        self.queue = queue
    }

    /// Finds the display's `DCPAVServiceProxy` by its framebuffer (m1ddc's
    /// walk) and makes a link for it. The registry walk and
    /// `IOAVServiceCreateWithService` run on the display's serial queue, never
    /// on the main thread, and never overlap an older link's transfers.
    /// `completion` runs on the main actor, always asynchronously, with nil for
    /// the built-in, displays without a framebuffer location (virtual, Sidecar,
    /// AirPlay), no external proxy, or missing IOAVService calls.
    static func make(displayID: CGDirectDisplayID, completion: @escaping @MainActor (DDCLink?) -> Void) {
        let queue = DDCQueues.queue(for: displayID)
        queue.async { @Sendable in
            let channel = DDCChannel.find(displayID: displayID)
            DispatchQueue.main.async { @Sendable in
                MainActor.assumeIsolated {
                    completion(channel.map { DDCLink(displayID: displayID, channel: $0, queue: queue) })
                }
            }
        }
    }

    /// Reads luminance. `permanentFailure` is true when the link is (now) dead;
    /// a nil reply without it means no valid answer this time (paused, no DDC/CI,
    /// or a link that returns junk such as EDID bytes).
    func readLuminance(completion: @escaping @MainActor (DDC.Reply?, _ permanentFailure: Bool) -> Void) {
        guard !channel.isDead, !isPaused else {
            let dead = channel.isDead
            DispatchQueue.main.async { @Sendable in
                MainActor.assumeIsolated { completion(nil, dead) }
            }
            return
        }
        let channel = channel
        queue.async { @Sendable in
            let reply = channel.readLuminance()
            let dead = channel.isDead
            DispatchQueue.main.async { @Sendable in
                MainActor.assumeIsolated { completion(reply, dead) }
            }
        }
    }

    /// Writes luminance `value` (0...the maximum a read reported). Latest wins:
    /// a queued write that a newer one replaces before it starts is dropped,
    /// and its completion runs with the result of the write that replaced it.
    /// True when the monitor's I2C accepted the write, which doesn't prove the
    /// monitor applied it.
    func writeLuminance(_ value: UInt16, completion: @escaping @MainActor (Bool) -> Void) {
        guard !channel.isDead, !isPaused else {
            DispatchQueue.main.async { @Sendable in
                MainActor.assumeIsolated { completion(false) }
            }
            return
        }
        guard channel.enqueueWrite(value, completion) else { return }
        let channel = channel
        queue.async { @Sendable in
            channel.drainWrite()
        }
    }
}

/// One display's service handle and gate, shared by the main actor and the
/// display queue. Nonisolated: its I/O runs on the queue, where main-actor
/// code traps. The service is only used on the queue; the lock guards the rest.
nonisolated final class DDCChannel: @unchecked Sendable {
    static let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "DDC")

    /// MonitorControl's defaults (Arm64DDC.swift, MIT), in microseconds.
    enum Timing {
        static let writeWait: useconds_t = 10_000
        static let writeCycles = 2
        static let readWait: useconds_t = 50_000
        static let attempts = 5
        static let retryWait: useconds_t = 20_000
        /// Slider moves are coalesced to at most one write per this interval.
        static let writeSpacing: TimeInterval = 0.05
    }

    static let replyLength = 11
    /// `kIOReturnUnsupported`, a macro Swift doesn't import.
    static let unsupported = IOReturn(bitPattern: 0xE000_02C7)

    private let service: CFTypeRef
    private let chip: UInt32
    private let displayID: CGDirectDisplayID
    private let lock = NSLock()
    private var paused = false
    private var dead = false
    /// The newest write not yet started, with every completion waiting on it.
    private var pending: (value: UInt16, completions: [@MainActor (Bool) -> Void])?
    private var lastWriteEnd: TimeInterval = 0

    init(service: CFTypeRef, chip: UInt32, displayID: CGDirectDisplayID) {
        self.service = service
        self.chip = chip
        self.displayID = displayID
    }

    /// Looks up the display's service. Blocking registry work: runs on the
    /// display queue.
    static func find(displayID: CGDirectDisplayID) -> DDCChannel? {
        guard IOAVServiceAPI.isAvailable, CGDisplayIsBuiltin(displayID) != 1,
              let location = DDCServiceFinder.ioLocation(of: displayID),
              let found = DDCServiceFinder.service(forFramebufferAt: location) else { return nil }
        log.notice("Display \(displayID, privacy: .public): DDC service found, chip 0x\(String(found.chip, radix: 16), privacy: .public)")
        return DDCChannel(service: found.service, chip: found.chip, displayID: displayID)
    }

    var isDead: Bool { locked { dead } }

    func setPaused(_ on: Bool) {
        locked { paused = on }
    }

    /// Stores the newest value. True when a drain job must be queued for it
    /// (none is waiting yet); false when it joined the one already waiting.
    func enqueueWrite(_ value: UInt16, _ completion: @escaping @MainActor (Bool) -> Void) -> Bool {
        locked {
            if var waiting = pending {
                waiting.value = value
                waiting.completions.append(completion)
                pending = waiting
                return false
            }
            pending = (value, [completion])
            return true
        }
    }

    // MARK: Queue work

    /// Runs on the display queue.
    func readLuminance() -> DDC.Reply? {
        let request = DDC.getPayload(code: DDC.luminance)
        var lastRead: IOReturn = kIOReturnSuccess
        var lastBytes: [UInt8] = []
        for attempt in 1...Timing.attempts {
            if attempt > 1 { usleep(Timing.retryWait) }
            for _ in 0..<Timing.writeCycles {
                usleep(Timing.writeWait)
                guard let result = transfer({ write(request) }) else { return nil }
                if DDC.isPermanentFailure(result) { return markDead("Get VCP write", result) }
            }
            usleep(Timing.readWait)
            var bytes = [UInt8](repeating: 0, count: readSize)
            guard let result = transfer({ read(into: &bytes) }) else { return nil }
            if DDC.isPermanentFailure(result) { return markDead("VCP read", result) }
            lastRead = result
            lastBytes = bytes
            if result == kIOReturnSuccess, let reply = DDC.parseReply(Array(bytes.prefix(Self.replyLength)), code: DDC.luminance) {
                Self.log.notice("Display \(self.displayID, privacy: .public): luminance \(reply.current, privacy: .public) of \(reply.maximum, privacy: .public)")
                return reply
            }
        }
        // EDID bytes (00 FF FF FF FF FF FF 00) here mean the link doesn't carry DDC/CI.
        let head = lastBytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        Self.log.notice("Display \(self.displayID, privacy: .public): no valid VCP reply after \(Timing.attempts, privacy: .public) attempts (last read 0x\(String(UInt32(bitPattern: lastRead), radix: 16), privacy: .public), bytes \(head, privacy: .public))")
        return nil
    }

    /// Runs on the display queue: waits out the write spacing, then sends the
    /// newest pending value and completes everyone waiting on it.
    func drainWrite() {
        let wait = locked { lastWriteEnd + Timing.writeSpacing } - ProcessInfo.processInfo.systemUptime
        if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
        guard let job = locked({ () -> (value: UInt16, completions: [@MainActor (Bool) -> Void])? in
            defer { pending = nil }
            return pending
        }) else { return }
        let ok = sendWrite(job.value)
        locked { lastWriteEnd = ProcessInfo.processInfo.systemUptime }
        let completions = job.completions
        DispatchQueue.main.async { @Sendable in
            MainActor.assumeIsolated {
                for completion in completions { completion(ok) }
            }
        }
    }

    private func sendWrite(_ value: UInt16) -> Bool {
        let request = DDC.setPayload(code: DDC.luminance, value: value)
        var last: IOReturn = kIOReturnSuccess
        for attempt in 1...Timing.attempts {
            if attempt > 1 { usleep(Timing.retryWait) }
            for _ in 0..<Timing.writeCycles {
                usleep(Timing.writeWait)
                guard let result = transfer({ write(request) }) else { return false }
                if DDC.isPermanentFailure(result) {
                    _ = markDead("Set VCP write", result)
                    return false
                }
                last = result
            }
            if last == kIOReturnSuccess { return true }
        }
        Self.log.notice("Display \(self.displayID, privacy: .public): luminance write failed (0x\(String(UInt32(bitPattern: last), radix: 16), privacy: .public))")
        return false
    }

    /// Runs one I2C call unless the link is paused or dead; nil when it was skipped.
    private func transfer(_ call: () -> IOReturn) -> IOReturn? {
        guard locked({ !paused && !dead }) else { return nil }
        return call()
    }

    private func write(_ payload: [UInt8]) -> IOReturn {
        guard let fn = IOAVServiceAPI.writeI2C else { return DDCChannel.unsupported }
        var bytes = payload
        return bytes.withUnsafeMutableBytes { buffer in
            fn(service, chip, UInt32(DDCServiceFinder.dataAddress), buffer.baseAddress!, UInt32(buffer.count))
        }
    }

    private func read(into bytes: inout [UInt8]) -> IOReturn {
        guard let fn = IOAVServiceAPI.readI2C else { return DDCChannel.unsupported }
        let offset = readOffset
        return bytes.withUnsafeMutableBytes { buffer in
            fn(service, chip, offset, buffer.baseAddress!, UInt32(buffer.count))
        }
    }

    /// MonitorControl reads 11 bytes at offset 0; m1ddc's MCDP29xx path (the
    /// M1 Mac mini HDMI converter) reads 12 at the data address.
    private var readOffset: UInt32 { chip == DDCServiceFinder.chipMCDP29XX ? UInt32(DDCServiceFinder.dataAddress) : 0 }
    private var readSize: Int { chip == DDCServiceFinder.chipMCDP29XX ? 12 : Self.replyLength }

    private func markDead(_ what: String, _ result: IOReturn) -> DDC.Reply? {
        locked { dead = true }
        Self.log.error("Display \(self.displayID, privacy: .public): \(what, privacy: .public) rejected permanently (0x\(String(UInt32(bitPattern: result), radix: 16), privacy: .public)); DDC off for this display")
        return nil
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Finds a display's `IOAVService` the way m1ddc does (`sources/ioregistry.m`,
/// MIT): walk the IOService plane in order; the `IOMobileFramebuffer` whose
/// entry ID matches the display's `IODisplayLocation` marks the start, and the
/// next `DCPAVServiceProxy` with `Location == "External"` is its proxy.
nonisolated enum DDCServiceFinder {
    /// Default DDC/CI chip address (7-bit), and the one the MCDP29xx HDMI
    /// converter uses (m1ddc #60).
    static let chipDefault: UInt32 = 0x37
    static let chipMCDP29XX: UInt32 = 0xB7
    /// DDC/CI host (source) address, sent as the I2C data address.
    static let dataAddress: UInt8 = 0x51

    static func ioLocation(of displayID: CGDirectDisplayID) -> String? {
        guard let info = CoreDisplayAPI.infoDictionary?(displayID)?.takeRetainedValue() as? [String: Any] else { return nil }
        return info["IODisplayLocation"] as? String
    }

    static func service(forFramebufferAt path: String) -> (service: CFTypeRef, chip: UInt32)? {
        guard let create = IOAVServiceAPI.createWithService else { return nil }
        let framebuffer = IORegistryEntryCopyFromPath(kIOMainPortDefault, path as CFString)
        guard framebuffer != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(framebuffer) }
        var framebufferID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(framebuffer, &framebufferID) == KERN_SUCCESS else { return nil }

        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var inside = false
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == IO_OBJECT_NULL { break }
            defer { IOObjectRelease(entry) }
            if IOObjectConformsTo(entry, "IOMobileFramebuffer") != 0 {
                var id: UInt64 = 0
                inside = IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS && id == framebufferID
                continue
            }
            guard inside, name(of: entry) == "DCPAVServiceProxy", isExternal(entry) else { continue }
            // Create rule: +1, balanced by ARC once taken.
            guard let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            return (service, isMCDP29XX(entry) ? chipMCDP29XX : chipDefault)
        }
        return nil
    }

    private static func name(of entry: io_registry_entry_t) -> String? {
        var buffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// Only external proxies: never talk to the built-in panel's.
    private static func isExternal(_ proxy: io_registry_entry_t) -> Bool {
        let location = IORegistryEntrySearchCFProperty(proxy, kIOServicePlane, "Location" as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively))
        return location as? String == "External"
    }

    private static func isMCDP29XX(_ proxy: io_registry_entry_t) -> Bool {
        var parent: io_registry_entry_t = IO_OBJECT_NULL
        guard IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(parent) }
        let provider = IORegistryEntryCreateCFProperty(parent, "EPICProviderClass" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return provider as? String == "AppleDCPMCDP29XX"
    }
}

/// One serial queue per display ID, shared by every link made for it, so a
/// link rebuilt after a reconfiguration never overlaps the old one's I/O.
private nonisolated enum DDCQueues {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [CGDirectDisplayID: DispatchQueue] = [:]

    static func queue(for displayID: CGDirectDisplayID) -> DispatchQueue {
        lock.lock()
        defer { lock.unlock() }
        if let queue = queues[displayID] { return queue }
        let queue = DispatchQueue(label: "io.github.mrxgamer999.Lidless.ddc.\(displayID)", qos: .userInitiated)
        queues[displayID] = queue
        return queue
    }
}
