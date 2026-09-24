import CoreGraphics
import Foundation
import LidlessCore
import Testing
@testable import Lidless

/// `ExternalBrightnessController` against fakes: which method each display
/// gets, where levels go, and how pauses gate DDC and re-place the shades.
/// The LG ULTRAGEAR (ID 2) is the DDC candidate, as on the development Mac.
@MainActor
struct ExternalBrightnessControllerTests {
    let lg = DisplayFixtures.lgUUID

    // MARK: Methods

    @Test func `an Apple display is native and reads its level from DisplayServices`() {
        let rig = ExternalRig()
        rig.native.levels[7] = 0.4
        rig.controller.update(displays: [ExternalRig.studio, ExternalRig.builtIn])

        #expect(rig.controller.method(for: ExternalRig.studioUUID) == .native)
        // Read off the main thread: unknown until the answer arrives.
        #expect(rig.controller.level(for: ExternalRig.studioUUID) == nil)
        let changes = rig.changes
        rig.native.answerReads()
        #expect(rig.controller.level(for: ExternalRig.studioUUID) == 0.4)
        #expect(rig.changes == changes + 1)
        #expect(rig.ddcRequests.isEmpty)

        rig.controller.setLevel(0.7, for: ExternalRig.studioUUID)
        #expect(rig.native.writes == [.init(display: 7, level: 0.7)])
        #expect(rig.shades.isEmpty)
    }

    @Test func `a native level set before the read arrives wins`() {
        let rig = ExternalRig()
        rig.native.levels[7] = 0.4
        rig.controller.update(displays: [ExternalRig.studio])
        rig.controller.setLevel(0.7, for: ExternalRig.studioUUID)
        rig.native.answerReads()
        #expect(rig.controller.level(for: ExternalRig.studioUUID) == 0.7)
    }

    @Test func `an unreadable Apple display shows the level saved for it`() {
        let rig = ExternalRig(stored: [ExternalRig.studioUUID: ["level": 0.2, "method": "native"]])
        rig.controller.update(displays: [ExternalRig.studio])
        rig.native.answerReads()
        #expect(rig.controller.level(for: ExternalRig.studioUUID) == 0.2)
    }

