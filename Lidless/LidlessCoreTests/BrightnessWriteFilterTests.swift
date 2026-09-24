import Testing
@testable import LidlessCore

struct BrightnessWriteFilterTests {
    let interval = 1.0 / 30

    @Test func `defaults are 30 Hz with a one second echo window`() {
        #expect(BrightnessWriteFilter() == BrightnessWriteFilter(minInterval: 1.0 / 30, echoWindow: 1, tolerance: 0.01))
    }

    @Test func `the first write goes out at once`() {
        var filter = BrightnessWriteFilter()
        #expect(filter.submit(0.5, now: 10) == 0.5)
        #expect(filter.pending == nil)
        #expect(filter.nextFlush(now: 10) == nil)
    }

    @Test func `writes inside the interval wait and the latest wins`() throws {
        var filter = BrightnessWriteFilter()
        _ = filter.submit(0.5, now: 10)
        #expect(filter.submit(0.6, now: 10.01) == nil)
        #expect(filter.submit(0.7, now: 10.02) == nil)
        #expect(filter.pending == 0.7)
        let due = try #require(filter.nextFlush(now: 10.02))
        #expect(due.isApproximately(10 + interval))
        #expect(filter.flush(now: 10.025) == nil)
        #expect(filter.flush(now: due) == 0.7)
        #expect(filter.pending == nil)
        #expect(filter.flush(now: due + 1) == nil)
    }

    /// A drag at 60 Hz reaches the panel at 30 Hz, always ending on the final value.
    @Test func `a fast drag is coalesced and ends on its last value`() {
        var filter = BrightnessWriteFilter()
        var written: [Double] = []
        for step in 0...30 {
            let now = 100 + Double(step) / 60
            if let due = filter.nextFlush(now: now), due <= now, let level = filter.flush(now: now) { written.append(level) }
            if let level = filter.submit(Double(step) / 30, now: now) { written.append(level) }
        }
        if let due = filter.nextFlush(now: 101), let level = filter.flush(now: due) { written.append(level) }
        #expect(written.count <= 17)
        #expect(written.first == 0)
        #expect(written.last == 1)
        #expect(filter.pending == nil)
    }

    @Test func `a write after the interval goes out at once and clears the queue`() {
        var filter = BrightnessWriteFilter()
        _ = filter.submit(0.5, now: 10)
        _ = filter.submit(0.6, now: 10.01)
        #expect(filter.submit(0.8, now: 10.1) == 0.8)
        #expect(filter.pending == nil)
    }

    /// Timers can fire a hair early by our clock; the final value must not be stranded.
    @Test func `a flush a hair before the slot still writes`() {
        var filter = BrightnessWriteFilter()
        _ = filter.submit(0.5, now: 10)
        _ = filter.submit(0.6, now: 10.01)
        #expect(filter.flush(now: 10 + interval - 0.0005) == 0.6)
    }

    @Test func `the next slot never lies in the past`() {
        var filter = BrightnessWriteFilter()
        _ = filter.submit(0.5, now: 10)
        _ = filter.submit(0.6, now: 10.01)
        #expect(filter.nextFlush(now: 20) == 20)
    }

    @Test(arguments: [(-0.2, 0.0), (1.4, 1.0), (0.25, 0.25)])
    func `levels are clamped to 0 through 1`(level: Double, expected: Double) {
        var filter = BrightnessWriteFilter()
        #expect(filter.submit(level, now: 0) == expected)
    }

    @Test func `a NaN level is dropped`() {
        var filter = BrightnessWriteFilter()
        #expect(filter.submit(.nan, now: 0) == nil)
        #expect(filter.pending == nil)
        #expect(filter.submit(0.4, now: 0) == 0.4)
    }

    // MARK: Echoes

    @Test func `a read matching a recent write is an echo`() {
        var filter = BrightnessWriteFilter()
        _ = filter.submit(0.75, now: 10)
        #expect(filter.isEcho(0.7499999, now: 10))
        #expect(filter.isEcho(0.755, now: 10.5))
        #expect(filter.isEcho(0.75, now: 11))
    }

    @Test func `reads outside the tolerance or the window are real changes`() {
        var filter = BrightnessWriteFilter()
        _ = filter.submit(0.75, now: 10)
        #expect(!filter.isEcho(0.7, now: 10.1))
        #expect(!filter.isEcho(0.75, now: 11.01))
        #expect(!filter.isEcho(0.75, now: 9.9))
        #expect(!filter.isEcho(.nan, now: 10.1))
    }

    @Test func `nothing is an echo before any write`() {
        #expect(!BrightnessWriteFilter().isEcho(0.5, now: 0))
    }

    /// While dragging, the callback for one write can arrive after the next went out.
    @Test func `every recent write can echo, not only the last`() {
        var filter = BrightnessWriteFilter()
        _ = filter.submit(0.4, now: 10)
        _ = filter.submit(0.5, now: 10.05)
        _ = filter.submit(0.6, now: 10.1)
        #expect(filter.isEcho(0.4, now: 10.2))
        #expect(filter.isEcho(0.5, now: 10.2))
        #expect(!filter.isEcho(0.4, now: 11.05))
        #expect(filter.isEcho(0.6, now: 11.05))
    }

    /// Only values that reached the panel echo; a queued one hasn't.
    @Test func `a pending value is not an echo until written`() {
        var filter = BrightnessWriteFilter()
        _ = filter.submit(0.2, now: 10)
        _ = filter.submit(0.9, now: 10.01)
        #expect(!filter.isEcho(0.9, now: 10.02))
        _ = filter.flush(now: 10.04)
        #expect(filter.isEcho(0.9, now: 10.05))
    }

    @Test func `old writes are forgotten`() {
        var filter = BrightnessWriteFilter()
        _ = filter.submit(0.1, now: 0)
        _ = filter.submit(0.2, now: 5)
        #expect(!filter.isEcho(0.1, now: 5))
        #expect(filter == {
            var fresh = BrightnessWriteFilter()
            _ = fresh.submit(0.2, now: 5)
            return fresh
        }())
    }
}
