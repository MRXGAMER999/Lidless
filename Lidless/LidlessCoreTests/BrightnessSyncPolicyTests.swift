import Testing
@testable import LidlessCore

struct BrightnessSyncPolicyTests {
    let policy = BrightnessSyncPolicy()
    let scale = BrightnessScale(panel: DisplayFixtures.panel, canBoost: true)

    func position(level: Double, current: Double, lastUserEdit: Double? = nil, now: Double = 100) -> Double? {
        policy.position(for: BrightnessLevelReading(level: level), scale: scale, current: current, lastUserEdit: lastUserEdit, now: now)
    }

    @Test func `defaults are a twentieth of a position and two seconds`() {
        #expect(policy == BrightnessSyncPolicy(minimumChange: 0.05, userHold: 2))
    }

    @Test func `a reading far from the slider moves it`() throws {
        #expect(try #require(position(level: 0.51017, current: 70)).isApproximately(51.017))
    }

    @Test(arguments: [(0.5004, 50.0), (0.5, 50.049), (0.7, 70.0)])
    func `a reading within a twentieth of a position is ignored`(level: Double, current: Double) {
        #expect(position(level: level, current: current) == nil)
    }

    /// Reads never fight the user's hand.
    @Test(arguments: [100.0, 101.0, 101.99])
    func `readings are ignored while the user holds the slider`(now: Double) {
        #expect(position(level: 0.3, current: 70, lastUserEdit: 100, now: now) == nil)
    }

    @Test(arguments: [102.0, 102.001, 500.0])
    func `readings apply once the hold is over`(now: Double) throws {
        #expect(try #require(position(level: 0.3, current: 70, lastUserEdit: 100, now: now)).isApproximately(30))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func `an unreadable level is ignored`(level: Double) {
        #expect(position(level: level, current: 50) == nil)
    }

    @Test func `a level above 1 lands on the boost line`() {
        #expect(position(level: 1.3, current: 50) == 100)
    }

    /// Boost is store-only until Phase 4, so a boosted slider follows the panel back.
    @Test func `a boosted slider snaps back after the hold`() {
        #expect(position(level: 1, current: 130, lastUserEdit: 90) == 100)
        #expect(position(level: 1, current: 130, lastUserEdit: 99) == nil)
    }

    @Test func `the reading's extra fields don't change the result`() throws {
        let reading = BrightnessLevelReading(level: 0.8, linear: 0.4, autoBrightness: true)
        let result = try #require(policy.position(for: reading, scale: scale, current: 20, lastUserEdit: nil, now: 0))
        #expect(result.isApproximately(80))
    }
}