    @Test func `a valid DDC read makes the display DDC with the monitor's level`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg, ExternalRig.builtIn])
        #expect(rig.controller.method(for: lg) == .probing)
        #expect(rig.controller.level(for: lg) == nil)

        rig.link(2).answerRead(ExternalRig.reply(current: 30, maximum: 100))
        #expect(rig.controller.method(for: lg) == .ddc(maximum: 100))
        #expect(rig.controller.level(for: lg) == 0.3)
        #expect(rig.changes == 2)

        rig.controller.setLevel(0.55, for: lg)
        #expect(rig.link(2).writes == [55])
        #expect(rig.shades.isEmpty)
        #expect(rig.stored(lg)?.method == "ddc")
    }

    @Test func `the DDC link is looked for off the main thread before the probe`() {
        let rig = ExternalRig()
        rig.holdsLinks = true
        rig.controller.update(displays: [ExternalRig.lg])
        #expect(rig.ddcRequests == [2])
        #expect(rig.links.isEmpty)
        #expect(rig.controller.method(for: lg) == .probing)

        rig.deliverLinks()
        rig.link(2).answerRead(ExternalRig.reply(current: 50, maximum: 100))
        #expect(rig.controller.method(for: lg) == .ddc(maximum: 100))
    }

    @Test func `a link found across a pause is never used`() {
        let rig = ExternalRig()
        rig.holdsLinks = true
        rig.controller.update(displays: [ExternalRig.lg])
        rig.controller.pause()
        rig.deliverLinks()
        let stale = rig.link(2)
        #expect(stale.isPaused)
        #expect(stale.pendingReads == 0)

        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(rig.ddcRequests == [2, 2])
        rig.deliverLinks()
        #expect(rig.link(2) !== stale)
        #expect(rig.link(2).pendingReads == 1)
    }

    @Test func `a permanent DDC failure goes to a shade at once, at a level saved for a shade`() {
        let rig = ExternalRig(stored: [DisplayFixtures.lgUUID: ["level": 0.5, "method": "shade"]])
        rig.controller.update(displays: [ExternalRig.lg])
        #expect(rig.shades.isEmpty)

        rig.link(2).answerRead(nil, permanent: true)
        #expect(rig.controller.method(for: lg) == .shade)
        #expect(rig.controller.level(for: lg) == 0.5)
        #expect(rig.link(2).isPaused)
        #expect(rig.shade(2).shownLevel == 0.5)
        #expect(rig.scheduler.delays.isEmpty)
    }

    @Test func `a fallback shade never starts at a level saved for DDC`() {
        let rig = ExternalRig(stored: [DisplayFixtures.lgUUID: ["level": 0.3, "method": "ddc"]])
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(nil, permanent: true)
        #expect(rig.controller.method(for: lg) == .shade)
        #expect(rig.controller.level(for: lg) == 1)
        #expect(rig.shades[2]?.isShown != true)
    }

    @Test func `a fallback shade never starts at a level from before methods were saved`() {
        let rig = ExternalRig(legacy: [DisplayFixtures.lgUUID: 0.3])
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(nil, permanent: true)
        #expect(rig.controller.level(for: lg) == 1)
        #expect(rig.shades[2]?.isShown != true)
    }

    @Test func `junk from the monitor is probed again after 5 s and 30 s before a shade`() {
        let rig = ExternalRig(stored: [DisplayFixtures.lgUUID: ["level": 0.6, "method": "shade"]])
        rig.controller.update(displays: [ExternalRig.lg])
        let first = rig.link(2)
        first.answerRead(nil)
        #expect(rig.controller.method(for: lg) == .probing)
        #expect(first.isPaused)
        #expect(rig.scheduler.delays == [5])
        #expect(rig.shades.isEmpty)

        rig.scheduler.fire()
        #expect(rig.ddcRequests == [2, 2])
        #expect(rig.link(2) !== first)
        rig.link(2).answerRead(nil)
        #expect(rig.controller.method(for: lg) == .probing)
        #expect(rig.scheduler.delays == [30])

        rig.scheduler.fire()
        #expect(rig.ddcRequests == [2, 2, 2])
        rig.link(2).answerRead(nil)
        #expect(rig.controller.method(for: lg) == .shade)
        #expect(rig.shade(2).shownLevel == 0.6)
        #expect(rig.scheduler.delays.isEmpty)
    }

    @Test func `a probe that answers on a retry makes the display DDC`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(nil)
        rig.scheduler.fire()
        rig.link(2).answerRead(ExternalRig.reply(current: 40, maximum: 100))
        #expect(rig.controller.method(for: lg) == .ddc(maximum: 100))
        #expect(rig.controller.level(for: lg) == 0.4)
        #expect(rig.shades.isEmpty)
    }

    @Test func `no DDC link is tried again before a shade`() {
        let rig = ExternalRig()
        rig.linksAvailable = false
        rig.controller.update(displays: [ExternalRig.lg])
        #expect(rig.controller.method(for: lg) == .probing)
        #expect(rig.scheduler.delays == [5])
        rig.scheduler.fire()
        #expect(rig.scheduler.delays == [30])
        rig.scheduler.fire()
        #expect(rig.controller.method(for: lg) == .shade)
        #expect(rig.ddcRequests == [2, 2, 2])
    }

    @Test func `a link that appears on a retry is used`() {
        let rig = ExternalRig()
        rig.linksAvailable = false
        rig.controller.update(displays: [ExternalRig.lg])
        rig.linksAvailable = true
        rig.scheduler.fire()
        rig.link(2).answerRead(ExternalRig.reply(current: 70, maximum: 100))
        #expect(rig.controller.method(for: lg) == .ddc(maximum: 100))
    }

    @Test func `a virtual display always gets a shade and never DDC`() {
        let rig = ExternalRig(stored: [ExternalRig.sidecarUUID: ["level": 0.6, "method": "shade"]])
        rig.controller.update(displays: [ExternalRig.sidecar])
        #expect(rig.controller.method(for: ExternalRig.sidecarUUID) == .shade)
        #expect(rig.ddcRequests.isEmpty)
        #expect(rig.shade(9).shownLevel == 0.6)
    }

    @Test func `a level from before methods were saved still dims a virtual display`() {
        // A display that is never probed only ever had a shade.
        let rig = ExternalRig(legacy: [ExternalRig.sidecarUUID: 0.6])
        rig.controller.update(displays: [ExternalRig.sidecar])
        #expect(rig.shade(9).shownLevel == 0.6)
    }

    @Test func `the built-in is never probed or shaded`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.builtIn])
        rig.controller.setLevel(0.2, for: DisplayFixtures.builtInUUID)
        #expect(rig.controller.level(for: DisplayFixtures.builtInUUID) == nil)
        #expect(rig.ddcRequests.isEmpty)
        #expect(rig.shades.isEmpty)
        #expect(rig.native.writes.isEmpty)
        #expect(rig.native.readCount == 0)
    }

    // MARK: Levels

    @Test func `levels are saved per display with their method and shades come back at launch`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.sidecar])
        rig.controller.setLevel(0.3, for: ExternalRig.sidecarUUID)
        #expect(rig.shade(9).shownLevel == 0.3)
        #expect(rig.stored(ExternalRig.sidecarUUID)?.level == 0.3)
        #expect(rig.stored(ExternalRig.sidecarUUID)?.method == "shade")

        let relaunched = ExternalRig(defaults: rig.defaults)
        relaunched.controller.update(displays: [ExternalRig.sidecar])
        #expect(relaunched.controller.level(for: ExternalRig.sidecarUUID) == 0.3)
        #expect(relaunched.shade(9).shownLevel == 0.3)
    }

    @Test func `levels from before methods were saved move to the new format`() {
        let rig = ExternalRig(legacy: [ExternalRig.sidecarUUID: 0.6, DisplayFixtures.lgUUID: 0.2])
        rig.controller.update(displays: [ExternalRig.sidecar])
        rig.controller.setLevel(0.5, for: ExternalRig.sidecarUUID)
        #expect(rig.stored(ExternalRig.sidecarUUID)?.level == 0.5)
        #expect(rig.stored(ExternalRig.sidecarUUID)?.method == "shade")
        // Kept, with no method: it could have been any.
        #expect(rig.stored(lg)?.level == 0.2)
        #expect(rig.stored(lg)?.method == nil)
    }

    @Test func `saved levels are clamped`() {
        let rig = ExternalRig(legacy: [ExternalRig.sidecarUUID: 7])
        rig.controller.update(displays: [ExternalRig.sidecar])
        #expect(rig.controller.level(for: ExternalRig.sidecarUUID) == 1)
        rig.controller.setLevel(-1, for: ExternalRig.sidecarUUID)
        #expect(rig.controller.level(for: ExternalRig.sidecarUUID) == 0)
    }

    @Test func `full brightness takes the shade window down`() {
        let rig = ExternalRig(legacy: [ExternalRig.sidecarUUID: 0.4])
        rig.controller.update(displays: [ExternalRig.sidecar])
        #expect(rig.shade(9).isShown)
        rig.controller.setLevel(1, for: ExternalRig.sidecarUUID)
        #expect(!rig.shade(9).isShown)
    }

    @Test func `moving the slider during the probe wins over the monitor's level`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.controller.setLevel(0.8, for: lg)
        #expect(rig.stored(lg)?.method == nil)
        rig.link(2).answerRead(ExternalRig.reply(current: 20, maximum: 50))
        #expect(rig.controller.level(for: lg) == 0.8)
        #expect(rig.link(2).writes == [40])
        #expect(rig.stored(lg)?.method == "ddc")
    }

    @Test func `the slider level carries over when the probe ends in a shade`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.controller.setLevel(0.25, for: lg)
        rig.link(2).answerRead(nil, permanent: true)
        #expect(rig.shade(2).shownLevel == 0.25)
        #expect(rig.stored(lg)?.method == "shade")
    }

    @Test func `a DDC link that dies on a write hands over to an undimmed shade`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(ExternalRig.reply(current: 100, maximum: 100))
        rig.controller.setLevel(0.4, for: lg)
        let changes = rig.changes

        rig.link(2).isDead = true
        rig.link(2).finishWrites(accepted: false)
        #expect(rig.controller.method(for: lg) == .shade)
        // 0.4 was a backlight level: as a shade it could dim twice.
        #expect(rig.controller.level(for: lg) == 1)
        #expect(rig.shades[2]?.isShown != true)
        #expect(rig.changes == changes + 1)
        #expect(rig.scheduler.delays.isEmpty)
    }

    @Test func `a failed DDC write is retried once after the write spacing`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(ExternalRig.reply(current: 100, maximum: 100))
        rig.controller.setLevel(0.4, for: lg)
        rig.link(2).finishWrites(accepted: false)
        #expect(rig.scheduler.delays == [DDCChannel.Timing.writeSpacing])
        #expect(rig.controller.method(for: lg) == .ddc(maximum: 100))

        rig.scheduler.fire()
        #expect(rig.link(2).writes == [40, 40])
        rig.link(2).finishWrites(accepted: false)
        // Once only: the level waits for the next write.
        #expect(rig.scheduler.delays.isEmpty)
        rig.controller.setLevel(0.5, for: lg)
        #expect(rig.link(2).writes == [40, 40, 50])
    }

    @Test func `a write that succeeds clears the failed writes`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(ExternalRig.reply(current: 100, maximum: 100))
        rig.controller.setLevel(0.4, for: lg)
        rig.link(2).finishWrites(accepted: false)
        rig.scheduler.fire()
        rig.link(2).finishWrites(accepted: true)

        rig.controller.setLevel(0.3, for: lg)
        rig.link(2).finishWrites(accepted: false)
        #expect(rig.scheduler.delays == [DDCChannel.Timing.writeSpacing])
    }

    @Test func `a newer level makes the pending retry unnecessary`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(ExternalRig.reply(current: 100, maximum: 100))
        rig.controller.setLevel(0.4, for: lg)
        rig.link(2).finishWrites(accepted: false)
        rig.controller.setLevel(0.6, for: lg)
        rig.scheduler.fire()
        #expect(rig.link(2).writes == [40, 60])
    }

    @Test func `a level whose retry failed goes out after the next resume`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(ExternalRig.reply(current: 100, maximum: 100))
        rig.controller.setLevel(0.4, for: lg)
        rig.link(2).finishWrites(accepted: false)
        rig.scheduler.fire()
        rig.link(2).finishWrites(accepted: false)
        let first = rig.link(2)

        rig.controller.pause()
        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(rig.link(2) !== first)
        #expect(rig.link(2).writes == [40])
    }

    @Test func `a DDC display whose link is gone after a resume is probed again`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(ExternalRig.reply(current: 100, maximum: 100))
        rig.controller.pause()
        rig.controller.setLevel(0.3, for: lg)
        rig.linksAvailable = false
        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(rig.controller.method(for: lg) == .probing)
        #expect(rig.scheduler.delays == [5])

        rig.linksAvailable = true
        rig.scheduler.fire()
        rig.link(2).answerRead(ExternalRig.reply(current: 100, maximum: 100))
        #expect(rig.controller.method(for: lg) == .ddc(maximum: 100))
        // The level that couldn't be sent goes out now.
        #expect(rig.link(2).writes == [30])
    }

    // MARK: Pausing

    @Test func `a pause holds DDC writes and drops the handle until the resume`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        let first = rig.link(2)
        first.answerRead(ExternalRig.reply(current: 100, maximum: 100))

        rig.controller.pause()
        #expect(first.isPaused)
        rig.controller.setLevel(0.2, for: lg)
        rig.controller.setLevel(0.3, for: lg)
        #expect(first.writes.isEmpty)
        #expect(rig.ddcRequests == [2])

        rig.controller.resume(after: 1)
        #expect(rig.scheduler.delays == [1])
        rig.scheduler.fire()
        #expect(rig.ddcRequests == [2, 2])
        #expect(rig.link(2) !== first)
        #expect(rig.link(2).writes == [30])
    }

    @Test func `a write cut off by a pause is sent again after it`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(ExternalRig.reply(current: 100, maximum: 100))
        rig.controller.setLevel(0.6, for: lg)
        let first = rig.link(2)

        rig.controller.pause()
        first.finishWrites(accepted: false)
        // Not a failure to retry: the resume sends it.
        #expect(rig.scheduler.delays.isEmpty)
        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(rig.link(2) !== first)
        #expect(rig.link(2).writes == [60])
    }

    @Test func `a probe cut off by a pause runs again after it`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        let first = rig.link(2)
        rig.controller.pause()
        // The paused link answers with nothing; that must not mean "no DDC".
        first.answerRead(nil)
        #expect(rig.controller.method(for: lg) == .probing)
        #expect(rig.scheduler.delays.isEmpty)

        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        rig.link(2).answerRead(ExternalRig.reply(current: 10, maximum: 100))
        #expect(rig.controller.method(for: lg) == .ddc(maximum: 100))
    }

    @Test func `a pause during the back-off probes again after the resume`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(nil)
        rig.controller.pause()
        rig.controller.resume(after: 1)
        #expect(rig.scheduler.delays == [5, 1])
        // The old back-off timer is void; the resume probes once.
        rig.scheduler.fire()
        #expect(rig.ddcRequests == [2, 2])
        rig.link(2).answerRead(nil)
        // The failures so far still count.
        #expect(rig.scheduler.delays == [30])
    }

    @Test func `a display found while paused is probed after the resume`() {
        let rig = ExternalRig()
        rig.controller.pause()
        rig.controller.update(displays: [ExternalRig.lg])
        #expect(rig.ddcRequests.isEmpty)
        #expect(rig.controller.method(for: lg) == .probing)
        rig.controller.resume(after: 3)
        rig.scheduler.fire()
        #expect(rig.ddcRequests == [2])
    }

    @Test func `only the latest resume ends a pause`() {
        let rig = ExternalRig()
        rig.controller.pause()
        rig.controller.resume(after: 1)
        rig.controller.pause()
        rig.scheduler.fire()
        #expect(rig.controller.isPaused)

        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(!rig.controller.isPaused)
    }

    @Test func `native writes wait for the resume too`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.studio])
        rig.controller.pause()
        #expect(rig.native.isPaused)
        rig.controller.setLevel(0.2, for: ExternalRig.studioUUID)
        rig.controller.setLevel(0.9, for: ExternalRig.studioUUID)
        #expect(rig.native.writes.isEmpty)
        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(!rig.native.isPaused)
        #expect(rig.native.writes == [.init(display: 7, level: 0.9)])
    }

    @Test func `shades stay up while paused and are re-fitted after`() {
        let rig = ExternalRig(legacy: [ExternalRig.sidecarUUID: 0.5])
        rig.controller.update(displays: [ExternalRig.sidecar])
        rig.controller.pause()
        #expect(rig.shade(9).isShown)
        rig.controller.setLevel(0.4, for: ExternalRig.sidecarUUID)
        #expect(rig.shade(9).shownLevel == 0.4)

        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(rig.shade(9).refits == 1)
        #expect(rig.shade(9).isShown)
    }

    @Test func `a shade that lost its screen during a pause comes back after it`() {
        let rig = ExternalRig(legacy: [ExternalRig.sidecarUUID: 0.5])
        rig.controller.update(displays: [ExternalRig.sidecar])
        rig.controller.pause()
        rig.shade(9).lose()
        rig.controller.setLevel(0.45, for: ExternalRig.sidecarUUID)
        #expect(!rig.shade(9).isShown)

        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(rig.shade(9).shownLevel == 0.45)
    }

    @Test func `no new shade goes up while paused`() {
        let rig = ExternalRig(legacy: [ExternalRig.sidecarUUID: 0.5])
        rig.controller.pause()
        rig.controller.update(displays: [ExternalRig.sidecar])
        #expect(rig.shades[9]?.isShown != true)
        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(rig.shade(9).shownLevel == 0.5)
    }

    // MARK: Displays coming and going

    @Test func `a display that leaves takes its shade with it`() {
        let rig = ExternalRig(legacy: [ExternalRig.sidecarUUID: 0.5])
        rig.controller.update(displays: [ExternalRig.sidecar])
        rig.controller.update(displays: [])
        #expect(!rig.shade(9).isShown)
        #expect(rig.controller.level(for: ExternalRig.sidecarUUID) == nil)
    }

    @Test func `a display back under a new ID is probed again`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        let first = rig.link(2)

        var moved = ExternalRig.lg
        moved.displayID = 4
        rig.controller.update(displays: [moved])
        #expect(rig.ddcRequests == [2, 4])
        #expect(first.isPaused)
        // A late answer from the old attach changes nothing.
        first.answerRead(ExternalRig.reply(current: 1, maximum: 2))
        #expect(rig.controller.method(for: lg) == .probing)

        rig.link(4).answerRead(ExternalRig.reply(current: 70, maximum: 100))
        #expect(rig.controller.method(for: lg) == .ddc(maximum: 100))
    }

    @Test func `a back-off timer from an old attach does nothing`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.link(2).answerRead(nil)
        var moved = ExternalRig.lg
        moved.displayID = 4
        rig.controller.update(displays: [moved])
        rig.scheduler.fire()
        #expect(rig.ddcRequests == [2, 4])
    }

    @Test func `no shade while displays mirror`() {
        let rig = ExternalRig(legacy: [ExternalRig.sidecarUUID: 0.5])
        rig.controller.update(displays: [ExternalRig.sidecar])
        var mirroredBuiltIn = ExternalRig.builtIn
        mirroredBuiltIn.role = .mirrored
        rig.controller.update(displays: [ExternalRig.sidecar, mirroredBuiltIn])
        #expect(!rig.shade(9).isShown)

        rig.controller.update(displays: [ExternalRig.sidecar, ExternalRig.builtIn])
        #expect(rig.shade(9).shownLevel == 0.5)
    }

    // MARK: Panic key

    @Test func `removing all shades shows full brightness but keeps the saved level`() {
        let rig = ExternalRig(stored: [ExternalRig.sidecarUUID: ["level": 0.3, "method": "shade"]])
        rig.controller.update(displays: [ExternalRig.sidecar])
        let changes = rig.changes
        rig.controller.removeAllShades()
        #expect(!rig.shade(9).isShown)
        #expect(rig.controller.level(for: ExternalRig.sidecarUUID) == 1)
        #expect(rig.changes == changes + 1)

        // Later display changes and pauses don't bring it back.
        rig.controller.update(displays: [ExternalRig.sidecar])
        rig.controller.pause()
        rig.controller.resume(after: 1)
        rig.scheduler.fire()
        #expect(!rig.shade(9).isShown)
        #expect(rig.stored(ExternalRig.sidecarUUID)?.level == 0.3)
        #expect(rig.stored(ExternalRig.sidecarUUID)?.method == "shade")
    }

    @Test func `after the panic key a display that comes back starts undimmed until its slider moves`() {
        let rig = ExternalRig(stored: [ExternalRig.sidecarUUID: ["level": 0.4, "method": "shade"]])
        rig.controller.update(displays: [ExternalRig.sidecar])
        rig.controller.removeAllShades()
        rig.controller.update(displays: [])
        rig.controller.update(displays: [ExternalRig.sidecar])
        #expect(rig.controller.level(for: ExternalRig.sidecarUUID) == 1)
        #expect(!rig.shade(9).isShown)

        rig.controller.setLevel(0.6, for: ExternalRig.sidecarUUID)
        #expect(rig.shade(9).shownLevel == 0.6)
        rig.controller.update(displays: [])
        rig.controller.update(displays: [ExternalRig.sidecar])
        #expect(rig.shade(9).shownLevel == 0.6)
    }

    @Test func `after the panic key a probe that fails brings no dimmed shade`() {
        let rig = ExternalRig(stored: [DisplayFixtures.lgUUID: ["level": 0.5, "method": "shade"]])
        rig.controller.update(displays: [ExternalRig.lg])
        rig.controller.setLevel(0.3, for: lg)
        rig.controller.removeAllShades()
        rig.link(2).answerRead(nil, permanent: true)
        #expect(rig.controller.method(for: lg) == .shade)
        #expect(rig.controller.level(for: lg) == 1)
        #expect(rig.shades[2]?.isShown != true)
    }

    @Test func `after the panic key a probe that succeeds writes no level from before it`() {
        let rig = ExternalRig()
        rig.controller.update(displays: [ExternalRig.lg])
        rig.controller.setLevel(0.3, for: lg)
        rig.controller.removeAllShades()
        rig.link(2).answerRead(ExternalRig.reply(current: 80, maximum: 100))
        #expect(rig.controller.level(for: lg) == 0.8)
        #expect(rig.link(2).writes.isEmpty)
    }
}

