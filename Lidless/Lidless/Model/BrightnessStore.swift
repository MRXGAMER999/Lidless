import Combine
import Foundation
import LidlessCore

/// Built-in screen brightness and Boost, as shown by the popover slider.
///
/// Kept separate from the other stores so that dragging the slider only
/// redraws the brightness card.
///
/// Live mode (Phase 2) only reads: moving the slider changes this store, not
/// the screen, until Phase 4. Reads wait while the slider is held, resume 2 s
/// after the last touch and move the thumb back to macOS's level.
final class BrightnessStore: ObservableObject {
    /// Slider position, 0...150. Past 100 is Boost.
    @Published var position: Double {
        didSet { if !isApplyingRead { lastUserEdit = clock() } }
    }
    @Published var scale: BrightnessScale
    /// Settings › Brightness › "Boost allowed".
    @Published var boostAllowed: Bool

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
    func applyRead(_ reading: BrightnessLevelReading, policy: BrightnessSyncPolicy = .init()) {
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
/// In live mode the levels stay at the default of 1.0 per display: reading and
/// applying external brightness arrive in Phase 4 (DDC, or native for Apple
/// displays), so until then its sliders change this store only.
final class ExternalBrightnessStore: ObservableObject {
    @Published var levels: [String: Double]

    init(levels: [String: Double] = [:]) {
        self.levels = levels
    }

    func level(for displayID: String) -> Double {
        levels[displayID] ?? 1
    }

    func setLevel(_ level: Double, for displayID: String) {
        levels[displayID] = min(max(level, 0), 1)
    }

    /// One display's level, so views can bind to it with `$store[levelFor: id]`.
    subscript(levelFor displayID: String) -> Double {
        get { level(for: displayID) }
        set { setLevel(newValue, for: displayID) }
    }
}
