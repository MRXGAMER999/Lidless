import Foundation

/// Names for displays that don't report one. The app passes localized strings,
/// so the core holds no user-facing copy.
public struct DisplayNames: Sendable, Equatable {
    public var builtIn: String
    public var unknownExternal: String

    public init(builtIn: String, unknownExternal: String) {
        self.builtIn = builtIn
        self.unknownExternal = unknownExternal
    }
}

/// Everything the popover and Desk Mode need from one display snapshot.
public struct DisplayInventory: Sendable, Equatable {
    /// The Mac's own panel. Kept from the previous inventory while it is offline
    /// (lid closed, or switched off by Desk Mode), so it never flickers to nil.
    public var builtIn: DisplayDescriptor?
    /// Whether `builtIn` was in this snapshot. Brightness is read only when true.
    public var builtInOnline: Bool
    /// A reference preset locks the built-in's brightness, so Boost can't run.
    public var builtInPresetLocksBrightness: Bool
    /// Wired external displays: the main display first, then left to right.
    public var externals: [DisplayDescriptor]
    /// Externals Desk Mode could move to.
    public var usableExternalCount: Int
    /// Sidecar, AirPlay, DisplayLink and dummy displays, left out of `externals`.
    public var virtualCount: Int

    public static let empty = DisplayInventory(
        builtIn: nil, builtInOnline: false, builtInPresetLocksBrightness: false,
        externals: [], usableExternalCount: 0, virtualCount: 0
    )

    public init(
        builtIn: DisplayDescriptor?,
        builtInOnline: Bool,
        builtInPresetLocksBrightness: Bool,
        externals: [DisplayDescriptor],
        usableExternalCount: Int,
        virtualCount: Int
    ) {
        self.builtIn = builtIn
        self.builtInOnline = builtInOnline
        self.builtInPresetLocksBrightness = builtInPresetLocksBrightness
        self.externals = externals
        self.usableExternalCount = usableExternalCount
        self.virtualCount = virtualCount
    }

    /// Classifies a snapshot.
    ///
    /// - Parameters:
    ///   - facts: One entry per online display ID, in any order.
    ///   - previousBuiltIn: The last inventory's `builtIn`, kept when the panel is offline.
    ///   - names: Fallback names.
    public init(facts: [DisplayFacts], previousBuiltIn: DisplayDescriptor?, names: DisplayNames) {
        var seenIDs: Set<String> = []
        var builtInFacts: DisplayFacts?
        var builtIn: DisplayDescriptor?
        var externals: [(descriptor: DisplayDescriptor, originX: Double)] = []
        var usable = 0
        var virtual = 0

        for f in facts.sorted(by: { $0.displayID < $1.displayID }) {
            let kind = DisplayClassifier.kind(of: f)
            guard kind != .placeholder, let uuid = f.uuid else { continue }
            // Identical monitors can share a UUID; SwiftUI rows need unique IDs.
            let id = seenIDs.contains(uuid) ? "\(uuid)#\(f.displayID)" : uuid
            seenIDs.insert(id)
            let name: String
            switch kind {
            case .builtIn:
                // CoreDisplay calls the built-in "Color LCD": never use it.
                name = Self.cleaned(f.screenName) ?? names.builtIn
            default:
                name = Self.cleaned(f.screenName) ?? Self.cleaned(f.productName) ?? names.unknownExternal
            }
            let descriptor = DisplayDescriptor(
                id: id,
                displayID: f.displayID,
                name: name,
                isBuiltIn: kind == .builtIn,
                pixelWidth: f.nativePixelWidth,
                pixelHeight: f.nativePixelHeight,
                refreshRate: f.refreshRate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
                role: DisplayClassifier.role(of: f),
                isVirtual: kind == .virtual,
                supportsBoost: DisplayClassifier.supportsBoost(f, kind: kind),
                brightnessControl: DisplayClassifier.brightnessControl(f, kind: kind)
            )
            switch kind {
            case .builtIn where builtIn == nil:
                builtIn = descriptor
                builtInFacts = f
            case .physicalExternal:
                externals.append((descriptor, f.originX))
                if DisplayClassifier.isUsableExternal(f, kind: kind) { usable += 1 }
            case .virtual:
                virtual += 1
            case .builtIn, .placeholder:
                break
            }
        }

        self.builtIn = builtIn ?? previousBuiltIn
        builtInOnline = builtIn != nil
        builtInPresetLocksBrightness = (builtInFacts?.referenceHeadroom ?? 0) > 0
        self.externals = externals.sorted { a, b in
            let aMain = a.descriptor.role == .main, bMain = b.descriptor.role == .main
            if aMain != bMain { return aMain }
            if a.originX != b.originX { return a.originX < b.originX }
            return a.descriptor.displayID < b.descriptor.displayID
        }.map(\.descriptor)
        usableExternalCount = usable
        virtualCount = virtual
    }

    private static func cleaned(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
