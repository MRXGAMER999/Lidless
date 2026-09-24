import Foundation

/// Settings › Keys & App and first-run state. JSON in UserDefaults ("general.settings").
public struct GeneralSettings: Sendable, Equatable, Codable {
    /// "Icon shows what's on": the menu bar glyph changes with Desk Mode and Boost. Default on.
    public var iconShowsState: Bool
    /// Onboarding finished ("Start Using Lidless"). Default false.
    public var onboardingCompleted: Bool
    /// "Auto-update" (Phase 6 Sparkle). Default on.
    public var autoUpdate: Bool

    public static let defaults = GeneralSettings(iconShowsState: true, onboardingCompleted: false, autoUpdate: true)

    public init(iconShowsState: Bool, onboardingCompleted: Bool, autoUpdate: Bool) {
        self.iconShowsState = iconShowsState
        self.onboardingCompleted = onboardingCompleted
        self.autoUpdate = autoUpdate
    }

    /// Missing keys take their defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralSettings.defaults
        iconShowsState = try c.decodeIfPresent(Bool.self, forKey: .iconShowsState) ?? d.iconShowsState
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? d.onboardingCompleted
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? d.autoUpdate
    }
}
