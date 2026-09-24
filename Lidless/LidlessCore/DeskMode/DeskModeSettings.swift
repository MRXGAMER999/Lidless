import Foundation

/// Desk Mode's saved settings. Stored as one JSON value in UserDefaults by the app.
public struct DeskModeSettings: Sendable, Equatable, Codable {
    public var method: DeskModeMethod
    /// "Ask before keeping it off". Default on.
    public var askBeforeKeeping: Bool
    /// Re-apply after wake instead of leaving the panel on. Default off.
    public var keepAfterWake: Bool
    public var rule: DeskModeRule

    public static let defaults = DeskModeSettings(method: .disconnect, askBeforeKeeping: true, keepAfterWake: false, rule: DeskModeRule())

    public init(method: DeskModeMethod, askBeforeKeeping: Bool, keepAfterWake: Bool, rule: DeskModeRule) {
        self.method = method
        self.askBeforeKeeping = askBeforeKeeping
        self.keepAfterWake = keepAfterWake
        self.rule = rule
    }

    /// Decodes, filling missing keys from `defaults` so older saves keep working.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DeskModeSettings.defaults
        method = try c.decodeIfPresent(DeskModeMethod.self, forKey: .method) ?? d.method
        askBeforeKeeping = try c.decodeIfPresent(Bool.self, forKey: .askBeforeKeeping) ?? d.askBeforeKeeping
        keepAfterWake = try c.decodeIfPresent(Bool.self, forKey: .keepAfterWake) ?? d.keepAfterWake
        rule = try c.decodeIfPresent(DeskModeRule.self, forKey: .rule) ?? d.rule
    }
}
