import Foundation

/// Maps the popover's built-in brightness slider to brightness levels.
///
/// The slider runs from 0 to 150. The first two thirds (0...100) are the
/// panel's normal range; the last third (100...150) is Boost, which lifts
/// white above the normal maximum up to `ceilingNits`.
public struct BrightnessScale: Sendable, Equatable {
    /// Slider position where Boost starts (the line drawn on the track).
    public static let normalLimit = 100.0
    /// Slider position at the far right of the track.
    public static let sliderMax = 150.0
    /// Where the Boost line sits along the track, as a fraction of its width.
    public static let boostLineFraction = normalLimit / sliderMax

    /// Brightest SDR white the panel shows without Boost, in nits. At least 1.
    public let normalMaxNits: Double
    /// Brightest white Boost may reach, in nits (Settings › Brightness). At least `normalMaxNits`.
    public let ceilingNits: Double
    /// The panel's own slider-to-nits curve for the normal range; linear when nil.
    public let curve: PanelBrightnessCurve?

    public init(normalMaxNits: Double, ceilingNits: Double, curve: PanelBrightnessCurve? = nil) {
        // A failed panel read (0, NaN, infinity) must not reach the readouts:
        // Int(_:) traps on a NaN or infinite percentage.
        self.normalMaxNits = normalMaxNits.isFinite ? max(1, normalMaxNits) : 1
        self.ceilingNits = ceilingNits.isFinite ? max(self.normalMaxNits, ceilingNits) : self.normalMaxNits
        self.curve = curve
    }

    /// Whether this scale has any room above normal brightness.
    public var canBoost: Bool { ceilingNits > normalMaxNits }

    /// This scale, or the same scale with no Boost range when Boost isn't allowed.
    public func allowingBoost(_ allowed: Bool) -> BrightnessScale {
        allowed ? self : BrightnessScale(normalMaxNits: normalMaxNits, ceilingNits: normalMaxNits, curve: curve)
    }

    /// Clamps a slider position into 0...150, or 0...100 when there is no room to boost.
    public func clamp(_ position: Double) -> Double {
        let upper = canBoost ? Self.sliderMax : Self.normalLimit
        return min(max(position, 0), upper)
    }

    public func isBoosted(_ position: Double) -> Bool {
        clamp(position) > Self.normalLimit
    }

    /// How far into the Boost range the slider is, 0...1.
    public func boostProgress(_ position: Double) -> Double {
        let p = clamp(position)
        guard p > Self.normalLimit else { return 0 }
        return (p - Self.normalLimit) / (Self.sliderMax - Self.normalLimit)
    }

    /// Native panel brightness for the normal range, 0...1. Stays at 1 while boosted.
    public func nativeLevel(_ position: Double) -> Double {
        min(clamp(position), Self.normalLimit) / Self.normalLimit
    }

    /// Approximate white level in nits.
    public func nits(_ position: Double) -> Double {
        let p = clamp(position)
        if p <= Self.normalLimit {
            let level = p / Self.normalLimit
            // Scaled so the end of the curve lands exactly on normalMaxNits.
            guard let curve else { return level * normalMaxNits }
            return curve.nits(atLevel: level) / curve.maxNits * normalMaxNits
        }
        return normalMaxNits + boostProgress(p) * (ceilingNits - normalMaxNits)
    }

    /// Brightness as a percentage: the slider position up to 100, so it matches
    /// Control Center, then white above normal maximum while boosted.
    public func percent(_ position: Double) -> Double {
        let p = clamp(position)
        return p <= Self.normalLimit ? p : nits(p) / normalMaxNits * 100
    }

    /// Multiplier Boost applies on top of full native brightness (1 when not boosted).
    public func boostFactor(_ position: Double) -> Double {
        isBoosted(position) ? nits(position) / normalMaxNits : 1
    }

    /// Largest percentage the slider can reach.
    public var maxPercent: Double { ceilingNits / normalMaxNits * 100 }

