import Foundation

/// Events for `BoostMachine`.
public enum BoostEvent: Sendable, Equatable {
    /// The factor the slider asks for (`BrightnessScale.boostFactor`), 1 = no Boost.
    case request(factor: Double)
    /// The guard rails changed.
    case conditions(BoostConditions, BoostSettings)
    /// The overlay engine reported the screen's current EDR headroom
    /// (`maximumExtendedDynamicRangeColorComponentValue`) while it is up.
    case headroom(Double)
    /// The overlay window could not be created or lost its screen.
    case engineFailed
    /// About every 0.25 s while not idle.
    case tick
    /// The panic key, Desk Mode engaging, sleep: drop the overlay now.
    case teardown
}

/// What the app must do.
public enum BoostCommand: Sendable, Equatable {
    /// Put the overlay up (if it isn't) and ramp to `factor` over `rampSeconds`.
    case show(factor: Double, rampSeconds: Double)
    /// Remove the overlay (ramp to 1 first when `rampSeconds` > 0).
    case hide(rampSeconds: Double)
    /// Tell the user once: "Brightness Boost paused" (hot or battery).
    case notifyPaused(BoostBlock)
    /// The popover shows this as the Boost state.
    case publish(BoostStatus)
}

/// What the popover and Settings show about Boost.
public enum BoostStatus: Sendable, Equatable {
    case off
    /// Waiting for macOS to give the screen EDR headroom.
    case engaging
    case on(factor: Double)
    /// Paused or suspended, with the reason.
    case blocked(BoostBlock)
    /// macOS didn't give headroom after three tries; retry on the next request.
    case unavailable
}

/// Boost's engine logic. Pure and deterministic; the app feeds events with a
/// monotonic `now` and runs the commands.
///
/// - The factor is `min(requested, maxFactor, thermal cap, 0.98 × headroom)`,
///   and never below 1. Headroom caps it from the first frame: until the engine
///   reports headroom for the overlay that is up, the factor is 1 (the overlay
///   is up and asks macOS for EDR, but multiplies by 1), then it follows
///   0.98 × headroom as macOS ramps it (phase4-research.md §5.1).
/// - While engaging, the factor stays 1 until the headroom reaches
///   `wantedFactor` (what the engine asks macOS for) or `headroomHold` runs out, then ramps up once. Following macOS's headroom
///   ramp step by step made the screen go bright, dip while macOS moved the
///   backlight, then bright again (M5 Pro, macOS 27).
/// - `engaging` → `on` when the reported headroom reaches the (capped) request
///   minus 0.02 and the factor is visible (see below). At `engageTimeout` it is
///   `on` if the factor is above 1.01 (or the whole of a smaller request);
///   otherwise the try failed: hide, back off for `backoff`, retry; three
///   strikes → `unavailable` until a new request.
/// - Blocks hide at once (no ramp) and publish `.blocked`; when they clear and
///   a factor > 1 is still requested, show again. Suspensions (asleep, locked,
///   reconfiguring, Desk Mode) never count as strikes.
/// - Requests are coalesced: at most one `.show` per `minUpdateInterval`.
///
/// Details the list above leaves open:
/// - Shows always ramp (`rampSeconds`, the overlay starts each engagement at 1).
///   Hides ramp only when the user asked for less (a request of 1) or an engage
///   try failed; blocks, `.teardown` and `.engineFailed` hide with no ramp.
/// - `.teardown` hides at once and publishes `.off`; nothing brings the overlay
///   back (not even conditions clearing) until the next `.request` above 1. It
///   also clears strikes and back-off.
/// - A request of 1 ends the attempt: strikes and back-off are cleared too.
/// - `.engineFailed` while the overlay is up counts as a strike, like a timeout
///   with no headroom. Blocks keep a running back-off (it keeps counting) and
///   `unavailable`; they never add or clear strikes. A successful engage clears them.
/// - Status is `.off` while no factor above 1 is requested, whatever blocks;
///   `.blocked` wins over everything else.
/// - A factor is *visible* when it is above 1.005, or is the whole request
///   (a request that small is met). `.on(factor:)` is only ever published with
///   a visible factor: an overlay that is up with a smaller one (headroom
///   under the request) publishes `.engaging`, since headroom may still rise.
/// - Back-off (hidden between tries) publishes `.unavailable`, not `.engaging`:
///   nothing is up, and the popover says "macOS isn't allowing Boost right
///   now." until the next try shows the overlay again. Ticks keep running so
///   back-off ends by itself.
/// - Heat and battery pauses (`.hot`, `.lowBattery`) have hysteresis: once the
///   rail clears, the pause stays in effect for `pauseClearHold` and ends only
///   if the rail stayed clear that long (going hot again restarts the hold).
///   A pause-threshold change in Settings drops the hold at once.
/// - `.notifyPaused` goes out once per blocked stretch for each block that
///   `notifies`, only while a factor above 1 is requested (so a request made
///   during a pause notifies then), and never within `noticeCooldown` of the
///   last notice for the same block. The stretch ends when nothing blocks
///   (after the hold).
/// - Headroom only counts while the overlay is up, and is forgotten when it
///   hides. The factor never goes below 1, so with headroom under 1/0.98 it is 1.
/// - Before the first `.conditions`, the machine assumes `BoostConditions()` and
///   `BoostSettings.defaults` (nothing blocks).
/// - `needsTicks` is true exactly when a `.tick` can change something; the app
///   reads it after every event and runs its tick timer only while it is true.
public struct BoostMachine: Sendable, Equatable {
    public struct Configuration: Sendable, Equatable {
        /// Absolute ceiling on the factor (≈ 1000 / 600).
        public var maxFactor: Double
        public var engageTimeout: TimeInterval
        public var backoff: TimeInterval
        public var maxStrikes: Int
        public var rampSeconds: Double
        public var minUpdateInterval: TimeInterval
        /// How long the heat or battery rail must stay clear before its pause
        /// ends: readings that flap around a threshold don't flap Boost.
        public var pauseClearHold: TimeInterval
        /// The "Brightness Boost paused" notice for the same reason never goes
        /// out twice within this.
        public var noticeCooldown: TimeInterval

