import Foundation

/// A small JSON file written before Desk Mode turns the built-in off and removed
/// once it is back. Found at launch, it means the last run died with the panel off.
public struct CrashMarker: Sendable, Equatable, Codable {
    public enum Stage: String, Sendable, Equatable, Codable {
        /// Written just before the disable call.
        case engaging
        /// The disable was verified.
        case active
    }

    public var stage: Stage
    public var method: DeskModeMethod
    public var builtInDisplayID: UInt32
    public var builtInUUID: String?
    public var pid: Int32
    /// `kern.bootsessionuuid`: a different value means the Mac restarted since.
    public var bootSessionUUID: String?
    /// Wall-clock time the marker was written.
    public var writtenAt: Date

    public init(stage: Stage, method: DeskModeMethod, builtInDisplayID: UInt32, builtInUUID: String?, pid: Int32, bootSessionUUID: String?, writtenAt: Date) {
        self.stage = stage
        self.method = method
        self.builtInDisplayID = builtInDisplayID
        self.builtInUUID = builtInUUID
        self.pid = pid
        self.bootSessionUUID = bootSessionUUID
        self.writtenAt = writtenAt
    }

    /// Stable JSON (sorted keys, ISO 8601 dates). ISO 8601 keeps whole seconds,
    /// which is all a launch-time diagnostic needs. A nil UUID is left out.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// nil for unreadable or foreign data; a damaged marker is treated as absent.
    public static func decode(_ data: Data) -> CrashMarker? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CrashMarker.self, from: data)
    }
}

/// What to do at launch about a marker left by an earlier run.
public enum LaunchRecovery: Sendable, Equatable {
    /// No marker.
    case nothing
    /// Same boot: enable this panel before any UI, then delete the marker and
    /// tell the user once. Never re-applies Desk Mode.
    case restore(displayID: UInt32, uuid: String?, method: DeskModeMethod, notify: Bool)
    /// The Mac restarted since (the panel is back by itself), or the marker is
    /// damaged: just delete it.
    case discard

    /// - Parameters:
    ///   - marker: The decoded marker, nil when absent. Pass `markerFileExists`
    ///     so a damaged file is discarded rather than ignored.
    ///   - currentBootSession: This boot's `kern.bootsessionuuid`, nil when unreadable
    ///     (then a marker counts as the same boot, the safe choice).
    ///   - otherInstanceRunning: The marker's PID is another live Lidless. Leave it alone.
    ///
    /// Both stages restore: after `.engaging` the disable may or may not have
    /// landed, and an enable is harmless either way. A black-out marker still
    /// restores, so the controller can confirm and the user hears Desk Mode
    /// ended; its window died with the old process.
    public static func decide(marker: CrashMarker?, markerFileExists: Bool, currentBootSession: String?, otherInstanceRunning: Bool) -> LaunchRecovery {
        // A decoded marker came from a file, whatever the flag says.
        guard markerFileExists || marker != nil else { return .nothing }
        guard let marker else { return .discard }
        // The owner is alive and still guarding its own panel.
        if otherInstanceRunning { return .nothing }
        if let written = marker.bootSessionUUID, let current = currentBootSession, written != current {
            return .discard
        }
        return .restore(displayID: marker.builtInDisplayID, uuid: marker.builtInUUID, method: marker.method, notify: true)
    }
}
