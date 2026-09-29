import Foundation

/// A Lidless feature another display utility can fight over the same resource.
/// Declared in the order the notices name them: the first conflict an app has
/// is the one it's announced with when none of its features is in use.
public enum ConflictFeature: String, CaseIterable, Sendable, Comparable {
    /// Turning the built-in screen off: display configuration and enabling.
    case deskMode
    /// Brightening the built-in screen past 100% with an EDR overlay.
    case boost
    /// Dimming external displays over DDC or with a shade.
    case externalBrightness

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// A display utility known to fight Lidless, and over what.
public struct ConflictingApp: Sendable, Equatable, Hashable {
    /// The product name, as the notices show it (brand names aren't translated).
    public var name: String
    /// Every bundle identifier its current and older releases use. Setapp
    /// builds ("…-setapp") match without being listed.
    public var bundleIDs: [String]
    /// What it fights over, in `ConflictFeature` order.
    public var features: [ConflictFeature]

    public init(name: String, bundleIDs: [String], features: [ConflictFeature]) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.features = features.sorted()
    }

    /// Identifies the app across its bundle identifiers.
    public var id: String { bundleIDs[0] }

    public func conflicts(with feature: ConflictFeature) -> Bool {
        features.contains(feature)
    }
}

/// The display utilities Lidless warns about, and which of them are running.
///
/// Night Shift, f.lux and virtual-display tools (DeskPad, DisplayLink) are not
/// here: they don't touch what Lidless changes (and Lidless never writes gamma).
/// Bundle identifiers from each project's Xcode project or Homebrew cask (2026-09).
public enum ConflictingApps {
    public static let known: [ConflictingApp] = [
        // Disconnects/disables displays and protects display configuration,
        // XDR/HDR "extra brightness", DDC and software dimming.
        ConflictingApp(
            name: "BetterDisplay",
            bundleIDs: ["pro.betterdisplay.BetterDisplay"],
            features: [.deskMode, .boost, .externalBrightness]
        ),
        // BlackOut and Auto BlackOut disconnect the built-in, XDR Brightness,
        // DDC, gamma and sub-zero dimming.
        ConflictingApp(
            name: "Lunar",
            bundleIDs: ["fyi.lunar.Lunar", "fyi.lunar.LunarLite"],
            features: [.deskMode, .boost, .externalBrightness]
        ),
        // Turns the built-in off whenever an external is connected.
        ConflictingApp(
            name: "SoloDisplay",
            bundleIDs: ["dev.solodisplay.SoloDisplay"],
            features: [.deskMode]
        ),
        // EDR overlays on the built-in screen (App Store and direct builds share the ID).
        ConflictingApp(
            name: "BrightIntosh",
            bundleIDs: ["de.brightintosh.app"],
            features: [.boost]
        ),
        ConflictingApp(
            name: "Vivid",
            bundleIDs: ["com.goodsnooze.vivid"],
            features: [.boost]
        ),
        // DDC plus gamma or shade dimming. v4 moved to app.monitorcontrol;
        // v3 and older used me.guillaumeb.
        ConflictingApp(
            name: "MonitorControl",
            bundleIDs: ["app.monitorcontrol.MonitorControl", "me.guillaumeb.MonitorControl", "app.monitorcontrol.MonitorControlLite"],
            features: [.externalBrightness]
        ),
        // DDC brightness, contrast and presets.
        ConflictingApp(
            name: "DisplayBuddy",
            bundleIDs: ["com.sids.DisplayBuddy"],
            features: [.externalBrightness]
        ),
    ]

    private static let byBundleID: [String: ConflictingApp] = {
        var table: [String: ConflictingApp] = [:]
        for app in known {
            for id in app.bundleIDs { table[id.lowercased()] = app }
        }
        return table
    }()

    /// The known app a bundle identifier belongs to. Case-insensitive, like
    /// Launch Services; a Setapp build's "-setapp" suffix is ignored.
    public static func app(forBundleID bundleID: String) -> ConflictingApp? {
        var id = bundleID.lowercased()
        if id.hasSuffix(setappSuffix) { id.removeLast(setappSuffix.count) }
        return byBundleID[id]
    }

    private static let setappSuffix = "-setapp"

    /// The known apps among running bundle identifiers, each once, in `known` order.
    public static func running(in bundleIDs: some Sequence<String>) -> [ConflictingApp] {
        let found = Set(bundleIDs.compactMap(app(forBundleID:)))
        return known.filter(found.contains)
    }

    /// The running apps that fight `feature`.
    public static func running(in bundleIDs: some Sequence<String>, conflictingWith feature: ConflictFeature) -> [ConflictingApp] {
        running(in: bundleIDs).filter { $0.conflicts(with: feature) }
    }
}

/// One warning to post: `app` is running and fights `feature`.
public struct ConflictNotice: Sendable, Equatable {
    public var app: ConflictingApp
    public var feature: ConflictFeature

    public init(app: ConflictingApp, feature: ConflictFeature) {
        self.app = app
        self.feature = feature
    }
}

/// Decides which conflict warnings to post, so each is posted at most once per
/// launch of Lidless: one when a conflicting app is first seen, and one per
/// feature of it the user then turns on.
///
/// Remembers what it announced for the whole run: quitting and relaunching the
/// other app, or switching the feature off and on, doesn't warn again.
public struct ConflictAdvisor: Sendable {
    private var announcedApps: Set<String> = []
    private var announced: Set<Key> = []

    private struct Key: Hashable, Sendable {
        var app: String
        var feature: ConflictFeature
    }

    public init() {}

    /// Apps that are running (at launch) or just launched. Each known app not
    /// announced yet gets one notice, about the first of its conflicting
    /// features that is on, or else about the first it has.
    public mutating func appsSeen(_ bundleIDs: some Sequence<String>, activeFeatures: Set<ConflictFeature>) -> [ConflictNotice] {
        ConflictingApps.running(in: bundleIDs).compactMap { app in
            guard announcedApps.insert(app.id).inserted else { return nil }
            let feature = app.features.first(where: activeFeatures.contains) ?? app.features[0]
            announced.insert(Key(app: app.id, feature: feature))
            return ConflictNotice(app: app, feature: feature)
        }
    }

    /// `feature` just turned on while `runningBundleIDs` run: one notice per
    /// conflicting app that hasn't been warned about this feature yet.
    public mutating func featureTurnedOn(_ feature: ConflictFeature, runningBundleIDs: some Sequence<String>) -> [ConflictNotice] {
        ConflictingApps.running(in: runningBundleIDs, conflictingWith: feature).compactMap { app in
            guard announced.insert(Key(app: app.id, feature: feature)).inserted else { return nil }
            announcedApps.insert(app.id)
            return ConflictNotice(app: app, feature: feature)
        }
    }
}
