import Foundation
import LidlessCore
import os

/// The crash marker as a JSON file in Application Support (L8). Written before
/// the built-in goes off, removed once it is back; found at launch, it means
/// the last run died with the panel off.
///
/// The write is atomic (a temporary file renamed over the old one), so a crash
/// mid-write leaves the previous marker or none, never half a file. No fsync:
/// a process crash keeps the page cache, and a kernel panic reboots the Mac,
/// which brings the panel back and makes the marker stale anyway.
final class FileCrashMarkerStore: CrashMarkerStore {
    static let fileName = "desk-mode-marker.json"

    let fileURL: URL
    private let directory: URL
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "CrashMarker")

    /// Tests pass their own directory.
    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        fileURL = self.directory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// ~/Library/Application Support/io.github.mrxgamer999.Lidless
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("io.github.mrxgamer999.Lidless", isDirectory: true)
    }

    func write(_ marker: CrashMarker) {
        do {
            // Only the user needs to read it; the attributes apply to directories this creates.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try marker.encoded().write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            log.error("Couldn't write the Desk Mode marker: \(error.localizedDescription, privacy: .public)")
        }
    }

    func read() -> (marker: CrashMarker?, fileExists: Bool) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return (nil, false) }
        do {
            let data = try Data(contentsOf: fileURL)
            return (CrashMarker.decode(data), true)
        } catch {
            // It exists but can't be read: damaged, so recovery discards it.
            log.error("Couldn't read the Desk Mode marker: \(error.localizedDescription, privacy: .public)")
            return (nil, true)
        }
    }

    func clear() {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already gone.
        } catch {
            log.error("Couldn't remove the Desk Mode marker: \(error.localizedDescription, privacy: .public)")
        }
    }

    var currentBootSession: String? { Self.bootSessionUUID() }

    /// `kern.bootsessionuuid`: new on every boot. nil when unreadable.
    nonisolated static func bootSessionUUID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = buffer.withUnsafeMutableBytes { sysctlbyname("kern.bootsessionuuid", $0.baseAddress, &size, nil, 0) }
        guard read == 0 else { return nil }
        let value = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }
}