/// `NativeBrightnessQueue` with recorded DisplayServices calls: it runs on a
/// real queue, so each test waits for it.
@MainActor
struct NativeBrightnessQueueTests {
    @Test func `writes are held while paused and the latest goes out on resume`() {
        let recorder = NativeCallRecorder()
        let queue = NativeBrightnessQueue(calls: recorder.calls)
        queue.setPaused(true)
        queue.submit(0.2, to: 7)
        queue.submit(0.6, to: 7)
        queue.waitUntilIdle()
        #expect(recorder.writes.isEmpty)

        queue.setPaused(false)
        queue.waitUntilIdle()
        #expect(recorder.writes == [NativeWrite(display: 7, level: 0.6)])
    }

    @Test func `a write queued before a pause waits for the resume`() {
        let recorder = NativeCallRecorder(blocksReads: true)
        let queue = NativeBrightnessQueue(calls: recorder.calls)
        // A read holds the queue, so the write is still queued when the pause lands.
        queue.read(7) { _ in }
        queue.submit(0.3, to: 7)
        queue.setPaused(true)
        recorder.releaseRead()
        queue.waitUntilIdle()
        #expect(recorder.writes.isEmpty)

        queue.setPaused(false)
        queue.waitUntilIdle()
        #expect(recorder.writes == [NativeWrite(display: 7, level: 0.3)])
    }

