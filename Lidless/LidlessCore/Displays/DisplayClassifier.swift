import Foundation

/// What a display ID turns out to be.
public enum DisplayKind: Sendable, Equatable {
    case builtIn
    /// A monitor on a cable, driven by its own framebuffer.
    case physicalExternal
    /// Sidecar, AirPlay, DisplayLink, dummies and anything unrecognised.
    case virtual
    /// Not a panel: an empty framebuffer slot or WindowServer's stand-in.
    case placeholder
}

/// Sorts raw display facts into the app's categories. First match wins; the
/// order matters (see each rule).
public enum DisplayClassifier {
    /// Potential EDR headroom that separates XDR panels (16) from SDR ones (about 2).
    public static let boostHeadroomThreshold = 4.0

    static let nilUUID = "00000000-0000-0000-0000-000000000000"

    public static func kind(of facts: DisplayFacts) -> DisplayKind {
        // EDID vendor and product are 16-bit: the 'unkn'/'virt' stand-in can't be a panel,
        // and it may claim to be built in, so this runs first.
        let noPanel = facts.vendor > 0xFFFF || facts.model > 0xFFFF
            || (facts.vendor == 0 && facts.model == 0)
            || facts.nativePixelWidth <= 1
            || facts.uuid == nil || facts.uuid == nilUUID
        if noPanel || !facts.isOnline { return .placeholder }
        if facts.isBuiltIn { return .builtIn }
        if facts.isAirPlay { return .virtual }
        // Wired displays hang off a DCP framebuffer node. Checked before the virtual
        // flag, which reads 1 on real monitors around display sleep.
        if facts.ioLocation?.contains("/dispext") == true { return .physicalExternal }
        return .virtual
    }

    public static func role(of facts: DisplayFacts) -> DisplayDescriptor.Role {
        if facts.mirrorsDisplay != 0 { return .mirrored }
        return facts.isMain ? .main : .extended
    }

    public static func supportsBoost(_ facts: DisplayFacts, kind: DisplayKind) -> Bool {
        kind == .builtIn && facts.potentialHeadroom >= boostHeadroomThreshold
    }

    /// The control each display could use. `.ddc` is only a candidate: Phase 4
    /// probes it and may fall back to `.software`.
    public static func brightnessControl(_ facts: DisplayFacts, kind: DisplayKind) -> DisplayDescriptor.BrightnessControl {
        if facts.canChangeBrightnessNatively { return .native }
        switch kind {
        case .physicalExternal: return .ddc
        case .virtual: return .software
        case .builtIn, .placeholder: return .none
        }
    }

    /// A wired monitor Desk Mode could move to. Asleep displays drop out of the
    /// active list, and mirror followers may too, so either still counts.
    public static func isUsableExternal(_ facts: DisplayFacts, kind: DisplayKind) -> Bool {
        kind == .physicalExternal && facts.isOnline && (facts.isActive || facts.isAsleep || facts.isInMirrorSet)
    }
}
