import Testing
@testable import LidlessCore

struct MenuBarIconStateTests {
    @Test(arguments: [
        (false, false, MenuBarIconState.normal),
        (false, true, .boost),
        (true, false, .deskMode),
        (true, true, .deskMode),
    ])
    func `desk mode wins over boost`(desk: Bool, boosted: Bool, expected: MenuBarIconState) {
        #expect(MenuBarIconState.state(desk: desk, boosted: boosted, iconShowsState: true) == expected)
    }

    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func `always normal when the icon doesn't show state`(desk: Bool, boosted: Bool) {
        #expect(MenuBarIconState.state(desk: desk, boosted: boosted, iconShowsState: false) == .normal)
    }
}

struct BrightnessScaleBoostAllowedTests {
    let scale = BrightnessScale(normalMaxNits: 600, ceilingNits: 1000)

    @Test func `allowed keeps the boost range`() {
        #expect(scale.allowingBoost(true) == scale)
        #expect(scale.allowingBoost(true).isBoosted(130))
    }

    @Test func `not allowed removes the boost range`() {
        let limited = scale.allowingBoost(false)
        #expect(!limited.canBoost)
        #expect(!limited.isBoosted(130))
        #expect(limited.normalMaxNits == 600)
    }
}
