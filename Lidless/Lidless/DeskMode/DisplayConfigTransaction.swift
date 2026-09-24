import ColorSync
import CoreGraphics
import Foundation
import os

/// SkyLight's enable bit inside a CoreGraphics configuration transaction.
///
/// `nonisolated` and synchronous: it may block for up to about 30 s inside
/// `CGCompleteDisplayConfiguration`, so call it off the main thread. Also used
/// by the sidecar watchdog process, which has no AppKit.
nonisolated enum DisplayConfigTransaction {
    enum Scope: Sendable {
        /// Reverts when this process exits (if WindowServer honours it). Used to disable.
        case appOnly
        /// Survives this process. Used to enable, so the baseline says "on".
        case session
    }

    /// Apple's EDID vendor number, which the built-in panel reports.
    static let appleVendor: UInt32 = 0x610

    /// Far above what a Mac can drive; only guards against a bogus count.
    private static let maxDisplays: UInt32 = 32
    /// Marks a thread that is inside one of our transactions. Our own
    /// `CGCompleteDisplayConfiguration` runs the reconfiguration callbacks
    /// synchronously on the calling thread, so this is how a callback that tries
    /// to start another transaction gets caught.
    private static let reentryKey = "io.github.mrxgamer999.Lidless.displayTransaction"
    private static let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "DeskMode")

    /// Both SkyLight calls resolved.
    static var isAvailable: Bool {
        SkyLightAPI.configureDisplayEnabled != nil && SkyLightAPI.getDisplayList != nil
    }

    /// Returns true when CoreGraphics reported success. Not proof: verify with `isOnline`.
    static func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool, scope: Scope) -> Bool {
        guard let configure = SkyLightAPI.configureDisplayEnabled else {
            log.error("Display \(id, privacy: .public): SkyLight's enable call is missing")
            return false
        }
        return guarded("setEnabled") {
            var config: CGDisplayConfigRef?
            let begun = CGBeginDisplayConfiguration(&config)
            guard begun == .success, let config else {
                log.error("Display \(id, privacy: .public): begin configuration failed (\(begun.rawValue, privacy: .public))")
                return false
            }
            let configured = configure(config, id, enabled)
            guard configured == .success else {
                // Also what an ID already in the target state gets: the transaction is void.
                CGCancelDisplayConfiguration(config)
                log.error("Display \(id, privacy: .public): enabled=\(enabled, privacy: .public) rejected (\(configured.rawValue, privacy: .public))")
                return false
            }
            let started = ProcessInfo.processInfo.systemUptime
            // Never `.permanently`: nothing Desk Mode does may outlive the login session.
            let completed = CGCompleteDisplayConfiguration(config, scope == .appOnly ? .forAppOnly : .forSession)
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            log.notice("Display \(id, privacy: .public): enabled=\(enabled, privacy: .public) \(String(describing: scope), privacy: .public) completed (\(completed.rawValue, privacy: .public)) in \(elapsed, format: .fixed(precision: 2), privacy: .public) s")
            return completed == .success
        }
    }

    /// The built-in's current ID: the listed entry whose UUID matches (always
    /// preferred), else the one that is built in with Apple's vendor (0x610),
    /// else `fallbackID`. Never one of SkyLight's phantom IDs (`isPhantom`).
    ///
    /// A disabled panel is missing from the online list but still in SkyLight's,
    /// so both lists are searched. `fallbackID` is the panel's ID from when it was
    /// last online; it is dropped only if it now reads as a phantom.
    static func findBuiltIn(uuid: String?, fallbackID: CGDirectDisplayID?) -> CGDirectDisplayID? {
        var known = onlineIDs()
        for id in skyLightIDs() where !known.contains(id) {
            known.append(id)
        }
        let candidates = known.filter { !isPhantom($0) }
        if let wanted = DisplayReadingHelpers.panelUUID(uuid),
           let match = candidates.first(where: { displayUUID($0)?.caseInsensitiveCompare(wanted) == .orderedSame }) {
            return match
        }
        // `boolean_t` getters return -1 for IDs they don't know: only 1 is true.
        if let match = candidates.first(where: { CGDisplayIsBuiltin($0) == 1 && CGDisplayVendorNumber($0) == appleVendor }) {
            return match
        }
        guard let fallbackID, !isPhantom(fallbackID) else {
            return nil
        }
        return fallbackID
    }

    /// In `CGGetOnlineDisplayList`. List membership, never `CGDisplayIsOnline`,
    /// which returns -1 (truthy) for absent IDs on macOS 27.
    static func isOnline(_ id: CGDirectDisplayID) -> Bool {
        onlineIDs().contains(id)
    }

    static func onlineIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        let capacity = min(count, maxDisplays)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        guard CGGetOnlineDisplayList(capacity, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(min(count, capacity))))
    }

    /// `CGRestorePermanentDisplayConfiguration()`: the last step of a restore ladder.
    static func restorePermanentConfiguration() {
        _ = guarded("restorePermanentConfiguration") {
            log.notice("Restoring the permanent display configuration")
            CGRestorePermanentDisplayConfiguration()
            return true
        }
    }

    // MARK: - Helpers

    /// SkyLight's list, disabled displays and phantoms included. Empty when the
    /// call is missing or fails.
    private static func skyLightIDs() -> [CGDirectDisplayID] {
        guard let getList = SkyLightAPI.getDisplayList else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        let error = ids.withUnsafeMutableBufferPointer { getList(maxDisplays, $0.baseAddress, &count) }
        guard error == .success else {
            log.error("SkyLight display list failed (\(error.rawValue, privacy: .public))")
            return []
        }
        return Array(ids.prefix(Int(min(count, maxDisplays))))
    }

    /// SkyLight's placeholder IDs: vendor 0 and model 0 and at most 1 px wide.
    /// All three, never any one: a disabled built-in has no current mode and may
    /// read 0 px wide, but keeps Apple's vendor (0x610) and `IsBuiltin`, so a
    /// width test alone would throw the real panel away.
    private static func isPhantom(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == 0 && CGDisplayModelNumber(id) == 0 && CGDisplayPixelsWide(id) <= 1
    }

    private static func displayUUID(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return DisplayReadingHelpers.panelUUID(CFUUIDCreateString(nil, uuid) as String)
    }

    /// Runs `body` unless this thread is already inside a transaction, which is
    /// how a reconfiguration callback re-entering us would look.
    private static func guarded(_ what: String, _ body: () -> Bool) -> Bool {
        let threadState = Thread.current.threadDictionary
        guard threadState[reentryKey] == nil else {
            log.fault("\(what, privacy: .public) refused: already inside a display transaction on this thread")
            return false
        }
        threadState[reentryKey] = true
        defer { threadState.removeObject(forKey: reentryKey) }
        return body()
    }
}