    @Test func `writes coalesce to the latest level`() {
        let recorder = NativeCallRecorder(blocksReads: true)
        let queue = NativeBrightnessQueue(calls: recorder.calls)
        queue.read(7) { _ in }
        queue.submit(0.1, to: 7)
        queue.submit(0.5, to: 7)
        queue.submit(0.4, to: 8)
        recorder.releaseRead()
        queue.waitUntilIdle()
        #expect(recorder.writes == [NativeWrite(display: 7, level: 0.5), NativeWrite(display: 8, level: 0.4)])
    }

    @Test func `reads run off the main thread and answer on it`() async {
        let recorder = NativeCallRecorder()
        recorder.level = 0.35
        let queue = NativeBrightnessQueue(calls: recorder.calls)
        let level: Double? = await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            queue.read(7) { level in
                #expect(Thread.isMainThread)
                continuation.resume(returning: level)
            }
        }
        #expect(level == 0.35)
        #expect(recorder.readOnMainThread == false)
    }
}

// MARK: - Rig

@MainActor
final class ExternalRig {
    static let studioUUID = "A1B2C3D4-0000-4000-8000-00000000A0B1"
    static let sidecarUUID = "5F3B7A10-1111-4222-8333-444455556666"

    static let builtIn = DisplayDescriptor(
        id: DisplayFixtures.builtInUUID, displayID: 1, name: "Built-in Retina Display", isBuiltIn: true,
        pixelWidth: 3024, pixelHeight: 1964, role: .extended, supportsBoost: true, brightnessControl: .native
    )
    static let lg = DisplayDescriptor(
        id: DisplayFixtures.lgUUID, displayID: 2, name: "LG ULTRAGEAR", isBuiltIn: false,
        pixelWidth: 1920, pixelHeight: 1080, refreshRate: 144, role: .main, brightnessControl: .ddc
    )
    static let studio = DisplayDescriptor(
        id: studioUUID, displayID: 7, name: "Studio Display", isBuiltIn: false,
        pixelWidth: 5120, pixelHeight: 2880, role: .extended, brightnessControl: .native
    )
    static let sidecar = DisplayDescriptor(
        id: sidecarUUID, displayID: 9, name: "Sidecar Display", isBuiltIn: false,
        pixelWidth: 2388, pixelHeight: 1668, role: .extended, isVirtual: true, brightnessControl: .software
    )