        /// While engaging, how long the factor stays 1 waiting for the headroom
        /// to reach the target; 0 follows the headroom from the start.
        public var headroomHold: TimeInterval

        public init(maxFactor: Double = 1.67, headroomHold: TimeInterval = 4, engageTimeout: TimeInterval = 10, backoff: TimeInterval = 30, maxStrikes: Int = 3, rampSeconds: Double = 0.4, minUpdateInterval: TimeInterval = 0.25, pauseClearHold: TimeInterval = 10, noticeCooldown: TimeInterval = 60) {
            self.maxFactor = maxFactor
            self.headroomHold = headroomHold
            self.engageTimeout = engageTimeout
            self.backoff = backoff
            self.maxStrikes = maxStrikes
            self.rampSeconds = rampSeconds
            self.minUpdateInterval = minUpdateInterval
            self.pauseClearHold = pauseClearHold
            self.noticeCooldown = noticeCooldown
        }
    }

    public var configuration: Configuration
    public private(set) var status: BoostStatus

    private enum Phase: Sendable, Equatable {
        /// Hidden, and not waiting for anything.
        case idle
        /// The overlay is up and macOS is ramping headroom.
        case engaging(since: TimeInterval)
        case on
        /// Hidden after a strike; try again at `until`.
        case backoff(until: TimeInterval)
        /// Hidden after `maxStrikes`; waits for a new request.
        case unavailable
    }

