import Foundation

/// How Desk Mode turns the built-in screen off (Settings › Desk Mode › "How it switches off").
public enum DeskModeMethod: String, Sendable, Equatable, Codable, CaseIterable {
    /// SkyLight takes the panel out of the arrangement; windows move to the other displays.
    case disconnect
    /// A black window covers the panel; the arrangement and windows stay put.
    case blackout
}

/// One external display as Desk Mode sees it.
public struct ExternalPresence: Sendable, Equatable {
    /// `CGDisplayCreateUUIDFromDisplayID`. Stable across ID re-issues.
    public var uuid: String
    public var displayID: UInt32
    public var name: String
    /// In the online list. The loss path looks only at this: display sleep
    /// makes every display inactive, and that must never end Desk Mode.
    public var isPresent: Bool
    /// Present, a wired monitor (not virtual, not a placeholder) and active,
    /// asleep or in a mirror set. Only the engage path requires this.
    public var isUsable: Bool

    public init(uuid: String, displayID: UInt32, name: String, isPresent: Bool, isUsable: Bool) {
        self.uuid = uuid
        self.displayID = displayID
        self.name = name
        self.isPresent = isPresent
        self.isUsable = isUsable
    }
}

/// What the system looks like, for Desk Mode's decisions. Pure data; the app
/// builds one after every display or system event.
public struct DeskModeSnapshot: Sendable, Equatable {
    public var lid: LidState
    /// The built-in panel is in the online list.
    public var builtInOnline: Bool
    /// The built-in's ID and UUID, captured while it was online. Kept while it is off.
    public var builtInDisplayID: UInt32?
    public var builtInUUID: String?
    /// The built-in is part of a hardware mirror set. Desk Mode refuses to engage.
    public var builtInMirrored: Bool
    /// Wired externals only; virtual displays and placeholders are left out.
    public var externals: [ExternalPresence]
    /// Between `screensDidSleep` and `screensDidWake`.
    public var screensAsleep: Bool
    /// Between `willSleep` and `didWake`. No display calls while set.
    public var systemSleeping: Bool
    /// This login session owns the console (false after fast user switching away).
    public var sessionActive: Bool
    public var power: PowerSource

    public init(
        lid: LidState = .open,
        builtInOnline: Bool = true,
        builtInDisplayID: UInt32? = 1,
        builtInUUID: String? = nil,
        builtInMirrored: Bool = false,
        externals: [ExternalPresence] = [],
        screensAsleep: Bool = false,
        systemSleeping: Bool = false,
        sessionActive: Bool = true,
        power: PowerSource = .adapter
    ) {
        self.lid = lid
        self.builtInOnline = builtInOnline
        self.builtInDisplayID = builtInDisplayID
        self.builtInUUID = builtInUUID
        self.builtInMirrored = builtInMirrored
        self.externals = externals
        self.screensAsleep = screensAsleep
        self.systemSleeping = systemSleeping
        self.sessionActive = sessionActive
        self.power = power
    }

    /// Externals Desk Mode may move to right now.
    public var usableExternals: [ExternalPresence] { externals.filter(\.isUsable) }
    /// Externals still connected, awake or not.
    public var presentExternals: [ExternalPresence] { externals.filter(\.isPresent) }

    /// Builds a snapshot from raw display facts (one per online ID, any order),
    /// classifying them with `DisplayClassifier`. `previous` supplies the
    /// built-in's ID and UUID while the panel is offline.
    public init(
        facts: [DisplayFacts],
        previous: DeskModeSnapshot?,
        lid: LidState,
        screensAsleep: Bool,
        systemSleeping: Bool,
        sessionActive: Bool,
        power: PowerSource,
        names: DisplayNames
    ) {
        var builtIn: DisplayFacts?
        var externals: [(presence: ExternalPresence, isMain: Bool, originX: Double)] = []
        for f in facts.sorted(by: { $0.displayID < $1.displayID }) {
            let kind = DisplayClassifier.kind(of: f)
            switch kind {
            case .builtIn where builtIn == nil:
                builtIn = f
            case .physicalExternal:
                // Placeholders are filtered by the classifier, so a UUID is always there.
                guard let uuid = f.uuid else { continue }
                let name = Self.cleaned(f.screenName) ?? Self.cleaned(f.productName) ?? names.unknownExternal
                let presence = ExternalPresence(
                    uuid: uuid, displayID: f.displayID, name: name,
                    isPresent: f.isOnline, isUsable: DisplayClassifier.isUsableExternal(f, kind: kind)
                )
                externals.append((presence, f.isMain, f.originX))
            case .builtIn, .virtual, .placeholder:
                break
            }
        }
        self.init(
            lid: lid,
            builtInOnline: builtIn != nil,
            builtInDisplayID: builtIn?.displayID ?? previous?.builtInDisplayID,
            builtInUUID: builtIn?.uuid ?? previous?.builtInUUID,
            builtInMirrored: builtIn.map { $0.isInMirrorSet || $0.mirrorsDisplay != 0 } ?? false,
            // Same order as the popover: the main display first, then left to right, so
            // the prompt lands on the display the user looks at.
            externals: externals.sorted { a, b in
                if a.isMain != b.isMain { return a.isMain }
                if a.originX != b.originX { return a.originX < b.originX }
                return a.presence.displayID < b.presence.displayID
            }.map(\.presence),
            screensAsleep: screensAsleep,
            systemSleeping: systemSleeping,
            sessionActive: sessionActive,
            power: power
        )
    }

    private static func cleaned(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
