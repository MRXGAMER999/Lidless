import Combine
import Foundation
import LidlessCore

/// Built-in screen brightness and Boost, as shown by the popover slider.
///
/// Kept separate from the other stores so that dragging the slider only
/// redraws the brightness card.
///
/// In a normal launch `BoostController` sets `changeHandler` and turns the
/// slider into native brightness (0...100) and Boost (above 100). Without a
/// handler (samples, previews) the slider changes this store only. Reads wait
/// while the slider is held, resume 2 s after the last touch and move the
/// thumb back to macOS's level.
final class BrightnessStore: ObservableObject {
    /// Where a change of `position` came from.
    enum ChangeSource: Sendable, Equatable {
        /// The slider, a key or an action: the screen should follow.
        case user
        /// A read of macOS's level: the screen is already there, so nothing is written.
        case read
    }

    /// Slider position, 0...150. Past 100 is Boost.
    @Published var position: Double {
        didSet {
            if !isApplyingRead { lastUserEdit = clock() }
            if position != oldValue { changeHandler?(position, isApplyingRead ? .read : .user) }
        }
    }
    @Published var scale: BrightnessScale
    /// Settings › Brightness › "Boost allowed".
    @Published var boostAllowed: Bool

    /// Runs after every change of `position`, with the new position. A read
    /// never writes brightness back, or macOS and the slider would chase each other.
    var changeHandler: ((Double, ChangeSource) -> Void)?
    /// Runs when the user presses (true) or releases (false) the slider.
    var trackingHandler: ((Bool) -> Void)?
    /// Native brightness this close to full counts as full: Boost holds it there.
    static let fullLevelTolerance = 0.005

    /// Uptime of the user's last touch: a change that didn't come from
    /// `applyRead`, or a press or release of the slider. Reads never fight a drag.
    private(set) var lastUserEdit: TimeInterval?
    /// The slider is held. A thumb held still changes nothing, so without this
    /// the hold would run out under the user's pointer.
    private(set) var isTracking = false
    private var isApplyingRead = false
    private let clock: () -> TimeInterval

    /// - Parameter clock: Monotonic seconds; tests pass a fake.
    init(
        position: Double = 70,
        scale: BrightnessScale = .init(normalMaxNits: 600, ceilingNits: 1000),
        boostAllowed: Bool = true,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.position = position
        self.scale = scale
        self.boostAllowed = boostAllowed
        self.clock = clock
    }

    /// The scale the slider actually uses: no Boost range when Boost isn't allowed.
    var effectiveScale: BrightnessScale {
        scale.allowingBoost(boostAllowed)
    }

    var isBoosted: Bool { effectiveScale.isBoosted(position) }

    /// "Back to 100%": leaves Boost and goes to full normal brightness.
    func leaveBoost() {
        position = BrightnessScale.normalLimit
    }

    /// The user pressed (true) or released (false) the slider. No read moves a
    /// held slider, and the hold restarts from the release.
    func setTracking(_ tracking: Bool) {
        guard tracking != isTracking else { return }
        isTracking = tracking
        lastUserEdit = clock()
        trackingHandler?(tracking)
    }

    /// Seconds until a read may move the slider again, or nil when one already
    /// may. A held slider has at least the whole hold left.
    func remainingUserHold(policy: BrightnessSyncPolicy = .init()) -> TimeInterval? {
        if isTracking { return policy.userHold }
        guard let lastUserEdit else { return nil }
        let remaining = policy.userHold - (clock() - lastUserEdit)
        return remaining > 0 ? remaining : nil
    }

    /// Moves the slider to the level macOS reports, unless the user holds it,
    /// moved it within the policy's hold, or the change is too small to see.
    /// While boosted, a read at full native brightness is Boost's own level and
    /// keeps the thumb where it is; a lower one (the brightness-down key) leaves Boost.
    func applyRead(_ reading: BrightnessLevelReading, policy: BrightnessSyncPolicy = .init()) {
        if isBoosted, reading.level >= 1 - Self.fullLevelTolerance { return }
        guard !isTracking, let target = policy.position(
            for: reading,
            scale: effectiveScale,
            current: position,
            lastUserEdit: lastUserEdit,
            now: clock()
        ) else { return }
        isApplyingRead = true
        position = target
        isApplyingRead = false
    }

    func applyScale(_ newScale: BrightnessScale) {
        guard newScale != scale else { return }
        scale = newScale
    }
}

/// Brightness of each external display, 0...1, keyed by display UUID.
///
/// In a normal launch `BoostController` sets `applyHandler`, so a slider change
/// reaches the display (natively, over DDC or as a shade), and fills in the
/// levels and methods `ExternalBrightnessController` knows through `applyRead`.
/// Without a handler (samples, previews) the sliders change this store only.
final class ExternalBrightnessStore: ObservableObject {
    @Published var levels: [String: Double]
    /// How each display's brightness is changed; missing until it is known.
    @Published var methods: [String: ExternalBrightnessMethod]

    /// Runs after the user set a level, with the display UUID and the clamped level.
    var applyHandler: ((String, Double) -> Void)?

    init(levels: [String: Double] = [:], methods: [String: ExternalBrightnessMethod] = [:]) {
        self.levels = levels
        self.methods = methods
    }

    func level(for displayID: String) -> Double {
        levels[displayID] ?? 1
    }

    func method(for displayID: String) -> ExternalBrightnessMethod? {
        methods[displayID]
    }

    /// The user's change: stored, then applied to the display.
    func setLevel(_ level: Double, for displayID: String) {
        let level = min(max(level, 0), 1)
        levels[displayID] = level
        applyHandler?(displayID, level)
    }

    /// What the display reports (or the shade holds): stored, never applied back.
    func applyRead(level: Double?, method: ExternalBrightnessMethod, for displayID: String) {
        if let level, level.isFinite {
            let level = min(max(level, 0), 1)
            if levels[displayID] != level { levels[displayID] = level }
        }
        if methods[displayID] != method { methods[displayID] = method }
    }

    /// Drops displays that are gone.
    func retain(only displayIDs: Set<String>) {
        let keep = { (key: String) in displayIDs.contains(key) }
        if levels.keys.contains(where: { !keep($0) }) { levels = levels.filter { keep($0.key) } }
        if methods.keys.contains(where: { !keep($0) }) { methods = methods.filter { keep($0.key) } }
    }

    /// One display's level, so views can bind to it with `$store[levelFor: id]`.
    subscript(levelFor displayID: String) -> Double {
        get { level(for: displayID) }
        set { setLevel(newValue, for: displayID) }
    }
}

/// What Boost is doing, for the popover and Settings. Only `BoostController`
/// changes it; samples and previews set it once.
final class BoostStatusStore: ObservableObject {
    @Published private(set) var status: BoostStatus

    init(status: BoostStatus = .off) {
        self.status = status
    }

    func update(_ status: BoostStatus) {
        guard status != self.status else { return }
        self.status = status
    }
}