    let defaults: UserDefaults
    /// The suite this rig made, removed when it goes.
    private let suiteName: String?
    let native = FakeNativeBrightness()
    let scheduler = FakeAfter()
    var linksAvailable = true
    /// Links are handed over only on `deliverLinks()`, as the live lookup
    /// answers later from another thread.
    var holdsLinks = false
    /// Display IDs a DDC link was asked for, in order.
    private(set) var ddcRequests: [CGDirectDisplayID] = []
    private(set) var links: [CGDirectDisplayID: FakeDDCLink] = [:]
    private(set) var shades: [CGDirectDisplayID: FakeShade] = [:]
    private(set) var changes = 0
    private(set) var controller: ExternalBrightnessController!
    private var heldLinks: [() -> Void] = []

    /// - Parameters:
    ///   - legacy: levels in the format from before methods were saved.
    ///   - stored: levels as saved now, `[uuid: ["level": x, "method": m]]`.
    init(defaults: UserDefaults? = nil, legacy: [String: Double] = [:], stored: [String: [String: Any]] = [:]) {
        if let defaults {
            self.defaults = defaults
            suiteName = nil
        } else {
            let name = "ExternalRig-\(UUID().uuidString)"
            self.defaults = UserDefaults(suiteName: name)!
            suiteName = name
        }
        if !legacy.isEmpty { self.defaults.set(legacy, forKey: ExternalBrightnessController.defaultsKey) }
        if !stored.isEmpty { self.defaults.set(stored, forKey: ExternalBrightnessController.defaultsKey) }
        let scheduler = scheduler
        let services = ExternalBrightnessController.Services(
            native: native,
            makeDDC: { [unowned self] id, completion in
                self.ddcRequests.append(id)
                let hand = { [unowned self] in
                    guard self.linksAvailable else { return completion(nil) }
                    let link = FakeDDCLink()
                    self.links[id] = link
                    completion(link)
                }
                if self.holdsLinks {
                    self.heldLinks.append(hand)
                } else {
                    hand()
                }
            },
            makeShade: { [unowned self] id in
                #expect(id != 1, "never a shade on the built-in")
                let shade = FakeShade()
                self.shades[id] = shade
                return shade
            },
            after: { delay, work in scheduler.schedule(delay, work) }
        )
        controller = ExternalBrightnessController(services: services, defaults: self.defaults)
        controller.onChange = { [unowned self] in self.changes += 1 }
    }

