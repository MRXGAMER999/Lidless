import Foundation
import Testing
@testable import LidlessCore

struct CrashMarkerTests {
    static let boot = "6B0E4F1C-2D3A-4B5C-8D9E-0F1A2B3C4D5E"
    static let panel = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    static func marker(stage: CrashMarker.Stage = .active, method: DeskModeMethod = .disconnect, uuid: String? = panel, boot: String? = boot) -> CrashMarker {
        CrashMarker(stage: stage, method: method, builtInDisplayID: 1, builtInUUID: uuid, pid: 4242, bootSessionUUID: boot, writtenAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    // MARK: Encoding

    @Test(arguments: [
        marker(),
        marker(stage: .engaging, method: .blackout),
        marker(uuid: nil, boot: nil),
    ])
    func `round trips`(marker: CrashMarker) throws {
        #expect(CrashMarker.decode(try marker.encoded()) == marker)
    }

    @Test func `encoding is stable, sorted and ISO 8601`() throws {
        let text = String(decoding: try Self.marker().encoded(), as: UTF8.self)
        #expect(text == #"{"bootSessionUUID":"6B0E4F1C-2D3A-4B5C-8D9E-0F1A2B3C4D5E","builtInDisplayID":1,"builtInUUID":"37D8832A-2D66-02CA-B9F7-8F30A301B230","method":"disconnect","pid":4242,"stage":"active","writtenAt":"2026-09-21T14:13:20Z"}"#)
        #expect(try Self.marker().encoded() == Self.marker().encoded())
    }

    @Test func `nil fields are left out`() throws {
        let text = String(decoding: try Self.marker(uuid: nil, boot: nil).encoded(), as: UTF8.self)
        #expect(!text.contains("builtInUUID"))
        #expect(!text.contains("bootSessionUUID"))
    }

    @Test(arguments: [
        "",
        "not json",
        "{}",
        "[]",
        "null",
        #"{"stage":"active"}"#,
        // Unknown stage.
        #"{"builtInDisplayID":1,"method":"disconnect","pid":1,"stage":"off","writtenAt":"2026-09-21T14:13:20Z"}"#,
        // Unknown method.
        #"{"builtInDisplayID":1,"method":"gamma","pid":1,"stage":"active","writtenAt":"2026-09-21T14:13:20Z"}"#,
        // Date as a number, not ISO 8601.
        #"{"builtInDisplayID":1,"method":"disconnect","pid":1,"stage":"active","writtenAt":1790000000}"#,
        // Display ID out of range.
        #"{"builtInDisplayID":-1,"method":"disconnect","pid":1,"stage":"active","writtenAt":"2026-09-21T14:13:20Z"}"#,
        // Truncated write.
        #"{"builtInDisplayID":1,"method":"disconnect","pid":1,"stage":"act"#,
    ])
    func `damaged or foreign data decodes to nil`(text: String) {
        #expect(CrashMarker.decode(Data(text.utf8)) == nil)
    }

    @Test func `binary garbage decodes to nil`() {
        #expect(CrashMarker.decode(Data([0xFF, 0xFE, 0x00, 0x7B])) == nil)
    }

    @Test func `minimal hand-written marker decodes`() {
        let text = #"{"builtInDisplayID":3,"method":"blackout","pid":7,"stage":"engaging","writtenAt":"2026-09-21T14:13:20Z","extra":true}"#
        let marker = CrashMarker.decode(Data(text.utf8))
        #expect(marker == CrashMarker(stage: .engaging, method: .blackout, builtInDisplayID: 3, builtInUUID: nil, pid: 7, bootSessionUUID: nil, writtenAt: Date(timeIntervalSince1970: 1_790_000_000)))
    }

    // MARK: Launch recovery

    @Test func `no file does nothing`() {
        #expect(LaunchRecovery.decide(marker: nil, markerFileExists: false, currentBootSession: Self.boot, otherInstanceRunning: false) == .nothing)
    }

    @Test func `damaged file is discarded`() {
        #expect(LaunchRecovery.decide(marker: nil, markerFileExists: true, currentBootSession: Self.boot, otherInstanceRunning: false) == .discard)
        #expect(LaunchRecovery.decide(marker: nil, markerFileExists: true, currentBootSession: nil, otherInstanceRunning: true) == .discard)
    }

    @Test func `a decoded marker counts as a file`() {
        let result = LaunchRecovery.decide(marker: Self.marker(), markerFileExists: false, currentBootSession: Self.boot, otherInstanceRunning: false)
        #expect(result == .restore(displayID: 1, uuid: Self.panel, method: .disconnect, notify: true))
    }

    @Test func `another live instance owns the marker`() {
        #expect(LaunchRecovery.decide(marker: Self.marker(), markerFileExists: true, currentBootSession: Self.boot, otherInstanceRunning: true) == .nothing)
        // The live check comes first; a live owner can't be from another boot anyway.
        #expect(LaunchRecovery.decide(marker: Self.marker(), markerFileExists: true, currentBootSession: "OTHER", otherInstanceRunning: true) == .nothing)
    }

    @Test func `a restart since means the panel is back by itself`() {
        #expect(LaunchRecovery.decide(marker: Self.marker(), markerFileExists: true, currentBootSession: "OTHER", otherInstanceRunning: false) == .discard)
    }

    @Test(arguments: [
        (boot as String?, boot as String?),
        (nil, boot),
        (boot, nil),
        (nil, nil),
    ])
    func `same or unknown boot restores`(written: String?, current: String?) {
        let result = LaunchRecovery.decide(marker: Self.marker(boot: written), markerFileExists: true, currentBootSession: current, otherInstanceRunning: false)
        #expect(result == .restore(displayID: 1, uuid: Self.panel, method: .disconnect, notify: true))
    }

    @Test(arguments: [CrashMarker.Stage.engaging, .active], DeskModeMethod.allCases)
    func `every stage and method restores and notifies`(stage: CrashMarker.Stage, method: DeskModeMethod) {
        let result = LaunchRecovery.decide(marker: Self.marker(stage: stage, method: method, uuid: nil), markerFileExists: true, currentBootSession: Self.boot, otherInstanceRunning: false)
        #expect(result == .restore(displayID: 1, uuid: nil, method: method, notify: true))
    }

    @Test func `recovery from bytes on disk`() throws {
        let data = try Self.marker(stage: .engaging).encoded()
        let result = LaunchRecovery.decide(marker: CrashMarker.decode(data), markerFileExists: true, currentBootSession: Self.boot, otherInstanceRunning: false)
        #expect(result == .restore(displayID: 1, uuid: Self.panel, method: .disconnect, notify: true))
        let torn = data.prefix(data.count / 2)
        #expect(LaunchRecovery.decide(marker: CrashMarker.decode(torn), markerFileExists: true, currentBootSession: Self.boot, otherInstanceRunning: false) == .discard)
    }
}
