import Foundation
import LidlessCore
import os
import Testing
@testable import Lidless

/// The parts of the safety net that run for real: the hang watchdog's queue
/// and the crash marker file.
@MainActor
struct SafetyNetTests {
    /// What the watchdog queue saw; written there, read on the main thread.
    private nonisolated final class HangRecorder: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (stalls: [TimeInterval](), onMain: false))

        func record(_ stall: TimeInterval) {
            let onMain = Thread.isMainThread
            state.withLock {
                $0.stalls.append(stall)
                $0.onMain = $0.onMain || onMain
            }
        }

        var stalls: [TimeInterval] { state.withLock { $0.stalls } }
        var ranOnMain: Bool { state.withLock { $0.onMain } }
    }

    @Test func `a stuck main thread fires the hang watchdog from its own queue`() {
        let recorder = HangRecorder()
        let watchdog = HangWatchdog(limit: 0.3, onHang: { stall in recorder.record(stall) })
        watchdog.setArmed(true)
        defer { watchdog.setArmed(false) }

        // The check runs a second after arming; the main thread never beats.
        Thread.sleep(forTimeInterval: 1.5)

        #expect(!recorder.stalls.isEmpty)
        #expect(recorder.stalls.allSatisfy { $0 > 0.3 })
        #expect(!recorder.ranOnMain)
    }

    @Test func `the crash marker file round-trips and clears`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafetyNetTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCrashMarkerStore(directory: directory)
        #expect(store.read().marker == nil)
        #expect(!store.read().fileExists)

        let marker = CrashMarker(
            stage: .active, method: .disconnect, builtInDisplayID: 1, builtInUUID: DisplayFixtures.builtInUUID,
            pid: getpid(), bootSessionUUID: store.currentBootSession, writtenAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        store.write(marker)
        #expect(store.read().marker == marker)
        #expect(store.read().fileExists)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        store.clear()
        #expect(store.read().marker == nil)
        #expect(!store.read().fileExists)
        // Clearing twice is fine.
        store.clear()
    }

    @Test func `a damaged marker file reads as present but empty`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafetyNetTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FileCrashMarkerStore(directory: directory)
        try Data("nonsense".utf8).write(to: store.fileURL)

        let (marker, fileExists) = store.read()
        #expect(marker == nil)
        #expect(fileExists)
    }
}
