import CoreGraphics
import Foundation
import LidlessCore
import os

/// One display's DDC/CI link, as the controller uses it. `DDCLink` is the live one.
protocol ExternalDDCLink: AnyObject {
    /// `permanentFailure`: the link is dead, stop trying.
    func readLuminance(completion: @escaping @MainActor (DDC.Reply?, _ permanentFailure: Bool) -> Void)
    /// Latest wins; the completion always runs, on the main actor.
    func writeLuminance(_ value: UInt16, completion: @escaping @MainActor (Bool) -> Void)
    var isPaused: Bool { get set }
    var isDead: Bool { get }
}

extension DDCLink: ExternalDDCLink {}

/// Brightness of external Apple displays, which macOS dims itself.
protocol ExternalNativeBrightness: AnyObject {
    /// Reads the display's level 0...1 off the main thread; the completion runs
    /// on the main actor, with nil when DisplayServices can't read it.
    func readLevel(of display: CGDirectDisplayID, completion: @escaping @MainActor (Double?) -> Void)
    /// Writes an absolute level 0...1, latest value wins.
    func setLevel(_ level: Double, of display: CGDirectDisplayID)
    /// While true, writes are held (the latest per display) and sent when it
    /// turns false again.
    var isPaused: Bool { get set }
}

/// Brightness for every external display, by the best method each one allows:
/// native (DisplayServices) for Apple displays, DDC/CI when a strict read of
/// VCP 0x10 succeeds, and otherwise a black shade (`ShadeWindow`). Virtual
/// displays (Sidecar, AirPlay, DisplayLink) always get a shade. The built-in
/// is never touched.
///
/// A DDC probe that fails without a permanent error (no valid reply, no link
/// found) is tried again after 5 s and 30 s before the display settles on a
/// shade; a permanent failure (the coprocessor rejects the link) goes to a
/// shade at once.
///
/// Levels the user sets are saved per display UUID under "externalBrightness",
/// with the method they were set for. A shade only starts at a level saved for
/// a shade (so a DDC level never dims a display twice); otherwise it starts at
/// full brightness. Native and DDC displays keep their own level, so the
/// controller reads it back from them instead.
///
/// `pause()` stops DDC and native writes and drops every DDC handle (they go
/// stale when displays are re-enumerated); `resume(after:)` makes new ones,
/// finishes interrupted probes, writes the latest wanted level and re-fits
/// the shades. Shades stay up while paused. No shade is shown while any
/// display mirrors another: the mirror set may include the built-in.
///
/// After `removeAllShades()` (the panic key) every shade made later in the
/// session starts at full brightness until the user sets that display's level.
final class ExternalBrightnessController: ExternalBrightnessControl {
    /// UserDefaults key: `[displayUUID: ["level": 0...1, "method": "native" | "ddc" | "shade"]]`.
    /// "method" is missing for a level set while the display was being probed.
    /// Builds before methods were saved stored `[displayUUID: level]`; those
    /// values are still read, as levels of unknown method.
    static let defaultsKey = "externalBrightness"

    /// Waits before the second and third DDC probe of a display.
    static let probeRetryDelays: [TimeInterval] = [5, 30]

    /// What touches the system, injectable for tests.
    struct Services {
        var native: ExternalNativeBrightness
        /// Makes a DDC link for a physical external off the main thread; the
        /// completion runs on the main actor, with nil when none can be found.
        var makeDDC: (CGDirectDisplayID, @escaping @MainActor (ExternalDDCLink?) -> Void) -> Void
        var makeShade: (CGDirectDisplayID) -> ExternalShade
        /// Runs `work` on the main actor after `delay` seconds.
        var after: (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

        static var live: Services {
            Services(
                native: DisplayServicesExternalBrightness(),
                makeDDC: { displayID, completion in
                    DDCLink.make(displayID: displayID) { completion($0) }
                },
                makeShade: { ShadeWindow(displayID: $0) },
                after: { delay, work in
                    DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { @Sendable in
                        MainActor.assumeIsolated { work() }
                    }
                }
            )
        }
    }

    private static let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "ExternalBrightness")

    var onChange: (@MainActor () -> Void)?
    /// DDC and native writes wait for `resume(after:)`.
    private(set) var isPaused = false

