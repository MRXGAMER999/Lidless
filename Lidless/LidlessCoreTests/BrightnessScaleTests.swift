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

    /// The Phase 1 readouts, which the approved popover renders were made with.
    static func linearNits(_ scale: BrightnessScale, at p: Double) -> Double {
        p <= 100 ? p / 100 * scale.normalMaxNits : scale.normalMaxNits + (p - 100) / 50 * (scale.ceilingNits - scale.normalMaxNits)
    }

    @Test(arguments: [
        BrightnessScale(normalMaxNits: 500, ceilingNits: 1000),
        BrightnessScale(normalMaxNits: 600, ceilingNits: 1000),
        BrightnessScale(normalMaxNits: 600, ceilingNits: 600),
    ], 0...150)
    func `without a curve readouts match the linear formula`(scale: BrightnessScale, position: Int) {
        let p = Double(position)
        let nits = Self.linearNits(scale, at: scale.clamp(p))
        #expect(scale.nits(p) == nits)
        #expect(scale.displayPercent(p) == Int((nits / scale.normalMaxNits * 100).rounded()))
        #expect(scale.displayNits(p) == Int((nits / 10).rounded()) * 10)
    }
}

struct BrightnessScaleCurveTests {
    let panel = BrightnessScale(panel: DisplayFixtures.panel, canBoost: true)
    let linear = BrightnessScale(normalMaxNits: 600, ceilingNits: 1000)

    /// Control Center at 51% on this Mac.
    @Test func `the curve puts Control Center's 51 percent at about 144 nits`() {
        let position = panel.position(nativeLevel: 0.51017)
        #expect(position.isApproximately(51.017))
        #expect(panel.nits(position).isApproximately(144.2, tolerance: 0.1))
        #expect(panel.displayPercent(position) == 51)
        #expect(panel.displayNits(position) == 140)
    }

    @Test func `the curve ends on normal max`() {
        #expect(panel.nits(0) == 0)
        #expect(panel.nits(50).isApproximately(140))
        #expect(panel.nits(100) == 600)
    }

    @Test func `a curve is scaled to the normal maximum`() {
        let scale = BrightnessScale(normalMaxNits: 500, ceilingNits: 1000, curve: panel.curve)
        #expect(scale.nits(100) == 500)
        #expect(scale.nits(50).isApproximately(140.0 / 600 * 500))
    }

    @Test(arguments: [0, 12.5, 50, 51.017, 99.9, 100])
    func `percent is the slider position up to 100`(position: Double) {
        #expect(panel.percent(position) == position)
    }

    @Test(arguments: [100.0, 101, 125, 130, 150])
    func `the boost range is unchanged by a curve`(position: Double) {
        #expect(panel.nits(position) == linear.nits(position))
        #expect(panel.percent(position).isApproximately(linear.percent(position)))
        #expect(panel.boostFactor(position) == linear.boostFactor(position))
        #expect(panel.displayPercent(position) == linear.displayPercent(position))
    }

    @Test func `allowing boost keeps the curve`() {
        #expect(panel.allowingBoost(true) == panel)
        let limited = panel.allowingBoost(false)
        #expect(limited.curve == panel.curve)
        #expect(!limited.canBoost)
    }

    @Test(arguments: [
        (DisplayFixtures.panel, true, nil, 600.0, 1000.0, true),
        (DisplayFixtures.panel, false, nil, 600, 600, true),
        (DisplayFixtures.panel, true, 800, 600, 800, true),
        // The setting can't push white past the panel's outdoor maximum.
        (DisplayFixtures.panel, true, 2000, 600, 1000, true),
        (DisplayFixtures.panel, true, 400, 600, 600, true),
        (PanelBrightnessInfo(userMaxNits: 600), true, nil, 600, 1000, false),
        (PanelBrightnessInfo(), true, nil, 500, 1000, false),
    ] as [(PanelBrightnessInfo, Bool, Double?, Double, Double, Bool)])
    func `the live panel scale`(info: PanelBrightnessInfo, canBoost: Bool, ceilingSetting: Double?, normal: Double, ceiling: Double, hasCurve: Bool) {
        let scale = BrightnessScale(panel: info, canBoost: canBoost, ceilingSetting: ceilingSetting)
        #expect(scale.normalMaxNits == normal)
        #expect(scale.ceilingNits == ceiling)
        #expect((scale.curve != nil) == hasCurve)
    }

    @Test func `fallbacks are 500 and 1000 nits`() {
        #expect(BrightnessScale.fallbackNormalMaxNits == 500)
        #expect(BrightnessScale.fallbackCeilingNits == 1000)
    }
}

extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 1e-9) -> Bool {
        abs(self - other) <= tolerance
    }
}
