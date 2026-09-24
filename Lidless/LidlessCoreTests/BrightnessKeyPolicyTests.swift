import Testing
@testable import LidlessCore

struct BrightnessKeyPolicyTests {
    /// The design canvas: 500 nits normal, 1,000 nits ceiling.
    let scale = BrightnessScale(normalMaxNits: 500, ceilingNits: 1000)

    func position(_ key: BrightnessKeyPolicy.Key = .up, current: Double = 100, native: Double = 1, scale: BrightnessScale? = nil, keysIntoBoost: Bool = true) -> Double? {
        BrightnessKeyPolicy.position(after: key, current: current, nativeLevel: native, scale: scale ?? self.scale, keysIntoBoost: keysIntoBoost)
    }

    @Test func `eight presses cross the Boost range`() {
        #expect(BrightnessKeyPolicy.boostStep * 8 == BrightnessScale.sliderMax - BrightnessScale.normalLimit)
    }

    @Test func `up at full brightness steps into Boost`() {
        #expect(position(current: 100) == 106.25)
        #expect(position(current: 106.25) == 112.5)
    }

    @Test func `presses accumulate to the end of the scale and stop there`() {
        var current = 100.0
        for _ in 0..<12 { current = position(current: current) ?? current }
        #expect(current == BrightnessScale.sliderMax)
        #expect(position(current: 147) == BrightnessScale.sliderMax)
        #expect(position(current: 150) == BrightnessScale.sliderMax)
    }

    /// The store can lag the native level; Boost starts from the line, never below it.
    @Test(arguments: [91.75, 0, -5, .nan])
    func `a slider below the line starts from the line`(current: Double) {
        #expect(position(current: current) == 106.25)
    }

    /// The press that *arrives* at 100 % reads the level before it: 0.9175.
    @Test(arguments: [0.9175, 0.998, 0.5, 0, .nan])
    func `up below full brightness is macOS's`(native: Double) {
        #expect(position(native: native) == nil)
    }

    @Test(arguments: [0.999, 0.9995, 1.0])
    func `full brightness tolerates float noise`(native: Double) {
        #expect(position(native: native) == 106.25)
    }

    @Test(arguments: [100.0, 125.0, 150.0])
    func `down is always macOS's`(current: Double) {
        #expect(position(.down, current: current) == nil)
    }

    @Test func `nothing happens with the setting off`() {
        #expect(position(keysIntoBoost: false) == nil)
    }

    @Test func `nothing happens when the panel can't boost`() {
        #expect(position(scale: scale.allowingBoost(false)) == nil)
        #expect(position(scale: BrightnessScale(normalMaxNits: 600, ceilingNits: 600)) == nil)
    }
}
