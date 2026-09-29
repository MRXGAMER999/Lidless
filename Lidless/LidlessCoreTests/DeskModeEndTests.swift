import Foundation
import Testing
@testable import LidlessCore

/// Every path that ends Desk Mode gets one log line naming the reason.
struct DeskModeEndTests {
    private static let date = Date(timeIntervalSince1970: 1_800_000_000)
    private static let engaging = DeskModeMachine.Phase.engaging(trigger: .manual, method: .disconnect, startedAt: 100)
    private static let confirming = DeskModeMachine.Phase.confirming(trigger: .manual, method: .disconnect, since: date, deadline: 115)
    private static let active = DeskModeMachine.Phase.active(trigger: .manual, method: .disconnect, since: date, engagedAt: 100)

    private static func restoring(_ reason: DeskModeRestoreReason) -> DeskModeMachine.Phase {
        .restoring(reason: reason, method: .disconnect, lastAttempt: 400)
    }

    @Test(arguments: [engaging, confirming, active])
    func `leaving a session for a restore names its reason`(before: DeskModeMachine.Phase) {
        let end = DeskModeEnd.detect(from: before, to: Self.restoring(.timeLimit), on: .tick)
        #expect(end == .restoring(.timeLimit))
        #expect(end?.key == "timeLimit")
    }

    @Test func `a panel back on its own is told apart from an exit`() {
        #expect(DeskModeEnd.detect(from: Self.active, to: .idle, on: .snapshot(.init())) == .cameBackOnItsOwn)
        #expect(DeskModeEnd.detect(from: Self.confirming, to: .idle, on: .tick) == .cameBackOnItsOwn)
        #expect(DeskModeEnd.detect(from: Self.active, to: .idle, on: .willTerminate) == .exiting)
    }

    @Test func `transitions that don't end a session aren't endings`() {
        #expect(DeskModeEnd.detect(from: .idle, to: Self.engaging, on: .turnOn(trigger: .manual)) == nil)
        #expect(DeskModeEnd.detect(from: Self.engaging, to: Self.confirming, on: .disableFinished(succeeded: true)) == nil)
        #expect(DeskModeEnd.detect(from: Self.confirming, to: Self.active, on: .keep) == nil)
        #expect(DeskModeEnd.detect(from: Self.restoring(.user), to: .idle, on: .enableFinished(succeeded: true)) == nil)
        #expect(DeskModeEnd.detect(from: .idle, to: Self.restoring(.recovery), on: .resumeRestore(displayID: 1, uuid: nil, method: .disconnect)) == nil)
        #expect(DeskModeEnd.detect(from: Self.restoring(.user), to: Self.restoring(.panic), on: .panic) == nil)
    }

    @Test func `the session length counts from when the panel went off`() {
        #expect(DeskModeEnd.sessionLength(of: Self.engaging, now: 103, confirmationSeconds: 15) == 3)
        #expect(DeskModeEnd.sessionLength(of: Self.confirming, now: 110, confirmationSeconds: 15) == 10)
        #expect(DeskModeEnd.sessionLength(of: Self.active, now: 400, confirmationSeconds: 15) == 300)
        #expect(DeskModeEnd.sessionLength(of: .idle, now: 400, confirmationSeconds: 15) == nil)
        #expect(DeskModeEnd.sessionLength(of: Self.restoring(.user), now: 400, confirmationSeconds: 15) == nil)
    }

    @Test(arguments: [
        DeskModeRestoreReason.user, .panic, .externalLost(displayName: "LG ULTRAGEAR"), .confirmationTimedOut,
        .declined, .sleep, .sessionChanged, .engageFailed, .timeLimit, .terminating, .recovery,
    ])
    func `every reason has a key and a plain explanation without display names`(reason: DeskModeRestoreReason) {
        let end = DeskModeEnd.restoring(reason)
        #expect(!end.key.isEmpty)
        #expect(!end.key.contains(" "))
        #expect(!end.explanation.isEmpty)
        #expect(!end.explanation.contains("LG"))
    }

    /// End to end with the machine: the debug limit, an unplug and a panel that
    /// came back by itself each read as the ending they are.
    @Test func `the machine's endings are detected`() {
        func run(_ configuration: DeskModeMachine.Configuration, _ steps: (inout DeskModeMachine, inout TimeInterval) -> DeskModeEvent) -> DeskModeEnd? {
            let atDesk = DeskModeSnapshot(
                facts: DisplayFixtures.thisMac, previous: nil, lid: .open, screensAsleep: false,
                systemSleeping: false, sessionActive: true, power: .adapter, names: DisplayFixtures.names
            )
            var machine = DeskModeMachine(configuration: configuration, snapshot: atDesk)
            var now: TimeInterval = 1000
            _ = machine.handle(.turnOn(trigger: .manual), now: now)
            _ = machine.handle(.disableFinished(succeeded: true), now: now)
            let panelOff = DeskModeSnapshot(
                facts: [DisplayFixtures.lg], previous: atDesk, lid: .open, screensAsleep: false,
                systemSleeping: false, sessionActive: true, power: .adapter, names: DisplayFixtures.names
            )
            _ = machine.handle(.snapshot(panelOff), now: now)
            now += 5
            _ = machine.handle(.tick, now: now)
            let before = machine.phase
            let event = steps(&machine, &now)
            _ = machine.handle(event, now: now)
            return DeskModeEnd.detect(from: before, to: machine.phase, on: event)
        }
        let noPrompt = DeskModeMachine.Configuration(askBeforeKeeping: false)

        var limited = noPrompt
        limited.maxDuration = 300
        #expect(run(limited) { _, now in now += 300; return .tick } == .restoring(.timeLimit))
        #expect(run(noPrompt) { _, now in now += 300; return .tick } == nil)

        let backOnItsOwn = DeskModeSnapshot(
            facts: DisplayFixtures.thisMac, previous: nil, lid: .open, screensAsleep: false,
            systemSleeping: false, sessionActive: true, power: .adapter, names: DisplayFixtures.names
        )
        #expect(run(noPrompt) { _, _ in .snapshot(backOnItsOwn) } == .cameBackOnItsOwn)
        #expect(run(noPrompt) { _, _ in .turnOff } == .restoring(.user))
        #expect(run(noPrompt) { _, _ in .willTerminate } == .exiting)
    }
}
