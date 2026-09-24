import Foundation

extension LidState {
    /// From IOPMrootDomain's `AppleClamshellState`; nil when the key is absent,
    /// which means the Mac has no lid (desktops, VMs).
    public init(clamshellClosed: Bool?) {
        switch clamshellClosed {
        case true?: self = .closed
        case false?: self = .open
        case nil: self = .unknown
        }
    }
}

/// `kIOPMMessageClamshellStateChange` (IOPM.h). The SDK macro doesn't import into Swift.
public struct ClamshellMessage: Sendable, Equatable {
    public static let messageType: UInt32 = 0xE003_4100

    public var isClosed: Bool
    /// Closing the lid will put the Mac to sleep (no external display awake).
    public var causesSleep: Bool

    /// - Parameter argument: The message argument, a bit field (kClamshellStateBit, kClamshellSleepBit).
    public init(argument: UInt) {
        isClosed = argument & 0b01 != 0
        causesSleep = argument & 0b10 != 0
    }
}

/// One IOPowerSources entry, reduced to what Lidless shows.
public struct PowerSourceSample: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case internalBattery
        case ups
        case other
    }

    public var kind: Kind
    /// Charge, 0...100, when known.
    public var percent: Int?
    public var isPresent: Bool

    public init(kind: Kind, percent: Int?, isPresent: Bool = true) {
        self.kind = kind
        self.percent = percent
        self.isPresent = isPresent
    }

    /// From `IOPSGetPowerSourceDescription` (keys from IOPSKeys.h).
    public init(description: [String: Any]) {
        switch description["Type"] as? String {
        case "InternalBattery": kind = .internalBattery
        case "UPS": kind = .ups
        default: kind = .other
        }
        percent = Self.percent(current: description["Current Capacity"] as? Int, max: description["Max Capacity"] as? Int)
        isPresent = description["Is Present"] as? Bool ?? true
    }

    /// Apple sources publish percent, but a UPS may report mAh, so always divide.
    public static func percent(current: Int?, max: Int?) -> Int? {
        guard let current, let max, max > 0 else { return nil }
        // Clamped before the conversion: Int(_:) traps on a reading far out of range.
        let value = (Double(current) / Double(max) * 100).rounded()
        return Int(Swift.min(100, Swift.max(0, value)))
    }
}

extension PowerSource {
    /// - Parameters:
    ///   - providing: `IOPSGetProvidingPowerSourceType`: "AC Power", "Battery Power" or "UPS Power".
    ///     It also says "AC Power" on error and on Macs without a battery.
    ///   - sources: Every power source description.
    public init(providing: String?, sources: [PowerSourceSample]) {
        let battery = sources.first { $0.kind == .internalBattery && $0.isPresent }
        switch providing {
        case "Battery Power":
            self = .battery(percent: battery?.percent)
        case "UPS Power":
            // Running on stored energy, so "On battery" is true.
            self = .battery(percent: sources.first { $0.kind == .ups }?.percent)
        default:
            self = battery == nil ? .unknown : .adapter
        }
    }
}
