import Foundation

/// Why Boost can't run right now. `nil` from `BoostGuard.block(_:)` means it may.
public enum BoostBlock: Sendable, Equatable {
    // Pauses: shown to the user, and Boost comes back by itself when they clear.
    /// At or above Settings' heat level. Notifies once ("Brightness Boost paused").
    case hot
    /// On battery below Settings' level. Notifies once.
    case lowBattery
    /// Low Power Mode.
    case lowPower

    // Suspensions: silent, and Boost comes back by itself when they clear.
    /// Lid closed, built-in offline, or Desk Mode on or switching.
    case builtInUnavailable
    /// Displays asleep, the screen locked, or another user's session.
    case screenAsleepOrLocked
    /// A display reconfiguration is in progress (and for `settleTime` after it).
    case reconfiguring
    /// macOS asks apps to suppress HDR (`applicationShouldSuppressHighDynamicRangeContent`).
    case hdrSuppressed

    // Permanent until the setting or panel changes:
    /// "Boost allowed" is off.
    case notAllowed
    /// No XDR headroom, or a reference preset locks brightness.
    case unsupported

    /// Pauses the user should hear about once.
    public var notifies: Bool { self == .hot || self == .lowBattery }
}

/// Everything Boost's guard rails look at. The app fills it from its stores.
public struct BoostConditions: Sendable, Equatable {
    public var thermal: ThermalLevel
    public var power: PowerSource
    public var lowPowerMode: Bool
    public var lid: LidState
    public var builtInOnline: Bool
    public var deskModeEngaged: Bool
    public var screensAsleep: Bool
    public var screenLocked: Bool
    public var sessionActive: Bool
    public var reconfiguring: Bool
    public var hdrSuppressed: Bool
    /// The built-in reports XDR headroom (`DisplayDescriptor.supportsBoost`) and no reference preset.
    public var panelSupportsBoost: Bool

    public init(thermal: ThermalLevel = .nominal, power: PowerSource = .adapter, lowPowerMode: Bool = false, lid: LidState = .open, builtInOnline: Bool = true, deskModeEngaged: Bool = false, screensAsleep: Bool = false, screenLocked: Bool = false, sessionActive: Bool = true, reconfiguring: Bool = false, hdrSuppressed: Bool = false, panelSupportsBoost: Bool = true) {
        self.thermal = thermal
        self.power = power
        self.lowPowerMode = lowPowerMode
        self.lid = lid
        self.builtInOnline = builtInOnline
        self.deskModeEngaged = deskModeEngaged
        self.screensAsleep = screensAsleep
        self.screenLocked = screenLocked
        self.sessionActive = sessionActive
        self.reconfiguring = reconfiguring
        self.hdrSuppressed = hdrSuppressed
        self.panelSupportsBoost = panelSupportsBoost
    }
}

public enum BoostGuard {
    /// The most important block, or nil. Order: notAllowed, unsupported,
    /// builtInUnavailable, screenAsleepOrLocked, reconfiguring, hot, lowBattery,
    /// lowPower, hdrSuppressed.
    public static func block(_ conditions: BoostConditions, settings: BoostSettings) -> BoostBlock? {
        if !settings.allowed { return .notAllowed }
        if !conditions.panelSupportsBoost { return .unsupported }
        if conditions.lid == .closed || !conditions.builtInOnline || conditions.deskModeEngaged { return .builtInUnavailable }
        if conditions.screensAsleep || conditions.screenLocked || !conditions.sessionActive { return .screenAsleepOrLocked }
        if conditions.reconfiguring { return .reconfiguring }
        if let pause = pause(conditions, settings: settings) { return pause }
        if conditions.lowPowerMode { return .lowPower }
        if conditions.hdrSuppressed { return .hdrSuppressed }
        return nil
    }

    /// The pause the heat or battery rail calls for (`.hot` before `.lowBattery`),
    /// whatever else blocks. `BoostMachine` keeps such a pause for a hold time
    /// after this goes nil, so a reading that flaps around the threshold
    /// doesn't flap Boost with it.
    static func pause(_ conditions: BoostConditions, settings: BoostSettings) -> BoostBlock? {
        if conditions.thermal >= settings.pauseAtHeat { return .hot }
        if isLowBattery(conditions.power, settings: settings) { return .lowBattery }
        return nil
    }

    /// Extra cap on the factor below the pause level: `.serious` (when the pause
    /// level is critical) caps at 1.2, `.fair` and `.nominal` don't cap.
    public static func thermalCap(_ thermal: ThermalLevel, settings: BoostSettings) -> Double {
        thermal == .serious && thermal < settings.pauseAtHeat ? seriousCap : .infinity
    }

    /// boost.md §9: "`.serious` → cap k at about 1.2".
    static let seriousCap = 1.2

    /// An unknown percentage never pauses: better a boosted screen than a
    /// pause the user can't explain.
    private static func isLowBattery(_ power: PowerSource, settings: BoostSettings) -> Bool {
        guard case .battery(let percent?) = power, let threshold = settings.pauseBelowBattery else { return false }
        return percent < threshold
    }
}
