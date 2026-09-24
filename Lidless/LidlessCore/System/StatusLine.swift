import Foundation

/// The pieces of the popover's one-line status ("Lid open · 3 displays · On power").
///
/// The app turns each segment into localized text; this type only decides which
/// segments appear and in what order.
public enum StatusSegment: Sendable, Equatable {
    case lidOpen
    case lidClosed
    case builtInOnly
    case builtInOff
    case displayCount(Int)
    case onPower
    case onBattery(percent: Int?)
}

public enum StatusLine {
    /// Builds the status segments for the popover header.
    ///
    /// - Parameters:
    ///   - lid: Lid state of the MacBook.
    ///   - externalCount: Real (non-virtual) external displays that are connected.
    ///   - builtInLit: Whether the built-in screen is showing an image as far as
    ///     Desk Mode knows. A closed lid overrides it.
    ///   - power: Current power source.
    public static func segments(
        lid: LidState,
        externalCount: Int,
        builtInLit: Bool,
        power: PowerSource
    ) -> [StatusSegment] {
        let lidClosed = lid == .closed
        // Desk Mode reports "off" while the lid is closed, but the built-in is dark.
        let lit = builtInLit && !lidClosed
        var result: [StatusSegment] = []
        if externalCount == 0 {
            result.append(.builtInOnly)
        } else {
            switch lid {
            case .open: result.append(.lidOpen)
            case .closed: result.append(.lidClosed)
            case .unknown: break
            }
        }

        // "Lid closed" already says the built-in is off.
        if !builtInLit, !lidClosed, externalCount > 0 {
            result.append(.builtInOff)
        }

        if externalCount > 0 {
            result.append(.displayCount(externalCount + (lit ? 1 : 0)))
        }

        // Keep the line short: the Desk Mode line already says a lot.
        if lit || lidClosed || externalCount == 0 {
            switch power {
            case .adapter: result.append(.onPower)
            case .battery(let percent): result.append(.onBattery(percent: percent))
            case .unknown: break
            }
        }
        return result
    }
}
