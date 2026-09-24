import Foundation

/// Maps between a custom slider's value and a point along its track.
public enum SliderMath {
    /// Where `value` sits along a track that covers `range`, from 0 to 1.
    public static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// The value under a point `fraction` along the track, snapped to `step`.
    /// Points past either end give the end value.
    public static func value(atFraction fraction: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        let raw = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
        return snap(raw, in: range, step: step)
    }

    /// `value` moved by `delta`, snapped to `step` and kept inside `range`.
    public static func nudge(_ value: Double, by delta: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        snap(value + delta, in: range, step: step)
    }

    /// A 0...1 level as a whole percentage.
    public static func percent(level: Double) -> Int {
        Int((min(max(level, 0), 1) * 100).rounded())
    }

    private static func snap(_ value: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        let snapped = step > 0
            ? range.lowerBound + ((value - range.lowerBound) / step).rounded() * step
            : value
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}
