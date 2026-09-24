import LidlessCore
import Testing
@testable import Lidless

// Only the copy mapping: posting needs a bundled app and the user's permission.

struct UserNotifierTests {
    @Test(arguments: [
        DeskModeRestoreReason.user,
        .declined,
        .terminating,
        .panic,
        .recovery,
    ])
    func `restores the user caused or already sees post nothing`(reason: DeskModeRestoreReason) {
        #expect(UserNotifier.note(for: reason) == nil)
    }

    @Test(arguments: [String?.none, "", "LG ULTRAGEAR"])
    func `losing the last external uses the designed copy`(name: String?) throws {
        let note = try #require(UserNotifier.note(for: .externalLost(displayName: name)))
        #expect(note.title == "Built-in display turned back on")
        #expect(note.body == "Your last external display was unplugged, so Lidless switched your built-in screen back on.")
        #expect(note.thread == "desk-mode")
    }

    @Test(arguments: [
        DeskModeRestoreReason.confirmationTimedOut,
        .sleep,
        .sessionChanged,
        .engageFailed,
        .timeLimit,
    ])
    func `restores the user didn't ask for replace one another`(reason: DeskModeRestoreReason) throws {
        let note = try #require(UserNotifier.note(for: reason))
        #expect(note.id == "desk-mode.restored")
        #expect(!note.body.isEmpty)
    }
}
