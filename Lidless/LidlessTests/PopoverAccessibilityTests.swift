import Foundation
import LidlessCore
import Testing
@testable import Lidless

/// What VoiceOver reads in the popover in place of colour and symbols.
/// A fixed en_US locale keeps digits and separators stable; the strings are
/// the catalog's development-language text.
@MainActor
struct PopoverAccessibilityTests {
    private let enUS = Locale(identifier: "en_US")
    /// The previews' 500 nit panel with a 1,000 nit ceiling.
    private let scale = BrightnessScale(normalMaxNits: 500, ceilingNits: 1000)

    @Test func `normal range reads percent and nits`() {
        #expect(BrightnessAccessibility.sliderValue(position: 70, scale: scale, locale: enUS) == "70%, about 350 nits")
    }

    @Test func `boost range is named`() {
        let value = BrightnessAccessibility.sliderValue(position: 130, scale: scale, locale: enUS)
        #expect(value == "160%, Boost, about 800 nits")
    }

    @Test func `the boost line itself is not boost`() {
        #expect(BrightnessAccessibility.sliderValue(position: 100, scale: scale, locale: enUS) == "100%, about 500 nits")
        #expect(BrightnessAccessibility.readout(position: 100, scale: scale, locale: enUS) == "100%")
    }

    @Test func `readout names boost only when boosted`() {
        #expect(BrightnessAccessibility.readout(position: 40, scale: scale, locale: enUS) == "40%")
        #expect(BrightnessAccessibility.readout(position: 150, scale: scale, locale: enUS) == "200%, Boost")
    }

    @Test func `values follow the locale`() {
        let value = BrightnessAccessibility.sliderValue(position: 150, scale: scale, locale: Locale(identifier: "de_DE"))
        #expect(value.contains("1.000"))
        #expect(value.contains("200 %"))
    }

    @Test func `hint and callout drop the approximately sign`() {
        let hint = BrightnessAccessibility.hint(nits: 350, canBoost: true, locale: enUS)
        #expect(hint == "About 350 nits. Drag past the line to boost.")
        #expect(BrightnessAccessibility.hint(nits: 350, canBoost: false, locale: enUS) == "About 350 nits.")
        let callout = BrightnessAccessibility.boostOnCallout(nits: 800, locale: enUS)
        #expect(callout.hasPrefix("Boost on, about 800 nits."))
        #expect(!hint.contains("≈") && !callout.contains("≈") && !callout.contains("·"))
    }

    @Test func `status line is spoken as a list`() {
        let spoken = StatusSegment.spokenList([.lidOpen, .onPower], locale: enUS)
        #expect(spoken == "Lid open, On power")
        #expect(!spoken.contains("·"))
    }
}
