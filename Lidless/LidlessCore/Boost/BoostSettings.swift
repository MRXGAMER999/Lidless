import Foundation

/// Settings › Brightness. Stored as one JSON value in UserDefaults by the app.
public struct BoostSettings: Sendable, Equatable, Codable {
    /// "Boost allowed". Default on.
    public var allowed: Bool
    /// The Boost ceiling handle, in nits: 550...1000 in steps of 50. Default 1000.
    public var ceilingNits: Double
    /// Guard rail "Mac gets hot": pause Boost at this heat level (fair, serious or critical). Default serious.
    public var pauseAtHeat: ThermalLevel
    /// Guard rail "Battery runs low": pause below this percentage on battery (10...50), nil = never. Default 30.
    public var pauseBelowBattery: Int?
    /// Guard rail "Screen sleeps": wake up at 100 %, not boosted. Default on.
    public var wakeAtNormal: Bool
    /// "Keep pressing to boost": the brightness-up key at 100 % goes into Boost. Default on.
    public var keysIntoBoost: Bool

    public static let ceilingRange: ClosedRange<Double> = 550...1000
    public static let ceilingStep = 50.0
    public static let batteryChoices = [10, 20, 30, 40, 50]
    public static let heatChoices: [ThermalLevel] = [.fair, .serious, .critical]

    public static let defaults = BoostSettings(allowed: true, ceilingNits: 1000, pauseAtHeat: .serious, pauseBelowBattery: 30, wakeAtNormal: true, keysIntoBoost: true)

    public init(allowed: Bool, ceilingNits: Double, pauseAtHeat: ThermalLevel, pauseBelowBattery: Int?, wakeAtNormal: Bool, keysIntoBoost: Bool) {
        self.allowed = allowed
        self.ceilingNits = ceilingNits
        self.pauseAtHeat = pauseAtHeat
        self.pauseBelowBattery = pauseBelowBattery
        self.wakeAtNormal = wakeAtNormal
        self.keysIntoBoost = keysIntoBoost
    }

    /// `ceilingNits` snapped to the step and clamped to the range.
    public var clampedCeiling: Double {
        guard !ceilingNits.isNaN else { return Self.defaults.ceilingNits }
        let snapped = (ceilingNits / Self.ceilingStep).rounded() * Self.ceilingStep
        return min(max(snapped, Self.ceilingRange.lowerBound), Self.ceilingRange.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case allowed, ceilingNits, pauseAtHeat, pauseBelowBattery, wakeAtNormal, keysIntoBoost
    }

    /// Decodes, filling missing keys from `defaults` so older saves keep working.
    /// A value that can't be read also falls back to its default, so one bad key
    /// doesn't cost the user every other setting. A heat level below `.fair` would
    /// pause Boost for good, so it's raised to `.fair`; the battery level is
    /// clamped to 10...50. A battery rail saved as `null` stays cleared.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BoostSettings.defaults
        allowed = (try? c.decodeIfPresent(Bool.self, forKey: .allowed)) ?? d.allowed
        ceilingNits = (try? c.decodeIfPresent(Double.self, forKey: .ceilingNits)) ?? d.ceilingNits
        let heat = (try? c.decodeIfPresent(ThermalLevel.self, forKey: .pauseAtHeat)) ?? d.pauseAtHeat
        pauseAtHeat = max(heat, .fair)
        if c.contains(.pauseBelowBattery) {
            if (try? c.decodeNil(forKey: .pauseBelowBattery)) == true {
                pauseBelowBattery = nil
            } else if let percent = try? c.decode(Int.self, forKey: .pauseBelowBattery) {
                pauseBelowBattery = min(max(percent, Self.batteryChoices[0]), Self.batteryChoices[Self.batteryChoices.count - 1])
            } else {
                pauseBelowBattery = d.pauseBelowBattery
            }
        } else {
            pauseBelowBattery = d.pauseBelowBattery
        }
        wakeAtNormal = (try? c.decodeIfPresent(Bool.self, forKey: .wakeAtNormal)) ?? d.wakeAtNormal
        keysIntoBoost = (try? c.decodeIfPresent(Bool.self, forKey: .keysIntoBoost)) ?? d.keysIntoBoost
    }

    /// Writes a cleared battery rail as `null` (the synthesized form would drop
    /// the key, and decoding would bring the default back).
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(allowed, forKey: .allowed)
        try c.encode(ceilingNits, forKey: .ceilingNits)
        try c.encode(pauseAtHeat, forKey: .pauseAtHeat)
        try c.encode(pauseBelowBattery, forKey: .pauseBelowBattery)
        try c.encode(wakeAtNormal, forKey: .wakeAtNormal)
        try c.encode(keysIntoBoost, forKey: .keysIntoBoost)
    }
}
