import Foundation

/// One display's current mode, as far as a mode switch shows.
///
/// macOS keeps its own settings for every display arrangement. When the
/// "external alone" arrangement gives a monitor a different mode than the
/// "MacBook + external" one, turning the built-in off or on switches that
/// monitor's mode, and it blanks for a moment while its signal resyncs.
/// A change of colour format alone (RGB vs YCbCr) keeps the mode and isn't
/// visible here.
public struct DisplayModeInfo: Sendable, Equatable {
    public var modeID: Int32
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double

    public init(modeID: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.modeID = modeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }

    /// "1920×1080 (HiDPI) @ 144 Hz, mode 108", for the log.
    public var summary: String {
        let hiDPI = pixelWidth > width ? " (HiDPI)" : ""
        return "\(width)×\(height)\(hiDPI) @ \(Int(refreshRate.rounded())) Hz, mode \(modeID)"
    }
}

public enum DisplayModeChange {
    /// The displays online both before and after whose mode differs, in ID
    /// order. Displays that came or went (the built-in itself) don't count.
    public static func changed(
        before: [UInt32: DisplayModeInfo],
        after: [UInt32: DisplayModeInfo]
    ) -> [(id: UInt32, from: DisplayModeInfo, to: DisplayModeInfo)] {
        before.keys.sorted().compactMap { id in
            guard let from = before[id], let to = after[id], from != to else { return nil }
            return (id, from, to)
        }
    }
}
