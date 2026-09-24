import CoreGraphics
import Foundation
import LidlessCore
import Testing
@testable import Lidless

// Nothing here changes brightness: every test injects a fake setter, and the
// display ID is one no real display uses.

@MainActor
private final class FakePanel {
    var now: TimeInterval = 100
    var writable = true
    private(set) var writes: [(display: CGDirectDisplayID, level: Float)] = []

    var setter: DisplayServicesBrightnessWriter.Setter {
        .init(
            canWrite: { [unowned self] _ in writable },
            write: { [unowned self] display, level in writes.append((display, level)) }
        )
    }

    func writer() -> DisplayServicesBrightnessWriter {
        DisplayServicesBrightnessWriter(setter: setter, clock: { [unowned self] in now })
    }

    var levels: [Float] { writes.map(\.level) }
}

@MainActor
struct BrightnessWriterTests {
    private static let display: CGDirectDisplayID = 0x7E57_0003

    @Test
    func `the first level is written at once`() {
        let panel = FakePanel()
        let writer = panel.writer()
        #expect(writer.setLevel(0.4, of: Self.display))
        #expect(panel.levels == [0.4])
        #expect(panel.writes.first?.display == Self.display)
        #expect(!writer.hasPendingWrite)
    }

    @Test
    func `a drag is coalesced to one write per slot, latest value wins`() {
        let panel = FakePanel()
        let writer = panel.writer()
        writer.setLevel(0.40, of: Self.display)
        panel.now += 0.005
        writer.setLevel(0.41, of: Self.display)
        panel.now += 0.005
        writer.setLevel(0.42, of: Self.display)
        #expect(panel.levels == [0.40])
        #expect(writer.hasPendingWrite)

        // Too early: still waiting.
        writer.flushIfDue()
        #expect(panel.levels == [0.40])

        panel.now += 1.0 / 30
        writer.flushIfDue()
        #expect(panel.levels == [0.40, 0.42])
        #expect(!writer.hasPendingWrite)
    }

    @Test
    func `levels a slot apart are each written`() {
        let panel = FakePanel()
        let writer = panel.writer()
        for level in [0.2, 0.3, 0.4] {
            writer.setLevel(level, of: Self.display)
            panel.now += 0.1
        }
        #expect(panel.levels == [0.2, 0.3, 0.4])
    }

    @Test
    func `a read matching a recent write is its echo`() {
        let panel = FakePanel()
        let writer = panel.writer()
        #expect(!writer.isEcho(0.6))
        writer.setLevel(0.6, of: Self.display)
        panel.now += 0.1
        #expect(writer.isEcho(0.6))
        #expect(writer.isEcho(0.6001))
        #expect(!writer.isEcho(0.8))
        panel.now += 5
        #expect(!writer.isEcho(0.6))
    }

    @Test
    func `NaN is refused and writes nothing`() {
        let panel = FakePanel()
        let writer = panel.writer()
        #expect(!writer.setLevel(.nan, of: Self.display))
        #expect(panel.writes.isEmpty)
        #expect(!writer.hasPendingWrite)
        #expect(!writer.isEcho(.nan))
    }

    @Test
    func `levels are clamped to 0…1`() {
        let panel = FakePanel()
        let writer = panel.writer()
        writer.setLevel(1.7, of: Self.display)
        panel.now += 0.1
        writer.setLevel(-0.3, of: Self.display)
        panel.now += 0.1
        writer.setLevel(.infinity, of: Self.display)
        #expect(panel.levels == [1, 0, 1])
    }

    @Test
    func `nothing is written when the display can't take it`() {
        let panel = FakePanel()
        panel.writable = false
        let writer = panel.writer()
        #expect(!writer.setLevel(0.5, of: Self.display))
        #expect(panel.writes.isEmpty)

        let missing = DisplayServicesBrightnessWriter(setter: nil, clock: { 0 })
        #expect(!missing.setLevel(0.5, of: Self.display))
        #expect(!missing.isEcho(0.5))
    }

    @Test
    func `a pending level is dropped when the display goes away before its slot`() {
        let panel = FakePanel()
        let writer = panel.writer()
        writer.setLevel(0.3, of: Self.display)
        panel.now += 0.01
        writer.setLevel(0.5, of: Self.display)
        panel.writable = false  // Lid closed or Desk Mode on.
        panel.now += 0.1
        writer.flushIfDue()
        #expect(panel.levels == [0.3])
        #expect(!writer.hasPendingWrite)
    }

    @Test
    func `a cancelled level is never written, and the next one is`() {
        let panel = FakePanel()
        let writer = panel.writer()
        writer.setLevel(0.3, of: Self.display)
        panel.now += 0.01
        writer.setLevel(0.5, of: Self.display)
        #expect(writer.hasPendingWrite)

        // Desk Mode starts switching: the waiting 0.5 must not reach the panel.
        writer.cancelPending()
        #expect(!writer.hasPendingWrite)
        panel.now += 0.1
        writer.flushIfDue()
        #expect(panel.levels == [0.3])

        // A later level goes out as usual, at once or in its slot.
        writer.setLevel(0.6, of: Self.display)
        #expect(panel.levels == [0.3, 0.6])
        panel.now += 0.01
        writer.setLevel(0.7, of: Self.display)
        #expect(writer.hasPendingWrite)
        panel.now += 0.1
        writer.flushIfDue()
        #expect(panel.levels == [0.3, 0.6, 0.7])
        #expect(!writer.hasPendingWrite)
    }

    @Test
    func `cancelling with nothing waiting changes nothing`() {
        let panel = FakePanel()
        let writer = panel.writer()
        writer.cancelPending()
        #expect(writer.setLevel(0.4, of: Self.display))
        #expect(panel.levels == [0.4])
        #expect(writer.isEcho(0.4))
    }
}