    deinit {
        if let suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
    }

    func link(_ id: CGDirectDisplayID) -> FakeDDCLink { links[id]! }

    /// Answers every link lookup made so far.
    func deliverLinks() {
        let held = heldLinks
        heldLinks = []
        held.forEach { $0() }
    }

    /// A luminance reply as a monitor sends it, parsed the way `DDCLink` does.
    static func reply(current: UInt16, maximum: UInt16) -> DDC.Reply {
        var bytes: [UInt8] = [0x6E, 0x88, 0x02, 0x00, DDC.luminance, 0x00,
                              UInt8(maximum >> 8), UInt8(maximum & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)]
        bytes.append(bytes.reduce(0x50, ^))
        return DDC.parseReply(bytes, code: DDC.luminance)!
    }
    func shade(_ id: CGDirectDisplayID) -> FakeShade { shades[id]! }

    /// What UserDefaults holds for a display: its level and method.
    func stored(_ uuid: String) -> (level: Double?, method: String?)? {
        guard let fields = defaults.dictionary(forKey: ExternalBrightnessController.defaultsKey)?[uuid] as? [String: Any] else { return nil }
        return (fields["level"] as? Double, fields["method"] as? String)
    }
}

@MainActor
final class FakeDDCLink: ExternalDDCLink {
    var isPaused = false
    var isDead = false
    private var reads: [@MainActor (DDC.Reply?, Bool) -> Void] = []
    private var writeCompletions: [@MainActor (Bool) -> Void] = []
    private(set) var writes: [UInt16] = []
    var pendingReads: Int { reads.count }

