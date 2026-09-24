import Testing
@testable import LidlessCore

struct BrightnessScaleTests {
    /// The design canvas uses a 500-nit normal maximum and a 1,000-nit ceiling.
    let canvas = BrightnessScale(normalMaxNits: 500, ceilingNits: 1000)

    @Test(arguments: [
        (70.0, 70.0, 350.0),
        (100.0, 100.0, 500.0),
        (130.0, 160.0, 800.0),
        (150.0, 200.0, 1000.0),
    ])
    func `matches the canvas slider script`(position: Double, percent: Double, nits: Double) {
        #expect(canvas.percent(position).isApproximately(percent))
        #expect(canvas.nits(position).isApproximately(nits))
    }

    @Test func `boost starts strictly past the line`() {
        #expect(!canvas.isBoosted(100))
        #expect(canvas.isBoosted(101))
        #expect(canvas.boostFactor(100) == 1)
        #expect(canvas.boostFactor(150).isApproximately(2))
    }

    @Test func `boost line sits two thirds along the track`() {
        #expect(BrightnessScale.boostLineFraction.isApproximately(2.0 / 3.0))
    }

    @Test func `native level stays at full while boosted`() {
        #expect(canvas.nativeLevel(50).isApproximately(0.5))
        #expect(canvas.nativeLevel(140) == 1)
    }

    @Test(arguments: [(-10.0, 0.0), (400.0, 150.0), (70.0, 70.0)])
    func `positions outside the track are clamped`(position: Double, expected: Double) {
        #expect(canvas.clamp(position) == expected)
    }

    @Test(arguments: [(-0.5, 0.0), (0.0, 0.0), (0.7, 70.0), (1.0, 100.0), (1.5, 100.0)])
    func `native level maps onto the normal range`(level: Double, position: Double) {
        #expect(canvas.position(nativeLevel: level).isApproximately(position))
    }

    @Test(arguments: [(90.0, 0.0), (100.0, 0.0), (125.0, 0.5), (150.0, 1.0), (200.0, 1.0)])
    func `boost progress runs across the boost range`(position: Double, progress: Double) {
        #expect(canvas.boostProgress(position).isApproximately(progress))
    }

    @Test func `max percent is the ceiling over normal max`() {
        #expect(canvas.maxPercent.isApproximately(200))
        #expect(BrightnessScale(normalMaxNits: 600, ceilingNits: 1000).maxPercent.isApproximately(1000.0 / 6.0))
    }

    @Test func `no boost range when the ceiling is at normal max`() {
        let flat = BrightnessScale(normalMaxNits: 1000, ceilingNits: 1000)
        #expect(!flat.canBoost)
        #expect(flat.clamp(140) == 100)
        #expect(!flat.isBoosted(140))
        #expect(flat.maxPercent == 100)
    }

    @Test func `ceiling below normal max is raised to normal max`() {
        let scale = BrightnessScale(normalMaxNits: 600, ceilingNits: 400)
        #expect(scale.ceilingNits == 600)
    }

    /// A failed panel read must not reach the readouts: Int(_:) traps on NaN or infinity.
    @Test(arguments: [
        (0.0, 1000.0, 1.0, 1000.0),
        (-5.0, 1000.0, 1.0, 1000.0),
        (Double.nan, 1000.0, 1.0, 1000.0),
        (Double.infinity, 1000.0, 1.0, 1000.0),
        (600.0, Double.nan, 600.0, 600.0),
        (600.0, Double.infinity, 600.0, 600.0),
    ])
    func `unreadable nit values fall back to finite ones`(normal: Double, ceiling: Double, expectedNormal: Double, expectedCeiling: Double) {
        let scale = BrightnessScale(normalMaxNits: normal, ceilingNits: ceiling)
        #expect(scale.normalMaxNits == expectedNormal)
        #expect(scale.ceilingNits == expectedCeiling)
        for position in [0.0, 50, 100, 150] {
            #expect(scale.percent(position).isFinite)
            #expect(scale.nits(position).isFinite)
            #expect(scale.displayPercent(position) >= 0)
            #expect(scale.displayNits(position) >= 0)
        }
    }

    @Test(arguments: [1.0, 1.2, 1.5, 1000.0 / 600.0])
    func `boost factor round-trips through the slider position`(factor: Double) {
        let scale = BrightnessScale(normalMaxNits: 600, ceilingNits: 1000)
        let position = scale.position(boostFactor: factor)
        #expect(scale.boostFactor(position).isApproximately(factor))
    }

    @Test func `boost factor beyond the ceiling stops at the end of the track`() {
        let scale = BrightnessScale(normalMaxNits: 600, ceilingNits: 1000)
        #expect(scale.position(boostFactor: 3) == 150)
    }
}

extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 1e-9) -> Bool {
        abs(self - other) <= tolerance
    }
}
