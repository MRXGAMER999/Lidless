import Foundation

/// The panel's slider-to-nits curve: nits at evenly spaced slider levels,
/// from the device tree's `backlight-marketing-table`. On this Mac it doubles
/// each step from 1 nit to 140 at half the slider, then rises to 600.
public struct PanelBrightnessCurve: Sendable, Equatable {
    /// Nits at slider levels 0, 1/(n-1), …, 1.
    public let stops: [Double]

    /// Nil unless there are at least two finite, non-negative, non-decreasing
    /// stops ending above 0.
    public init?(stops: [Double]) {
        guard stops.count >= 2,
              stops.allSatisfy({ $0.isFinite && $0 >= 0 }),
              zip(stops, stops.dropFirst()).allSatisfy({ $0 <= $1 }),
              let last = stops.last, last > 0
        else { return nil }
        self.stops = stops
    }

    /// From little-endian 16.16 fixed-point values, as the IORegistry stores them.
    public init?(fixed1616 data: Data) {
        guard data.count % 4 == 0, let values = FixedPoint.fixed1616Values(data) else { return nil }
        self.init(stops: values)
    }

    public var maxNits: Double { stops[stops.count - 1] }

    /// White level at a slider level, 0...1 (clamped; NaN reads as 0).
    public func nits(atLevel level: Double) -> Double {
        let clamped = min(max(level.isNaN ? 0 : level, 0), 1)
        let x = clamped * Double(stops.count - 1)
        let i = min(Int(x), stops.count - 2)
        let t = x - Double(i)
        let a = stops[i], b = stops[i + 1]
        // Exact at the top, so a scale built on this curve ends on its normal maximum.
        guard t < 1 else { return b }
        // The table doubles per step at the dark end: interpolate geometrically between lit stops.
        return a > 0 && b > 0 ? a * pow(b / a, t) : a + (b - a) * t
    }
}

/// The built-in panel's constants from the device tree node `IODeviceTree:/backlight`.
/// Keys are undocumented and vary by model; every field is nil when absent.
public struct PanelBrightnessInfo: Sendable, Equatable {
    /// Brightest SDR white the slider reaches (`user-accessible-max-nits`).
    public var userMaxNits: Double?
    /// Auto-brightness "outdoor" maximum (`aurora-maximum-nits`): the Boost ceiling.
    public var outdoorMaxNits: Double?
    /// HDR peak (`LmaxProduct`). Not a Boost ceiling.
    public var peakNits: Double?
    public var curve: PanelBrightnessCurve?

    /// Property names the reader fetches from the node.
    public enum Key {
        public static let userMaxNits = "user-accessible-max-nits"
        public static let outdoorMaxNits = "aurora-maximum-nits"
        public static let peakNits = "LmaxProduct"
        public static let curve = "backlight-marketing-table"
        public static let all = [userMaxNits, outdoorMaxNits, peakNits, curve]
    }

    public init(userMaxNits: Double? = nil, outdoorMaxNits: Double? = nil, peakNits: Double? = nil, curve: PanelBrightnessCurve? = nil) {
        self.userMaxNits = userMaxNits
        self.outdoorMaxNits = outdoorMaxNits
        self.peakNits = peakNits
        self.curve = curve
    }

    /// Decodes the raw `Data` properties. Most are 16.16 fixed point; the outdoor
    /// maximum is a float32. Zero or unreadable values count as absent.
    public init(backlightProperties properties: [String: Data]) {
        func positive(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        }
        userMaxNits = positive(properties[Key.userMaxNits].flatMap(FixedPoint.fixed1616))
        outdoorMaxNits = positive(properties[Key.outdoorMaxNits].flatMap(FixedPoint.float32))
        peakNits = positive(properties[Key.peakNits].flatMap(FixedPoint.fixed1616))
        curve = properties[Key.curve].flatMap(PanelBrightnessCurve.init(fixed1616:))
    }
}

/// Little-endian number formats used by device-tree properties.
enum FixedPoint {
    /// The first four bytes as unsigned 16.16 fixed point.
    static func fixed1616(_ data: Data) -> Double? {
        uint32(data, at: 0).map { Double($0) / 65536 }
    }

    /// Every four bytes as unsigned 16.16 fixed point.
    static func fixed1616Values(_ data: Data) -> [Double]? {
        guard data.count >= 4 else { return nil }
        return stride(from: 0, to: data.count - 3, by: 4).compactMap { uint32(data, at: $0).map { Double($0) / 65536 } }
    }

    /// The first four bytes as an IEEE 754 float.
    static func float32(_ data: Data) -> Double? {
        uint32(data, at: 0).map { Double(Float(bitPattern: $0)) }
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, data.count >= offset + 4 else { return nil }
        let start = data.startIndex + offset
        return data[start..<start + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }
}