    func readLuminance(completion: @escaping @MainActor (DDC.Reply?, _ permanentFailure: Bool) -> Void) {
        reads.append(completion)
    }

    func writeLuminance(_ value: UInt16, completion: @escaping @MainActor (Bool) -> Void) {
        writes.append(value)
        writeCompletions.append(completion)
    }

    func answerRead(_ reply: DDC.Reply?, permanent: Bool = false) {
        if permanent { isDead = true }
        reads.removeFirst()(reply, permanent)
    }

    func finishWrites(accepted: Bool) {
        let completions = writeCompletions
        writeCompletions = []
        completions.forEach { $0(accepted) }
    }
}

@MainActor
final class FakeNativeBrightness: ExternalNativeBrightness {
    struct Write: Equatable {
        var display: CGDirectDisplayID
        var level: Double
    }

    var levels: [CGDirectDisplayID: Double] = [:]
    var isPaused = false
    private(set) var writes: [Write] = []
    private(set) var readCount = 0
    private var reads: [(display: CGDirectDisplayID, completion: @MainActor (Double?) -> Void)] = []

    func readLevel(of display: CGDirectDisplayID, completion: @escaping @MainActor (Double?) -> Void) {
        readCount += 1
        reads.append((display, completion))
    }

    /// Answers every read so far from `levels`.
    func answerReads() {
        let due = reads
        reads = []
        for read in due { read.completion(levels[read.display]) }
    }