    private var phase = Phase.idle
    /// The slider's factor, ≥ 1.
    private var requested = 1.0
    /// Set by `.teardown`, cleared by a request above 1.
    private var tornDown = false
    private var conditions = BoostConditions()
    private var settings = BoostSettings.defaults
    /// What `BoostGuard` says about the current conditions.
    private var guardBlock: BoostBlock?
    /// The heat or battery pause in effect, kept through its hold after the
    /// rail clears.
    private var heldPause: BoostBlock?
    /// When the held pause ends; set while its rail is clear, nil otherwise.
    private var pauseEndsAt: TimeInterval?
    /// The block in effect: `guardBlock`, else a held pause.
    private var block: BoostBlock?
    private var strikes = 0
    /// The latest headroom the engine reported for the overlay that is up.
    private var headroom: Double?
    /// While engaging: the factor stays 1 until then, unless the headroom
    /// reaches the target first. Nil once the hold is over.
    private var holdEndsAt: TimeInterval?
    /// The factor last sent with `.show`; nil while hidden.
    private var shown: Double?
    private var lastShow = -Double.infinity
    /// Blocks already announced in the current blocked stretch.
    private var notified: [BoostBlock] = []
    /// When each block's notice last went out.
    private var lastNotice: [BoostBlock: TimeInterval] = [:]

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
        status = .off
    }

    /// True exactly when a `.tick` can change something: engaging (the
    /// timeout, or a coalesced show), backing off, a coalesced show while on,
    /// or a heat or battery pause whose hold is running. False while off, idle,
    /// unavailable, on and settled, or blocked with nothing else pending.
    public var needsTicks: Bool {
        guard requested > 1, !tornDown else { return false }
        if block == nil {
            switch phase {
            case .engaging, .backoff: return true
            case .on: if factor != shown { return true }
            case .idle, .unavailable: break
            }
        }
        // The hold matters only when its end lifts the block.
        return pauseEndsAt != nil && guardBlock == nil
    }

    public mutating func handle(_ event: BoostEvent, now: TimeInterval) -> [BoostCommand] {
        endHeldPause(now)
        var hideRamp = configuration.rampSeconds
        switch event {
        case .request(let factor):
            requested = factor.isNaN ? 1 : max(1, factor)
            if requested > 1 {
                tornDown = false
                if phase == .unavailable { reset() }
            } else {
                reset()
            }
        case .conditions(let newConditions, let newSettings):
            if newSettings.pauseAtHeat != settings.pauseAtHeat || newSettings.pauseBelowBattery != settings.pauseBelowBattery {
                // The user moved a threshold: it applies at once.
                heldPause = nil
                pauseEndsAt = nil
            }
            conditions = newConditions
            settings = newSettings
            updateBlock(now)
            if block != nil { hideRamp = 0 }
        case .headroom(let value):
            guard shown != nil, value.isFinite, value > 0 else { break }
            headroom = value
        case .engineFailed:
            guard shown != nil else { break }
            hideRamp = 0
            strike(now)
        case .tick:
            break
        case .teardown:
            tornDown = true
            hideRamp = 0
            reset()
        }

        advance(now)
        var commands: [BoostCommand] = []
        render(now, hideRamp: hideRamp, into: &commands)
        announce(now, into: &commands)
        let newStatus = currentStatus
        if newStatus != status {
            status = newStatus
            commands.append(.publish(newStatus))
        }
        return commands
    }

    // MARK: Engine state

    private var wantsBoost: Bool { requested > 1 && !tornDown && block == nil }

    private var isUp: Bool {
        switch phase {
        case .engaging, .on: true
        case .idle, .backoff, .unavailable: false
        }
    }

    /// The headroom to ask macOS for up front: the ceiling (under the heat
    /// cap), not just the slider, so dragging further doesn't make macOS move
    /// the backlight again mid-Boost.
    public var wantedFactor: Double {
        max(1, min(configuration.maxFactor, BoostGuard.thermalCap(conditions.thermal, settings: settings)))
    }

    /// The request under the fixed and thermal caps (headroom aside).
    private var target: Double {
        max(1, min(requested, configuration.maxFactor, BoostGuard.thermalCap(conditions.thermal, settings: settings)))
    }

    /// What the overlay should show: `target` under 0.98 × the reported
    /// headroom, and 1 until headroom is reported.
    private var factor: Double {
        guard let headroom, holdEndsAt == nil else { return 1 }
        return max(1, min(target, Self.headroomShare * headroom))
    }

    /// True when `factor` is a boost worth calling one: above 1 + `gain`, or
    /// all of a target that small.
    private func isVisible(gain: Double) -> Bool {
        let factor = self.factor
        return factor > 1 && (factor > 1 + gain || factor >= target)
    }

    /// Anything above the available headroom clips highlights (boost.md §6).
    static let headroomShare = 0.98
    /// How close to the target the headroom must come to count as engaged.
    static let engageTolerance = 0.02
    /// Below this gain over 1 the overlay isn't published as on.
    static let visibleGain = 0.005
    /// Below this gain over 1 an engage try that timed out failed.
    static let timeoutGain = 0.01

    private mutating func reset() {
        phase = .idle
        strikes = 0
    }

    private mutating func strike(_ now: TimeInterval) {
        strikes += 1
        phase = strikes >= configuration.maxStrikes ? .unavailable : .backoff(until: now + configuration.backoff)
    }

    /// Recomputes the block from the conditions, holding a heat or battery
    /// pause for `pauseClearHold` after its rail clears.
    private mutating func updateBlock(_ now: TimeInterval) {
        guardBlock = BoostGuard.block(conditions, settings: settings)
        if let pause = BoostGuard.pause(conditions, settings: settings) {
            heldPause = pause
            pauseEndsAt = nil
        } else if heldPause != nil, pauseEndsAt == nil {
            pauseEndsAt = now + configuration.pauseClearHold
        }
        block = guardBlock ?? heldPause
    }

    /// Ends a held pause whose hold ran out, under the conditions that were
    /// in force then (before the event being handled), so the result doesn't
    /// depend on how often ticks come.
    private mutating func endHeldPause(_ now: TimeInterval) {
        guard let pauseEndsAt, now >= pauseEndsAt else { return }
        heldPause = nil
        self.pauseEndsAt = nil
        block = guardBlock
        if block == nil { notified = [] }
    }

    /// Moves the phase along after an event: hides for blocks, retries after
    /// back-off, starts engaging, and settles engaging into on or a strike.
    private mutating func advance(_ now: TimeInterval) {
        guard wantsBoost else {
            if isUp { phase = .idle }
            return
        }
        if case .backoff(let until) = phase, now >= until { phase = .idle }
        if phase == .idle {
            phase = .engaging(since: now)
            holdEndsAt = configuration.headroomHold > 0 ? now + configuration.headroomHold : nil
        }
        guard case .engaging(let since) = phase else {
            holdEndsAt = nil
            return
        }
        // The engine asks macOS for `wantedFactor`: wait for all of it, so
        // macOS is done moving the backlight before the screen brightens.
        if let end = holdEndsAt, now >= end || (headroom ?? 0) >= wantedFactor - Self.engageTolerance {
            holdEndsAt = nil
        }
        if let headroom, headroom >= target - Self.engageTolerance, isVisible(gain: Self.visibleGain) {
            phase = .on
            strikes = 0
        } else if now - since >= configuration.engageTimeout {
            if isVisible(gain: Self.timeoutGain) {
                phase = .on
                strikes = 0
            } else {
                strike(now)
            }
        }
    }

    /// Brings the overlay in line with the phase. Hides go out at once; shows
    /// wait for `minUpdateInterval` since the last one (a later tick sends them).
    private mutating func render(_ now: TimeInterval, hideRamp: Double, into commands: inout [BoostCommand]) {
        guard isUp else {
            if shown != nil {
                commands.append(.hide(rampSeconds: hideRamp))
                shown = nil
                headroom = nil
            }
            return
        }
        let factor = self.factor
        guard factor != shown, now - lastShow >= configuration.minUpdateInterval else { return }
        commands.append(.show(factor: factor, rampSeconds: configuration.rampSeconds))
        shown = factor
        lastShow = now
    }

    private mutating func announce(_ now: TimeInterval, into commands: inout [BoostCommand]) {
        guard let block else {
            notified = []
            return
        }
        guard block.notifies, requested > 1, !tornDown, !notified.contains(block) else { return }
        notified.append(block)
        if let last = lastNotice[block], now - last < configuration.noticeCooldown { return }
        lastNotice[block] = now
        commands.append(.notifyPaused(block))
    }

    private var currentStatus: BoostStatus {
        if requested <= 1 || tornDown { return .off }
        if let block { return .blocked(block) }
        switch phase {
        case .on: return isVisible(gain: Self.visibleGain) ? .on(factor: factor) : .engaging
        case .backoff, .unavailable: return .unavailable
        case .idle, .engaging: return .engaging
        }
    }
}

/// "≈ N nits" while boosted: macOS allots headroom ≈ peak / SDR white.
public enum NitsEstimate {
    /// Panel peak used by macOS for headroom, in nits.
    public static let panelPeak = 1600.0
    /// SDR white from reported headroom; nil when headroom is at the 16× cap or ≤ 1.
    public static func sdrWhite(headroom: Double) -> Double? {
        guard headroom > 1, headroom < 16 else { return nil }
        return panelPeak / headroom
    }
}
