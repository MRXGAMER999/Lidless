import Testing
@testable import LidlessCore

struct SliderMathTests {
    @Test(arguments: [
        (0.0, 0.0),
        (0.5, 0.5),
        (1.0, 1.0),
        (-0.2, 0.0),
        (1.7, 1.0),
    ])
    func `fraction is clamped to the track`(value: Double, expected: Double) {
        #expect(SliderMath.fraction(of: value, in: 0...1).isApproximately(expected))
    }

    @Test func `an empty range sits at the start`() {
        #expect(SliderMath.fraction(of: 5, in: 5...5) == 0)
    }

    @Test(arguments: [
        (0.0, 0.0),
        (0.334, 0.33),
        (0.336, 0.34),
        (1.0, 1.0),
        (-3.0, 0.0),
        (2.0, 1.0),
    ])
    func `value snaps to the step and stays in range`(fraction: Double, expected: Double) {
        #expect(SliderMath.value(atFraction: fraction, in: 0...1, step: 0.01).isApproximately(expected, tolerance: 1e-9))
    }

    @Test(arguments: [
        (0.98, 0.05, 1.0),
        (0.02, -0.05, 0.0),
        (0.5, 0.05, 0.55),
    ])
    func `nudging stops at the ends`(start: Double, delta: Double, expected: Double) {
        #expect(SliderMath.nudge(start, by: delta, in: 0...1, step: 0.01).isApproximately(expected))
    }

    @Test(arguments: [(0.8, 80), (0.555, 56), (0.0, 0), (1.2, 100), (-1.0, 0)])
    func `levels read as whole percentages`(level: Double, percent: Int) {
        #expect(SliderMath.percent(level: level) == percent)
    }
}

struct BrightnessTrackTests {
    let canvas = BrightnessScale(normalMaxNits: 500, ceilingNits: 1000)

    @Test func `the canvas thumb positions`() {
        // Main.dc.html: 70 of 150 → 46.667%; Popover-Boost: 130 → 86.667%.
        #expect(canvas.trackFraction(70).isApproximately(70.0 / 150.0))
        #expect(canvas.trackFraction(130).isApproximately(130.0 / 150.0))
        #expect(canvas.boostLineTrackFraction == BrightnessScale.boostLineFraction)
    }

    @Test(arguments: [(0.0, 0.0), (0.5, 75.0), (0.4671, 70.0), (1.0, 150.0), (1.3, 150.0), (-0.1, 0.0)])
    func `a point on the track gives a whole position`(fraction: Double, position: Double) {
        #expect(canvas.position(atTrackFraction: fraction) == position)
    }

    @Test func `without boost the whole track is normal brightness`() {
        let noBoost = canvas.allowingBoost(false)
        #expect(noBoost.travel == 0...100)
        #expect(noBoost.boostLineTrackFraction == nil)
        #expect(noBoost.trackFraction(70).isApproximately(0.7))
        #expect(noBoost.trackFraction(130) == 1)
        #expect(noBoost.position(atTrackFraction: 1) == 100)
    }

    @Test(arguments: [
        (true, 148.0, 5.0, 150.0),
        (true, 3.0, -5.0, 0.0),
        (true, 70.0, 5.0, 75.0),
        (false, 98.0, 5.0, 100.0),
    ])
    func `keyboard nudges stay on the track`(boostAllowed: Bool, start: Double, delta: Double, expected: Double) {
        #expect(canvas.allowingBoost(boostAllowed).position(start, nudgedBy: delta) == expected)
    }

    @Test(arguments: [
        (70.0, 70, 350),
        (130.0, 160, 800),
        (150.0, 200, 1000),
        (0.0, 0, 0),
    ])
    func `readouts match the canvas`(position: Double, percent: Int, nits: Int) {
        #expect(canvas.displayPercent(position) == percent)
        #expect(canvas.displayNits(position) == nits)
    }

    @Test func `nits are rounded to the nearest ten`() {
        let panel = BrightnessScale(normalMaxNits: 600, ceilingNits: 1000)
        // 600 × 0.33 = 198 → 200; boosted 101 → 608 → 610.
        #expect(panel.displayNits(33) == 200)
        #expect(panel.displayNits(101) == 610)
        #expect(panel.displayPercent(150) == 167)
    }
}