    private let services: Services
    private let defaults: UserDefaults
    private var entries: [String: Entry] = [:]
    /// Levels the user set, by display UUID.
    private var saved: [String: SavedLevel]
    /// Bumped by every pause and resume, so only the latest resume fires.
    private var resumeGeneration = 0
    private var isMirroring = false
    /// Set by the panic key: shades made after it start at full brightness,
    /// except on displays in `levelSetSincePanic`.
    private var shadesStartUndimmed = false
    private var levelSetSincePanic: Set<String> = []

    init(services: Services = .live, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        saved = SavedLevel.load(from: defaults.dictionary(forKey: Self.defaultsKey) ?? [:])
    }

    // MARK: ExternalBrightnessControl

    func update(displays: [DisplayDescriptor]) {
        let externals = displays.filter { !$0.isBuiltIn }
        let current = Dictionary(externals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        isMirroring = displays.contains { $0.role == .mirrored }
        var changed = false
        // A display that came back under a new ID is a new attach: probe it again.
        for (uuid, entry) in entries where current[uuid]?.displayID != entry.displayID {
            drop(entry)
            entries[uuid] = nil
            changed = true
        }
        for display in externals where entries[display.id] == nil {
            let entry = Entry(uuid: display.id, displayID: display.displayID, method: Self.initialMethod(of: display))
            entries[display.id] = entry
            start(entry)
            changed = true
        }
        for entry in entries.values {
            placeShade(entry)
        }
        if changed { onChange?() }
    }

    func method(for displayUUID: String) -> ExternalBrightnessMethod {
        entries[displayUUID]?.method ?? .probing
    }

    func level(for displayUUID: String) -> Double? {
        entries[displayUUID]?.level
    }

    func setLevel(_ level: Double, for displayUUID: String) {
        guard !level.isNaN, let entry = entries[displayUUID] else { return }
        let level = min(max(level, 0), 1)
        entry.level = level
        levelSetSincePanic.insert(displayUUID)
        save(level, method: SavedLevel.Method(entry.method), for: displayUUID)
        switch entry.method {
        case .probing:
            entry.levelWhileProbing = level
        case .native:
            entry.pendingNative = level
            flushNative(entry)
        case .ddc(let maximum):
            entry.wantedDDC = Self.ddcValue(level, maximum: maximum)
            entry.pendingDDC = true
            runDDC(entry)
        case .shade:
            placeShade(entry)
        }
    }

    func pause() {
        isPaused = true
        resumeGeneration += 1
        services.native.isPaused = true
        for entry in entries.values {
            dropLink(of: entry)
            if entry.method == .probing {
                // Its answer, if one still comes, belongs to the old handle; a
                // back-off wait ends too: the resume probes again.
                entry.probeGeneration += 1
                entry.needsProbe = true
            }
        }
    }

    func resume(after delay: TimeInterval) {
        resumeGeneration += 1
        let generation = resumeGeneration
        services.after(delay) { [weak self] in
            guard let self, self.resumeGeneration == generation else { return }
            self.resumeNow()
        }
    }

    func removeAllShades() {
        shadesStartUndimmed = true
        levelSetSincePanic = []
        var changed = false
        for entry in entries.values {
            // A probe still running must not end in a dimmed shade.
            entry.levelWhileProbing = nil
            guard entry.method == .shade else { continue }
            removeShade(of: entry)
            // Shown as full brightness until the user moves the slider again. The
            // saved level stays, so the next launch dims the display again.
            if entry.level != 1 {
                entry.level = 1
                changed = true
            }
        }
        if changed { onChange?() }
    }

    // MARK: Starting

    private static func initialMethod(of display: DisplayDescriptor) -> ExternalBrightnessMethod {
        if display.isVirtual { return .shade }
        switch display.brightnessControl {
        case .native: return .native
        case .ddc: return .probing
        case .software, .none: return .shade
        }
    }

    private func start(_ entry: Entry) {
        switch entry.method {
        case .native:
            readNativeLevel(entry)
        case .shade:
            // Never probed, so a level saved before methods were saved was a shade's.
            entry.level = shadeStartLevel(entry, acceptsUnknownMethod: true)
        case .probing:
            entry.needsProbe = true
            runDDC(entry)
        case .ddc:
            break
        }
    }

    /// The native level comes from DisplayServices, read off the main thread.
    /// Until it arrives the level is unknown; a level the user sets first wins.
    private func readNativeLevel(_ entry: Entry) {
        services.native.readLevel(of: entry.displayID) { [weak self, weak entry] level in
            guard let self, let entry, self.entries[entry.uuid] === entry,
                  entry.method == .native, entry.level == nil else { return }
            entry.level = level ?? self.savedLevel(entry.uuid, for: .native, acceptsUnknownMethod: true) ?? 1
            self.onChange?()
        }
    }

    // MARK: DDC

    /// Moves the display's DDC work along once nothing blocks it: makes a link
    /// if there is none, then runs a waiting probe, or else a waiting write.
    private func runDDC(_ entry: Entry) {
        guard !isPaused, entry.needsProbe || entry.pendingDDC else { return }
        guard let link = entry.link else {
            requestLink(for: entry)
            return
        }
        if link.isDead {
            Self.log.notice("Display \(entry.displayID, privacy: .public): DDC link is dead, using a shade")
            becomeShade(entry)
        } else if entry.needsProbe {
            read(entry, with: link)
        } else {
            write(entry, with: link)
        }
    }

    /// Looks for the display's DDC service (off the main thread); the link
    /// answers only while no pause, drop or new attach came in between.
    private func requestLink(for entry: Entry) {
        guard !entry.isMakingLink else { return }
        entry.isMakingLink = true
        let generation = entry.linkGeneration
        services.makeDDC(entry.displayID) { [weak self, weak entry] link in
            guard let self, let entry, self.entries[entry.uuid] === entry,
                  entry.linkGeneration == generation else {
                // Found before a reconfiguration: the handle may be stale.
                link?.isPaused = true
                return
            }
            entry.isMakingLink = false
            guard let link else {
                self.noLink(entry)
                return
            }
            entry.link = link
            self.runDDC(entry)
        }
    }

    /// No DDC service was found. That may pass (the registry can lag behind an
    /// attach), so it counts as a failed probe, not a dead link.
    private func noLink(_ entry: Entry) {
        switch entry.method {
        case .probing:
            Self.log.notice("Display \(entry.displayID, privacy: .public): no DDC link")
            entry.needsProbe = false
            probeFailed(entry, permanent: false)
        case .ddc:
            // It had DDC before this reconfiguration: find out again, keeping
            // a level that wasn't sent yet for when DDC comes back.
            Self.log.notice("Display \(entry.displayID, privacy: .public): DDC link gone, probing again")
            entry.levelAfterReprobe = entry.pendingDDC ? entry.level : nil
            entry.method = .probing
            entry.wantedDDC = nil
            entry.pendingDDC = false
            entry.needsProbe = false
            entry.probeFailures = 0
            probeFailed(entry, permanent: false)
            onChange?()
        case .native, .shade:
            break
        }
    }

    /// Reads VCP 0x10: a valid reply makes the display DDC.
    private func read(_ entry: Entry, with link: ExternalDDCLink) {
        entry.needsProbe = false
        entry.probeGeneration += 1
        let generation = entry.probeGeneration
        link.readLuminance { [weak self, weak entry] reply, permanentFailure in
            guard let self, let entry, self.entries[entry.uuid] === entry,
                  entry.probeGeneration == generation else { return }
            self.probeFinished(entry, reply: reply, permanentFailure: permanentFailure)
        }
    }

    private func probeFinished(_ entry: Entry, reply: DDC.Reply?, permanentFailure: Bool) {
        guard let reply, reply.maximum > 0 else {
            probeFailed(entry, permanent: permanentFailure)
            return
        }
        Self.log.notice("Display \(entry.displayID, privacy: .public): DDC luminance \(reply.current, privacy: .public)/\(reply.maximum, privacy: .public)")
        entry.method = .ddc(maximum: reply.maximum)
        entry.probeFailures = 0
        if let wanted = entry.levelWhileProbing ?? entry.levelAfterReprobe {
            // The user moved the slider during the probe: their level wins.
            entry.levelWhileProbing = nil
            entry.levelAfterReprobe = nil
            entry.level = wanted
            save(wanted, method: .ddc, for: entry.uuid)
            entry.wantedDDC = Self.ddcValue(wanted, maximum: reply.maximum)
            entry.pendingDDC = true
            runDDC(entry)
        } else {
            entry.level = min(Double(reply.current) / Double(reply.maximum), 1)
        }
        onChange?()
    }

    /// A permanent failure, or the last of the retries, settles on a shade;
    /// any other failure tries again after the next back-off delay.
    private func probeFailed(_ entry: Entry, permanent: Bool) {
        // A fresh handle for the next try.
        dropLink(of: entry)
        let tries = entry.probeFailures
        guard !permanent, tries < Self.probeRetryDelays.count else {
            Self.log.notice("Display \(entry.displayID, privacy: .public): DDC probe failed (permanent: \(permanent, privacy: .public), tries: \(tries + 1, privacy: .public)), using a shade")
            becomeShade(entry)
            return
        }
        entry.probeFailures = tries + 1
        let delay = Self.probeRetryDelays[tries]
        Self.log.notice("Display \(entry.displayID, privacy: .public): DDC probe failed, trying again in \(delay, privacy: .public) s")
        let generation = entry.probeGeneration
        services.after(delay) { [weak self, weak entry] in
            guard let self, let entry, self.entries[entry.uuid] === entry,
                  entry.method == .probing, entry.probeGeneration == generation else { return }
            entry.needsProbe = true
            self.runDDC(entry)
        }
    }

    /// DDC is out for this display (no valid reply after the retries, or a
    /// dead link). The shade starts at full brightness unless the user picked
    /// a level during the probe or saved one for a shade before.
    private func becomeShade(_ entry: Entry) {
        dropLink(of: entry)
        entry.probeGeneration += 1
        entry.method = .shade
        if let wanted = entry.levelWhileProbing {
            entry.level = wanted
            save(wanted, method: .shade, for: entry.uuid)
        } else {
            entry.level = shadeStartLevel(entry, acceptsUnknownMethod: false)
        }
        entry.levelWhileProbing = nil
        entry.levelAfterReprobe = nil
        entry.needsProbe = false
        entry.probeFailures = 0
        entry.wantedDDC = nil
        entry.pendingDDC = false
        placeShade(entry)
        onChange?()
    }

    private static func ddcValue(_ level: Double, maximum: UInt16) -> UInt16 {
        UInt16((level * Double(maximum)).rounded())
    }

    /// Sends the latest wanted DDC value; the link coalesces and spaces writes.
    private func write(_ entry: Entry, with link: ExternalDDCLink) {
        entry.pendingDDC = false
        guard case .ddc = entry.method, let value = entry.wantedDDC else { return }
        link.writeLuminance(value) { [weak self, weak entry] accepted in
            guard let self, let entry, self.entries[entry.uuid] === entry else { return }
            self.writeFinished(entry, link: link, accepted: accepted)
        }
    }

    /// A dead link hands over to a shade. Any other failure retries once after
    /// the write spacing; if that fails too, the level waits for the next write
    /// or resume.
    private func writeFinished(_ entry: Entry, link: ExternalDDCLink, accepted: Bool) {
        guard case .ddc = entry.method else { return }
        if link.isDead {
            Self.log.notice("Display \(entry.displayID, privacy: .public): DDC write failed for good, using a shade")
            becomeShade(entry)
            return
        }
        if accepted {
            if entry.link === link { entry.writeFailures = 0 }
            return
        }
        // Held until DDC can run again.
        entry.pendingDDC = true
        guard !isPaused, entry.link === link else { return }
        entry.writeFailures += 1
        guard entry.writeFailures == 1 else {
            Self.log.notice("Display \(entry.displayID, privacy: .public): DDC write failed again; the level waits for the next write")
            return
        }
        let generation = entry.linkGeneration
        services.after(DDCChannel.Timing.writeSpacing) { [weak self, weak entry] in
            guard let self, let entry, self.entries[entry.uuid] === entry,
                  entry.linkGeneration == generation else { return }
            self.runDDC(entry)
        }
    }

    private func flushNative(_ entry: Entry) {
        guard !isPaused, case .native = entry.method, let level = entry.pendingNative else { return }
        entry.pendingNative = nil
        services.native.setLevel(level, of: entry.displayID)
    }

    /// Lets go of the display's link, and of one still being made.
    private func dropLink(of entry: Entry) {
        entry.link?.isPaused = true
        entry.link = nil
        entry.isMakingLink = false
        entry.linkGeneration += 1
        entry.writeFailures = 0
    }

    // MARK: Pause

    private func resumeNow() {
        isPaused = false
        services.native.isPaused = false
        for entry in entries.values {
            runDDC(entry)
            flushNative(entry)
            // The screen may have moved or changed size.
            if let shade = entry.shade, shade.isShown {
                shade.refit()
            }
            placeShade(entry)
        }
    }

    // MARK: Shades

    /// Shows, updates or removes the display's shade to match its method and level.
    private func placeShade(_ entry: Entry) {
        guard entry.method == .shade, !isMirroring, let level = entry.level,
              ShadeMath.alpha(forLevel: level) > 0 else {
            removeShade(of: entry)
            return
        }
        if isPaused {
            // Kept, but a new window waits for the displays to settle.
            if let shade = entry.shade, shade.isShown {
                shade.show(level: level)
            }
            return
        }
        let shade = entry.shade ?? services.makeShade(entry.displayID)
        entry.shade = shade
        if !shade.show(level: level) {
            Self.log.notice("Display \(entry.displayID, privacy: .public): no screen for the shade yet")
        }
    }

    private func removeShade(of entry: Entry) {
        entry.shade?.remove()
        entry.shade = nil
    }

    private func drop(_ entry: Entry) {
        removeShade(of: entry)
        dropLink(of: entry)
        entry.probeGeneration += 1
    }

    /// Where a new shade starts: full brightness after the panic key (until the
    /// user sets this display's level), else a level saved for a shade.
    private func shadeStartLevel(_ entry: Entry, acceptsUnknownMethod: Bool) -> Double {
        if shadesStartUndimmed && !levelSetSincePanic.contains(entry.uuid) { return 1 }
        return savedLevel(entry.uuid, for: .shade, acceptsUnknownMethod: acceptsUnknownMethod) ?? 1
    }

    // MARK: Saved levels

    private func savedLevel(_ uuid: String, for method: SavedLevel.Method, acceptsUnknownMethod: Bool) -> Double? {
        guard let entry = saved[uuid] else { return nil }
        if entry.method == method || (entry.method == nil && acceptsUnknownMethod) {
            return entry.level
        }
        return nil
    }

    private func save(_ level: Double, method: SavedLevel.Method?, for uuid: String) {
        let value = SavedLevel(level: level, method: method)
        guard saved[uuid] != value else { return }
        saved[uuid] = value
        // Rewrites every entry, so levels from older builds move to the new format.
        defaults.set(saved.mapValues { $0.propertyList }, forKey: Self.defaultsKey)
    }

    // MARK: Entry

    /// One connected external display.
    private final class Entry {
        let uuid: String
        let displayID: CGDirectDisplayID
        var method: ExternalBrightnessMethod
        var level: Double?
        var link: ExternalDDCLink?
        /// A link is being looked for.
        var isMakingLink = false
        /// Bumped by every drop, so a link found for an older handle is ignored.
        var linkGeneration = 0
        var shade: ExternalShade?
        /// Bumped to ignore a read that answers for an older handle or attach.
        var probeGeneration = 0
        /// A probe waits for a link or the end of a pause.
        var needsProbe = false
        /// Probes that failed without a permanent error, this attach.
        var probeFailures = 0
        /// The slider moved while the probe was running.
        var levelWhileProbing: Double?
        /// A DDC level not yet sent when the link went away; sent if DDC comes back.
        var levelAfterReprobe: Double?
        /// The newest DDC value asked for, and whether it still has to be sent.
        var wantedDDC: UInt16?
        var pendingDDC = false
        /// Failed writes in a row on the current link.
        var writeFailures = 0
        var pendingNative: Double?

        init(uuid: String, displayID: CGDirectDisplayID, method: ExternalBrightnessMethod) {
            self.uuid = uuid
            self.displayID = displayID
            self.method = method
        }
    }
}

/// A level the user set, and the method it was set for.
private nonisolated struct SavedLevel: Equatable {
    enum Method: String {
        case native, ddc, shade

        /// nil while probing: the level's method isn't known yet.
        init?(_ method: ExternalBrightnessMethod) {
            switch method {
            case .native: self = .native
            case .ddc: self = .ddc
            case .shade: self = .shade
            case .probing: return nil
            }
        }
    }

    var level: Double
    /// nil: set while probing, or saved by a build that didn't save methods.
    var method: Method?

    var propertyList: [String: Any] {
        guard let method else { return ["level": level] }
        return ["level": level, "method": method.rawValue]
    }

    /// Reads both formats: `["level": x, "method": m]` and the older bare level.
    /// Levels are clamped to 0...1; anything else is skipped.
    static func load(from dictionary: [String: Any]) -> [String: SavedLevel] {
        var result: [String: SavedLevel] = [:]
        for (uuid, value) in dictionary {
            let level: Double?
            var method: Method?
            if let fields = value as? [String: Any] {
                level = fields["level"] as? Double
                method = (fields["method"] as? String).flatMap(Method.init(rawValue:))
            } else {
                level = value as? Double
            }
            guard let level, level.isFinite else { continue }
            result[uuid] = SavedLevel(level: min(max(level, 0), 1), method: method)
        }
        return result
    }
}

/// External Apple displays through DisplayServices.
final class DisplayServicesExternalBrightness: ExternalNativeBrightness {
    private let queue = NativeBrightnessQueue()

