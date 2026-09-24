import LidlessCore
import Testing
@testable import Lidless

@MainActor
struct StatusSegmentTextTests {
    @Test func `desk mode with one external reads as one display`() {
        let segments = StatusLine.segments(lid: .open, externalCount: 1, builtInLit: false, power: .adapter)
        #expect(segments == [.lidOpen, .builtInOff, .displayCount(1)])
        #expect(StatusSegment.displayCount(1).localizedText.hasSuffix(" display"))
    }

    // Only the noun is checked so the test doesn't depend on the host locale's digits.
    @Test(arguments: [(1, " display"), (2, " displays"), (3, " displays")])
    func `display count uses the catalog's plural forms`(count: Int, noun: String) {
        #expect(StatusSegment.displayCount(count).localizedText.hasSuffix(noun))
    }
}
