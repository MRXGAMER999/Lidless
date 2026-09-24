import Foundation

/// Settings › Desk Mode › "Your rule": "When I plug in [any display], turn the
/// built-in screen [off] after [3 seconds]." plus "Only when my Mac is plugged in".
public struct DeskModeRule: Sendable, Equatable, Codable {
    public enum Action: String, Sendable, Equatable, Codable, CaseIterable {
        /// Turn the built-in off.
        case off
        /// Leave it on: the rule does nothing.
        case on
    }

    public var isEnabled: Bool
    /// The display that triggers the rule (UUID); nil means any wired display.
    public var displayUUID: String?
    /// Its name when chosen, for the menu while it isn't connected.
    public var displayName: String?
    public var action: Action
    /// 0 ("right away"), 3, 5 or 10.
    public var delaySeconds: Int
    public var onlyOnPower: Bool

    public static let delayChoices = [0, 3, 5, 10]

    public init(isEnabled: Bool = true, displayUUID: String? = nil, displayName: String? = nil, action: Action = .off, delaySeconds: Int = 3, onlyOnPower: Bool = false) {
        self.isEnabled = isEnabled
        self.displayUUID = displayUUID
        self.displayName = displayName
        self.action = action
        self.delaySeconds = delaySeconds
        self.onlyOnPower = onlyOnPower
    }

    /// Decodes, filling missing keys from the defaults so older saves keep working.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DeskModeRule()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        displayUUID = try c.decodeIfPresent(String.self, forKey: .displayUUID) ?? d.displayUUID
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? d.displayName
        action = try c.decodeIfPresent(Action.self, forKey: .action) ?? d.action
        delaySeconds = try c.decodeIfPresent(Int.self, forKey: .delaySeconds) ?? d.delaySeconds
        onlyOnPower = try c.decodeIfPresent(Bool.self, forKey: .onlyOnPower) ?? d.onlyOnPower
    }

    /// Whether plugging in the display `uuid` should turn the built-in off, on `power`.
    func matches(uuid: String, power: PowerSource) -> Bool {
        isEnabled
            && action == .off
            && (displayUUID == nil || displayUUID == uuid)
            && (!onlyOnPower || power == .adapter)
    }
}

/// Watches snapshots for newly connected displays and says when the rule fires.
///
/// Fires only for an external that *appears* while the app runs (not ones present
/// at launch or after wake, so a black panel never comes back on its own), after
/// the delay, if it is still connected and the rule still matches. Also never
/// fires again for a display the user turned Desk Mode off for, until that
/// display disconnects.
///
/// One display is pending at a time. Others that match while it waits queue
/// behind it, and the first still there takes its place if it is unplugged
/// before it fires.
public struct DeskModeRuleEngine: Sendable, Equatable {
    public struct Pending: Sendable, Equatable {
        public var uuid: String
        public var displayName: String
        public var fireAt: TimeInterval
    }

    public private(set) var pending: Pending?
    /// Displays that connected while another was pending, oldest first.
    private var waiting: [Arrival] = []
    /// Present externals in the last snapshot seen; anything not in here is new.
    private var known: Set<String> = []
    /// Displays the user turned Desk Mode off for, until they disconnect.
    private var declined: Set<String> = []
    /// Until the first `baseline`, `observe` baselines instead, so nothing
    /// present at launch counts as newly connected.
    private var hasBaseline = false

    private struct Arrival: Sendable, Equatable {
        var uuid: String
        var displayName: String
        var connectedAt: TimeInterval
    }

    public init() {}

    /// The first snapshot (at launch or after wake): remembers what's connected
    /// without firing.
    public mutating func baseline(_ snapshot: DeskModeSnapshot) {
        let present = Set(snapshot.presentExternals.map(\.uuid))
        known = present
        declined.formIntersection(present)
        pending = nil
        waiting = []
        hasBaseline = true
    }

    /// A new snapshot. Returns nothing; check `due(now:)` on ticks.
    ///
    /// Snapshots taken while the system sleeps are ignored (and cancel a pending
    /// trigger): displays drop out then, and must not count as new at wake.
    public mutating func observe(_ snapshot: DeskModeSnapshot, rule: DeskModeRule, now: TimeInterval) {
        guard hasBaseline else { return baseline(snapshot) }
        guard !snapshot.systemSleeping else {
            pending = nil
            waiting = []
            return
        }
        let present = Set(snapshot.presentExternals.map(\.uuid))
        let appeared = snapshot.presentExternals.filter { !known.contains($0.uuid) }
        known = present
        declined.formIntersection(present)
        waiting.removeAll { !present.contains($0.uuid) }
        let delay = TimeInterval(max(0, rule.delaySeconds))
        if let p = pending, !present.contains(p.uuid) {
            pending = nil
            // The next in line keeps its own delay, counted from when it connected.
            if let i = waiting.firstIndex(where: { rule.matches(uuid: $0.uuid, power: snapshot.power) }) {
                let next = waiting.remove(at: i)
                pending = Pending(uuid: next.uuid, displayName: next.displayName, fireAt: max(now, next.connectedAt + delay))
            }
        }
        for display in appeared where !declined.contains(display.uuid) && rule.matches(uuid: display.uuid, power: snapshot.power) {
            if pending == nil {
                pending = Pending(uuid: display.uuid, displayName: display.name, fireAt: now + delay)
            } else {
                waiting.append(Arrival(uuid: display.uuid, displayName: display.name, connectedAt: now))
            }
        }
    }

    /// The user turned Desk Mode off (or declined the prompt) while this display
    /// was connected: don't fire for it again until it reconnects.
    public mutating func userDeclined(currentExternals: [ExternalPresence]) {
        declined.formUnion(currentExternals.filter(\.isPresent).map(\.uuid))
        waiting.removeAll { declined.contains($0.uuid) }
        if let p = pending, declined.contains(p.uuid) { pending = nil }
    }

    /// When the pending trigger is due and its display still present and usable,
    /// returns the display's name and clears it. The caller then sends
    /// `.turnOn(trigger: .automatic(displayName:))`.
    ///
    /// A due trigger is cleared even when it doesn't fire, so it never waits
    /// for a display to become usable later. The queue goes with it, so
    /// displays plugged in together fire the rule once.
    public mutating func due(now: TimeInterval, snapshot: DeskModeSnapshot, rule: DeskModeRule) -> String? {
        guard let p = pending, now >= p.fireAt else { return nil }
        pending = nil
        waiting = []
        guard !declined.contains(p.uuid),
              rule.matches(uuid: p.uuid, power: snapshot.power),
              let display = snapshot.usableExternals.first(where: { $0.uuid == p.uuid })
        else { return nil }
        return display.name
    }
}
