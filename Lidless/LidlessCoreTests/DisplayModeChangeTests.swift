import Testing
@testable import LidlessCore

struct DisplayModeChangeTests {
    static let normal = DisplayModeInfo(modeID: 68, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 144)
    static let hiDPI = DisplayModeInfo(modeID: 108, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 144)
    static let panel = DisplayModeInfo(modeID: 66, width: 1800, height: 1169, pixelWidth: 3600, pixelHeight: 2338, refreshRate: 120)

    @Test func `an external that switches mode is reported`() {
        let changes = DisplayModeChange.changed(before: [1: Self.panel, 2: Self.normal], after: [2: Self.hiDPI])
        #expect(changes.count == 1)
        #expect(changes.first?.id == 2)
        #expect(changes.first?.from == Self.normal)
        #expect(changes.first?.to == Self.hiDPI)
    }

    @Test func `the built-in leaving or coming back is not a change`() {
        #expect(DisplayModeChange.changed(before: [1: Self.panel, 2: Self.normal], after: [2: Self.normal]).isEmpty)
        #expect(DisplayModeChange.changed(before: [2: Self.normal], after: [1: Self.panel, 2: Self.normal]).isEmpty)
    }

    @Test func `a refresh rate change alone counts`() {
        var slower = Self.normal
        slower.refreshRate = 60
        #expect(DisplayModeChange.changed(before: [2: Self.normal], after: [2: slower]).map(\.id) == [2])
    }

    @Test func `changes come in display ID order`() {
        let before: [UInt32: DisplayModeInfo] = [5: Self.normal, 3: Self.normal, 4: Self.normal]
        let after: [UInt32: DisplayModeInfo] = [5: Self.hiDPI, 3: Self.hiDPI, 4: Self.normal]
        #expect(DisplayModeChange.changed(before: before, after: after).map(\.id) == [3, 5])
    }

    @Test func `the summary names HiDPI modes`() {
        #expect(Self.hiDPI.summary == "1920×1080 (HiDPI) @ 144 Hz, mode 108")
        #expect(Self.normal.summary == "1920×1080 @ 144 Hz, mode 68")
    }
}
