import LidlessCore
import Testing
@testable import Lidless

// Only the pure parts: which apps run depends on the Mac, and posting needs a
// bundled app and the user's permission.

struct ConflictingAppMonitorTests {
    @Test func `Boost counts as on while engaging or on`() {
        #expect(ConflictingAppMonitor.isBoosting(.engaging))
        #expect(ConflictingAppMonitor.isBoosting(.on(factor: 1.4)))
        #expect(!ConflictingAppMonitor.isBoosting(.off))
        #expect(!ConflictingAppMonitor.isBoosting(.unavailable))
    }

    @Test func `external brightness counts as on once a display is dimmed`() {
        #expect(!ConflictingAppMonitor.isDimming([:]))
        #expect(!ConflictingAppMonitor.isDimming(["A": 1, "B": 0.995]))
        #expect(ConflictingAppMonitor.isDimming(["A": 1, "B": 0.6]))
    }

    @Test(arguments: ConflictFeature.allCases)
    func `each warning names the app and replaces older ones about it`(feature: ConflictFeature) throws {
        let app = try #require(ConflictingApps.app(forBundleID: "pro.betterdisplay.BetterDisplay"))
        let note = UserNotifier.note(for: ConflictNotice(app: app, feature: feature))
        #expect(note.title == "BetterDisplay is also running")
        #expect(note.id == "conflict.pro.betterdisplay.BetterDisplay")
        #expect(note.thread == "conflicts")
        #expect(!note.body.isEmpty)
        #expect(!note.sound)
    }

    @Test func `the Desk Mode warning says what the other app can do`() throws {
        let app = try #require(ConflictingApps.app(forBundleID: "dev.solodisplay.SoloDisplay"))
        let note = UserNotifier.note(for: ConflictNotice(app: app, feature: .deskMode))
        #expect(note.body == "It can turn your built-in screen back on. Quit it while you use Desk Mode.")
    }
}
