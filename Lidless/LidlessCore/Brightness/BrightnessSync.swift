import Foundation

/// One read of a display's brightness through DisplayServices.
public struct BrightnessLevelReading: Sendable, Equatable {
    /// The Control Center slider, 0...1.
    public var level: Double
    /// SDR white as a fraction of the panel's normal maximum, when readable.
    public var linear: Double?
    /// "Automatically adjust brightness", when readable.
    public var autoBrightness: Bool?

    public init(level: Double, linear: Double? = nil, autoBrightness: Bool? = nil) {
        self.level = level
        self.linear = linear
        self.autoBrightness = autoBrightness
    }
}

/// Decides when a brightness read may move the popover slider, so reads never
/// fight the user's hand.
public struct BrightnessSyncPolicy: Sendable, Equatable {
    /// Reads within this many slider positions of the slider are ignored.
    public var minimumChange: Double
    /// Seconds after the user last moved the slider during which reads are ignored.
    public var userHold: Double

    public init(minimumChange: Double = 0.05, userHold: Double = 2) {
        self.minimumChange = minimumChange
        self.userHold = userHold
    }

    /// The slider position for a read, or nil to leave the slider where it is.
    ///
    /// - Parameters:
    ///   - lastUserEdit: Monotonic time of the user's last slider change, if any.
    ///   - now: Monotonic time now.
    public func position(for reading: BrightnessLevelReading, scale: BrightnessScale, current: Double, lastUserEdit: Double?, now: Double) -> Double? {
        guard reading.level.isFinite else { return nil }
        if let lastUserEdit, now - lastUserEdit < userHold { return nil }
        let target = scale.position(nativeLevel: reading.level)
        return abs(target - current) >= minimumChange ? target : nil
    }
}
