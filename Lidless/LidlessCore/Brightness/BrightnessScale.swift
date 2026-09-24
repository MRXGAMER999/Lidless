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

    public init(normalMaxNits: Double, ceilingNits: Double) {
        // A failed panel read (0, NaN, infinity) must not reach the readouts:
        // Int(_:) traps on a NaN or infinite percentage.
        self.normalMaxNits = normalMaxNits.isFinite ? max(1, normalMaxNits) : 1
        self.ceilingNits = ceilingNits.isFinite ? max(self.normalMaxNits, ceilingNits) : self.normalMaxNits
    }

    /// Whether this scale has any room above normal brightness.
    public var canBoost: Bool { ceilingNits > normalMaxNits }

    /// This scale, or the same scale with no Boost range when Boost isn't allowed.
    public func allowingBoost(_ allowed: Bool) -> BrightnessScale {
        allowed ? self : BrightnessScale(normalMaxNits: normalMaxNits, ceilingNits: normalMaxNits)
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
            return p / Self.normalLimit * normalMaxNits
        }
        return normalMaxNits + boostProgress(p) * (ceilingNits - normalMaxNits)
    }

    /// Brightness as a percentage of normal maximum: 0...100, then above 100 while boosted.
    public func percent(_ position: Double) -> Double {
        nits(position) / normalMaxNits * 100
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
