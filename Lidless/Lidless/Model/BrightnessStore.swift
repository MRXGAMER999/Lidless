import Combine
import Foundation
import LidlessCore

/// Built-in screen brightness and Boost, as shown by the popover slider.
///
/// Kept separate from the other stores so that dragging the slider only
/// redraws the brightness card.
final class BrightnessStore: ObservableObject {
    /// Slider position, 0...150. Past 100 is Boost.
    @Published var position: Double
    @Published var scale: BrightnessScale
    /// Settings › Brightness › "Boost allowed".
    @Published var boostAllowed: Bool

    init(position: Double = 70, scale: BrightnessScale = .init(normalMaxNits: 600, ceilingNits: 1000), boostAllowed: Bool = true) {
        self.position = position
        self.scale = scale
        self.boostAllowed = boostAllowed
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
}

/// Brightness of each external display, 0...1, keyed by display UUID.
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