    func setLevel(_ level: Double, of display: CGDirectDisplayID) {
        writes.append(Write(display: display, level: level))
    }
}

@MainActor
final class FakeShade: ExternalShade {
    private(set) var isShown = false
    /// The level on screen, nil when no window is up.
    private(set) var shownLevel: Double?
    private(set) var refits = 0

    func show(level: Double) -> Bool {
        guard ShadeMath.alpha(forLevel: level) > 0 else {
            remove()
            return true
        }
        isShown = true
        shownLevel = level
        return true
    }

    func refit() -> Bool {
        guard isShown else { return false }
        refits += 1
        return true
    }

    func remove() {
        isShown = false
        shownLevel = nil
    }

    /// AppKit moved the window or its screen went away.
    func lose() { remove() }
}

@MainActor
final class FakeAfter {
    private var pending: [(delay: TimeInterval, work: @MainActor @Sendable () -> Void)] = []
    var delays: [TimeInterval] { pending.map(\.delay) }

    func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor @Sendable () -> Void) {
        pending.append((delay, work))
    }

    /// Runs everything scheduled so far, in order.
    func fire() {
        let due = pending
        pending = []
        due.forEach { $0.work() }
    }
}

nonisolated struct NativeWrite: Equatable, Sendable {
    var display: CGDirectDisplayID
    var level: Float
}

/// DisplayServices stand-ins for `NativeBrightnessQueue`, called on its queue.
nonisolated final class NativeCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let blocksReads: Bool
    private let gate = DispatchSemaphore(value: 0)
    private var _writes: [NativeWrite] = []
    private var _level: Double?
    private var _readOnMainThread: Bool?

    init(blocksReads: Bool = false) {
        self.blocksReads = blocksReads
    }

    var writes: [NativeWrite] { locked { _writes } }
    var level: Double? {
        get { locked { _level } }
        set { locked { _level = newValue } }
    }
    var readOnMainThread: Bool? { locked { _readOnMainThread } }

    /// Lets a blocked read finish.
    func releaseRead() { gate.signal() }

    var calls: NativeBrightnessQueue.Calls {
        NativeBrightnessQueue.Calls(
            read: { [self] _ in
                let onMain = Thread.isMainThread
                if blocksReads { gate.wait() }
                return locked {
                    _readOnMainThread = onMain
                    return _level
                }
            },
            write: { [self] display, level in
                locked { _writes.append(NativeWrite(display: display, level: level)) }
            }
        )
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