    var isPaused = false {
        didSet { queue.setPaused(isPaused) }
    }

    func readLevel(of display: CGDirectDisplayID, completion: @escaping @MainActor (Double?) -> Void) {
        queue.read(display, completion: completion)
    }

    func setLevel(_ level: Double, of display: CGDirectDisplayID) {
        queue.submit(Float(min(max(level, 0), 1)), to: display)
    }
}

/// Native reads and writes off the main thread, latest write wins: an external
/// Apple display is set over USB or Thunderbolt, which can take a while.
/// While paused, writes are held and the latest per display goes out on
/// resume; a write already running when the pause comes can't be stopped.
nonisolated final class NativeBrightnessQueue: @unchecked Sendable {
    /// The DisplayServices calls, run on the queue. Injectable for tests.
    nonisolated struct Calls: Sendable {
        var read: @Sendable (CGDirectDisplayID) -> Double?
        var write: @Sendable (CGDirectDisplayID, Float) -> Void

        static let live = Calls(
            read: { display in
                guard let get = DisplayServicesAPI.getBrightness else { return nil }
                var value: Float = 0
                guard get(display, &value) == 0, value.isFinite else { return nil }
                return Double(min(max(value, 0), 1))
            },
            write: { display, level in
                guard CGDisplayIsOnline(display) != 0,
                      DisplayServicesAPI.canChangeBrightness?(display) == true else { return }
                _ = DisplayServicesAPI.setBrightness?(display, level)
            }
        )
    }

    private let calls: Calls
    private let queue = DispatchQueue(label: "io.github.mrxgamer999.Lidless.external-native-brightness", qos: .userInitiated)
    private let lock = NSLock()
    /// Levels waiting to be written; a display is listed while a write job is
    /// queued for it or its write is held by a pause.
    private var pending: [CGDirectDisplayID: Float] = [:]
    private var paused = false

    init(calls: Calls = .live) {
        self.calls = calls
    }

    func read(_ display: CGDirectDisplayID, completion: @escaping @MainActor (Double?) -> Void) {
        let calls = calls
        queue.async { @Sendable in
            let level = calls.read(display)
            DispatchQueue.main.async { @Sendable in
                MainActor.assumeIsolated { completion(level) }
            }
        }
    }

    func submit(_ level: Float, to display: CGDirectDisplayID) {
        let needsJob = locked { () -> Bool in
            let isListed = pending[display] != nil
            pending[display] = level
            return !isListed && !paused
        }
        if needsJob { enqueueWrite(display) }
    }

    /// Pausing holds writes; resuming sends the latest held level of each display.
    func setPaused(_ on: Bool) {
        let held = locked { () -> [CGDirectDisplayID] in
            paused = on
            return on ? [] : Array(pending.keys)
        }
        held.forEach(enqueueWrite)
    }

    /// Blocks until work queued so far has run. For tests.
    func waitUntilIdle() {
        queue.sync {}
    }

    private func enqueueWrite(_ display: CGDirectDisplayID) {
        queue.async { @Sendable [self] in
            write(display)
        }
    }

    private func write(_ display: CGDirectDisplayID) {
        // The pause is checked under the lock: a held level stays for the resume.
        guard let level = locked({ paused ? nil : pending.removeValue(forKey: display) }) else { return }
        calls.write(display, level)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
