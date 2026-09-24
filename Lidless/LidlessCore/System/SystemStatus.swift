import Foundation

/// Heat level as reported by `ProcessInfo.thermalState`, in the app's own words.
public enum ThermalLevel: Int, Sendable, Comparable, CaseIterable, Codable {
    case nominal
    case fair
    case serious
    case critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Where the Mac is drawing power from.
public enum PowerSource: Sendable, Equatable {
    case adapter
    /// On battery; `percent` is 0...100 when known.
    case battery(percent: Int?)
    /// Desktop Macs or anything without a battery.
    case unknown
}

/// Whether the MacBook's lid is open.
public enum LidState: Sendable, Equatable {
    case open
    case closed
    /// Macs without a lid, or the state could not be read.
    case unknown
}
