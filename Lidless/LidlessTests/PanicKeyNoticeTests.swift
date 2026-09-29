import Carbon.HIToolbox
import LidlessCore
import Testing
@testable import Lidless

/// The note under the panic key hero in Settings › Keys & App.
struct PanicKeyNoticeTests {
    private let panicB = KeyShortcut.defaultPanic
    private let panicK = KeyShortcut(keyCode: 0x28, keyLabel: "K", modifiers: [.control, .option, .command])

    private var changeToK: PanicKeyNotice.Change {
        PanicKeyNotice.Change(recorded: panicK, previous: panicB)
    }

    @Test func `no note while the panic key is held`() {
        #expect(PanicKeyNotice.resolve(change: nil, saved: panicB, registration: .exclusive).notice == nil)
        #expect(PanicKeyNotice.resolve(change: nil, saved: panicB, registration: nil).notice == nil)
    }

    @Test func `a key shared with another app gets a note`() {
        #expect(PanicKeyNotice.resolve(change: nil, saved: panicB, registration: .shared).notice == .shared)
    }

    @Test func `a key that isn't registered gets a note`() {
        let result = PanicKeyNotice.resolve(change: nil, saved: panicB, registration: .failed(OSStatus(eventHotKeyExistsErr)))
        #expect(result.notice == .notRegistered)
    }

    @Test func `recorded keys put back to the previous ones were refused`() {
        // The app registered the previous key again, so Carbon holds it exclusively.
        let result = PanicKeyNotice.resolve(change: changeToK, saved: panicB, registration: .exclusive)
        #expect(result.notice == .refused(panicK, kept: panicB))
        // Kept, so the note stays until the next recording.
        #expect(result.change == changeToK)
    }

    @Test func `recorded keys that stayed are accepted and the check ends`() {
        let result = PanicKeyNotice.resolve(change: changeToK, saved: panicK, registration: .exclusive)
        #expect(result.notice == nil)
        #expect(result.change == nil)
    }

    @Test func `accepted keys shared with another app still get the shared note`() {
        let result = PanicKeyNotice.resolve(change: changeToK, saved: panicK, registration: .shared)
        #expect(result.notice == .shared)
        #expect(result.change == nil)
    }

    @Test func `the refusal names both keys`() {
        let message = PanicKeyNotice.refused(panicK, kept: panicB).message { $0.keyLabel }
        #expect(message.contains("K"))
        #expect(message.contains("B"))
    }

    @Test func `every note has text`() {
        for notice in [PanicKeyNotice.shared, .notRegistered, .refused(panicK, kept: panicB)] {
            #expect(!notice.message { $0.keyLabel }.isEmpty)
        }
    }
}
