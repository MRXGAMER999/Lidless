import Foundation

/// A snapshot of one connected display, independent of CoreGraphics types.
public struct DisplayDescriptor: Sendable, Equatable, Identifiable {
    /// Stable across reconnects (CoreGraphics display UUID).
    public var id: String
    /// CoreGraphics display ID at the time of the snapshot. Can change between connections.
    public var displayID: UInt32
    public var name: String
    public var isBuiltIn: Bool
    /// Panel resolution in pixels.
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Refresh rate in Hz, when known.
    public var refreshRate: Double?
    public var role: Role
    /// True for software displays (Sidecar, AirPlay, DisplayLink, dummies).
    public var isVirtual: Bool
    /// Whether this display can show brighter-than-SDR content.
    public var supportsBoost: Bool
    public var brightnessControl: BrightnessControl

    public enum Role: Sendable, Equatable {
        case main
        case extended
        case mirrored
    }

    public enum BrightnessControl: Sendable, Equatable {
        /// Apple panels and Apple-made external displays.
        case native
        /// External monitors that answer DDC/CI commands.
        case ddc
        /// Dimmed with an overlay because the monitor can't be controlled.
        case software
        case none
    }

    public init(
        id: String,
        displayID: UInt32,
        name: String,
        isBuiltIn: Bool,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double? = nil,
        role: Role,
        isVirtual: Bool = false,
        supportsBoost: Bool = false,
        brightnessControl: BrightnessControl = .none
    ) {
        self.id = id
        self.displayID = displayID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.role = role
        self.isVirtual = isVirtual
        self.supportsBoost = supportsBoost
        self.brightnessControl = brightnessControl
    }

    /// Short resolution name such as "5K", "4K" or "1080p".
    public var resolutionClass: String {
        ResolutionClass.name(width: pixelWidth, height: pixelHeight)
    }
}

/// Names a panel resolution the way people talk about monitors.
public enum ResolutionClass {
    public static func name(width: Int, height: Int) -> String {
        let long = max(width, height)
        let short = min(width, height)
        guard short > 0, long >= 1920 else { return "\(width)×\(height)" }
        // Ultrawides (21:9, 32:9) go by their height: "5K" or "4K" reads as a 16:9-ish panel.
        if long > short * 2 {
            return long == 3440 && short == 1440 ? "UWQHD" : "\(short)p"
        }
        switch long {
        case 7680...: return "8K"
        case 6016...: return "6K"
        case 5120...: return "5K"
        case 3840...: return "4K"
        default: return "\(short)p"
        }
    }
}