    /// Slider position for a native level (0...1) with no Boost.
    public func position(nativeLevel: Double) -> Double {
        min(max(nativeLevel, 0), 1) * Self.normalLimit
    }

    /// Slider position for a Boost factor (1 means full native brightness, no Boost).
    public func position(boostFactor: Double) -> Double {
        guard canBoost, boostFactor > 1 else { return Self.normalLimit }
        let target = min(boostFactor * normalMaxNits, ceilingNits)
        let progress = (target - normalMaxNits) / (ceilingNits - normalMaxNits)
        return Self.normalLimit + progress * (Self.sliderMax - Self.normalLimit)
    }
}

// MARK: - Slider track and readouts

extension BrightnessScale {
    /// Slider steps are whole positions, like the canvas `<input step="1">`.
    public static let step = 1.0

    /// Positions the thumb can reach. Without a Boost range the whole track is normal brightness.
    public var travel: ClosedRange<Double> {
        0...(canBoost ? Self.sliderMax : Self.normalLimit)
    }

    /// Where the Boost line is drawn along the track, or nil when there is no Boost range.
    public var boostLineTrackFraction: Double? {
        canBoost ? Self.boostLineFraction : nil
    }

    /// Where the thumb sits along the track, from 0 to 1.
    public func trackFraction(_ position: Double) -> Double {
        SliderMath.fraction(of: clamp(position), in: travel)
    }

    /// The position under a point `fraction` along the track.
    public func position(atTrackFraction fraction: Double) -> Double {
        SliderMath.value(atFraction: fraction, in: travel, step: Self.step)
    }

    /// `position` moved by `delta` steps' worth, kept on the track.
    public func position(_ position: Double, nudgedBy delta: Double) -> Double {
        SliderMath.nudge(clamp(position), by: delta, in: travel, step: Self.step)
    }

    /// The readout percentage: "70%", "160%".
    public func displayPercent(_ position: Double) -> Int {
        Int(percent(position).rounded())
    }

    /// The "≈ N nits" figure, rounded to the nearest 10 because it is an estimate.
    public func displayNits(_ position: Double) -> Int {
        Int((nits(position) / 10).rounded()) * 10
    }
}

// MARK: - Live panel

extension BrightnessScale {
    /// Normal maximum when the panel doesn't publish one.
    public static let fallbackNormalMaxNits = 500.0
    /// Boost ceiling when the panel doesn't publish its outdoor maximum.
    public static let fallbackCeilingNits = 1000.0

    /// The scale for this Mac's built-in panel.
    ///
    /// - Parameters:
    ///   - panel: Constants read from the device tree.
    ///   - canBoost: The panel is XDR and no reference preset locks it.
    ///   - ceilingSetting: The stored Settings › Brightness ceiling in nits
    ///     (`BoostSettings.ceilingNits`); nil for the panel's own limit. It goes
    ///     through `BoostSettings.effectiveCeiling(_:normalMaxNits:)`, like the
    ///     Settings slider, so a ceiling at or below this panel's normal maximum
    ///     is raised to the first step above it, and a panel with no room above
    ///     its normal maximum gets no Boost range.
    public init(panel: PanelBrightnessInfo, canBoost: Bool, ceilingSetting: Double? = nil) {
        let read = panel.userMaxNits ?? Self.fallbackNormalMaxNits
        // The same normal maximum the designated initializer keeps.
        let normal = read.isFinite ? max(1, read) : 1
        let panelLimit = panel.outdoorMaxNits ?? Self.fallbackCeilingNits
        let ceiling: Double
        if let ceilingSetting {
            ceiling = BoostSettings.effectiveCeiling(ceilingSetting, normalMaxNits: normal).map { min($0, panelLimit) } ?? normal
        } else {
            ceiling = panelLimit
        }
        self.init(normalMaxNits: normal, ceilingNits: canBoost ? ceiling : normal, curve: panel.curve)
    }
}
