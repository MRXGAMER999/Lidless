import Foundation
import LidlessCore

/// What VoiceOver reads for the built-in display's brightness. The screen shows
/// the Boost range in gold and its estimate as "≈ N nits"; these say both in
/// words, so neither the colour nor the symbol carries the meaning.
///
/// Returns resolved strings (not `Text`) so tests can check them; views pass
/// their environment's locale.
nonisolated enum BrightnessAccessibility {
    /// The slider's value: "70%, about 350 nits", "160%, Boost, about 800 nits".
    static func sliderValue(position: Double, scale: BrightnessScale, locale: Locale = .current) -> String {
        let percent = scale.displayPercent(position)
        // A plain Int makes the key "%lld nits", so translators can pluralize it.
        let nits = scale.displayNits(position)
        return scale.isBoosted(position)
            ? String(
                localized: "\(percent, format: .percent), Boost, about \(nits) nits",
                locale: locale,
                comment: "VoiceOver value of the built-in brightness slider while boosted, e.g. “160%, Boost, about 800 nits”. The first variable is the brightness in percent (above 100%), the second the estimated brightness in nits. “Boost” is the feature that makes the screen brighter than normal."
            )
            : String(
                localized: "\(percent, format: .percent), about \(nits) nits",
                locale: locale,
                comment: "VoiceOver value of the built-in brightness slider, e.g. “70%, about 350 nits”. The first variable is the brightness in percent, the second the estimated brightness in nits."
            )
    }

    /// The readout beside the card's title: "70%", or "160%, Boost" in the
    /// Boost range (shown on screen only by its gold colour).
    static func readout(position: Double, scale: BrightnessScale, locale: Locale = .current) -> String {
        let percent = scale.displayPercent(position)
        return scale.isBoosted(position)
            ? String(
                localized: "\(percent, format: .percent), Boost",
                locale: locale,
                comment: "VoiceOver reading of the built-in display card's brightness percentage while boosted, e.g. “160%, Boost”. The variable is the brightness in percent."
            )
            : percent.formatted(.percent.locale(locale))
    }

    /// The hint under the slider without its symbols: "About 350 nits." and,
    /// when Boost can be used, how to reach it.
    static func hint(nits: Int, canBoost: Bool, locale: Locale = .current) -> String {
        canBoost
            ? String(
                localized: "About \(nits) nits. Drag past the line to boost.",
                locale: locale,
                comment: "VoiceOver reading of the hint under the built-in brightness slider (shown as “≈ 350 nits · Drag past the line to boost”); the variable is the estimated brightness in nits"
            )
            : String(
                localized: "About \(nits) nits.",
                locale: locale,
                comment: "VoiceOver reading of the hint under the built-in brightness slider when Boost is off (shown as “≈ 350 nits”); the variable is the estimated brightness in nits"
            )
    }

    /// The Boost callout without its symbols: "Boost on, about 800 nits. Uses more battery …".
    static func boostOnCallout(nits: Int, locale: Locale = .current) -> String {
        String(
            localized: "Boost on, about \(nits) nits. Uses more battery and heat. Steps back by itself if your Mac gets hot.",
            locale: locale,
            comment: "VoiceOver reading of the popover's Boost callout (shown as “Boost on · ≈ 800 nits. Uses more battery and heat. …”); the variable is the estimated brightness in nits"
        )
    }
}
