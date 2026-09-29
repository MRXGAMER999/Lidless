import AppKit
import SwiftUI

/// Colours from the design (design-spec §1.1–1.2), sRGB exactly as authored.
///
/// Adaptive tokens are `NSColor(name:dynamicProvider:)` colours, so SwiftUI
/// resolves them against each view's own appearance: the popover in dark mode,
/// or a subtree forced dark with `.environment(\.colorScheme, .dark)`.
/// Only the popover's Desk-Mode-on state is designed in dark; dark values
/// marked "derived" are proposals in the same language.
nonisolated enum Palette {
    // MARK: Brand

    static let gold = fixed(0xFFBF00)
    static let goldBorderSelected = fixed(0xF5B400)
    static let goldTokenBorder = fixed(0xF2C94C)
    static let goldOnDark = fixed(0xFFD466)
    static let cream = fixed(0xFFF4D6)
    static let creamSelected = fixed(0xFFFBEF)
    static let sunWhite = fixed(0xFFF8E6)
    static let brown = fixed(0x5A3B00)
    static let amberArrow = fixed(0xB07A00)
    static let boostRegion = fixed(0xFFBF00, 0.30)
    static let boostAvailable = fixed(0xFFBF00, 0.22)
    static let goldGlow = fixed(0xFFBF00, 0.35)
    static let primaryButtonShadow = fixed(0xA06E00, 0.35)
    static let goldDeepFixed = fixed(0x8A5A00)
    /// "Boost" label, boosted readout, links. Derived for dark: #8A5A00 is unreadable there.
    static let goldDeep = adaptive("goldDeep", light: srgb(0x8A5A00), dark: srgb(0xFFD466))

    // MARK: Ink and neutrals

    /// #1B2531 in both appearances: toggle knob, keycap text, dark buttons.
    static let ink = fixed(0x1B2531)
    static let heroBackground = fixed(0x141B24)
    static let deviceBody = fixed(0x2A3542)
    static let screenOn = fixed(0x3B4A5E)
    static let screenOff = fixed(0x0D1117)
    /// Stronger with Increase Contrast (as `textOnDark2`).
    static let textOnDark = contrastAware("textOnDark", srgb(0xB8C0CC), increased: srgb(0xE6E9EE))
    static let textOnDark2 = fixed(0xE6E9EE)
    static let trackNormalOnDark = fixed(0xE8ECF2)
    static let deckLight = fixed(0xE6E7EA)
    static let deckMuted = fixed(0xC9CDD3)
    static let keyDark = fixed(0x222C38)
    static let keyDarkEdge = fixed(0x0B0F14)
    static let white = fixed(0xFFFFFF)

    static let textPrimary = adaptive("textPrimary", light: srgb(0x1B2531), dark: srgb(0xF5F5F7))
    /// Chip text, body copy on light surfaces.
    static let text2 = adaptive("text2", light: srgb(0x2B3440), dark: srgb(0xE5E5EA))
    /// Status line, section label, hints. Darker (lighter in dark) with Increase Contrast.
    static let text3 = adaptive(
        "text3", light: srgb(0x3A4452), dark: srgb(0xC8C8D2),
        highContrastLight: srgb(0x27303C), highContrastDark: srgb(0xE5E5EA)
    )
    /// Helper text, row subtitles, small slider icons. Darker (lighter in dark) with Increase Contrast.
    static let text4 = adaptive(
        "text4", light: srgb(0x4A5260), dark: srgb(0xC8C8D2),
        highContrastLight: srgb(0x2B3440), highContrastDark: srgb(0xE5E5EA)
    )
    /// External display row icons.
    static let rowIcon = adaptive("rowIcon", light: srgb(0x1B2531), dark: srgb(0xE5E5EA))
    /// The built-in readout when it says "Off" (ink in Main.dc.html, grey in DeskDark).
    static let readoutOff = adaptive("readoutOff", light: srgb(0x1B2531), dark: srgb(0xC8C8D2))

    // MARK: Translucent neutrals

    static let track = adaptive(
        "track", light: srgb(0x1B2531, 0.12), dark: srgb(0xFFFFFF, 0.16),
        highContrastLight: srgb(0x1B2531, 0.3), highContrastDark: srgb(0xFFFFFF, 0.35)
    )
    /// Normal part of the built-in slider. Derived for dark: gold there would hide the Boost split.
    static let sliderFill = adaptive("sliderFill", light: srgb(0x1B2531), dark: srgb(0xE6E9EE))
    /// External display mini sliders (gold in DeskDark).
    static let miniSliderFill = adaptive("miniSliderFill", light: srgb(0x1B2531), dark: srgb(0xFFBF00))
    static let boostMarker = adaptive(
        "boostMarker", light: srgb(0x1B2531, 0.45), dark: srgb(0xFFFFFF, 0.5),
        highContrastLight: srgb(0x1B2531, 0.8), highContrastDark: srgb(0xFFFFFF, 0.85)
    )
    /// The built-in slider's thumb ring (on a white thumb in both appearances).
    static let thumbRing = contrastAware("thumbRing", srgb(0x1B2531, 0.15), increased: srgb(0x1B2531, 0.55))
    static let fill7 = fixed(0x1B2531, 0.07)
    /// Empty-state and "Not set" dashed borders, inactive page dots. Stronger with Increase Contrast.
    static let dashedBorder = adaptive(
        "dashedBorder", light: srgb(0x1B2531, 0.25), dark: srgb(0xFFFFFF, 0.25),
        highContrastLight: srgb(0x1B2531, 0.6), highContrastDark: srgb(0xFFFFFF, 0.6)
    )
    static let cardUnselected = fixed(0x1B2531, 0.10)
    static let divider = adaptive(
        "divider", light: srgb(0x000000, 0.07), dark: srgb(0xFFFFFF, 0.1),
        highContrastLight: srgb(0x000000, 0.3), highContrastDark: srgb(0xFFFFFF, 0.35)
    )
    static let toggleOffTrack = fixed(0x787880, 0.30)

    // MARK: Popover panel

    /// Wash over the AppKit `.popover` material on macOS 12–25.
    static let popoverWash = adaptive("popoverWash", light: srgb(0xFFFFFF, 0.58), dark: srgb(0x1C1C24, 0.64))
    /// Wash over the material and Liquid Glass on macOS 26+, lighter than the
    /// design's 0.58 / 0.64 because both layers already tint.
    static let popoverGlassWash = adaptive("popoverGlassWash", light: srgb(0xFFFFFF, 0.06), dark: srgb(0x1C1C24, 0.47))
    static let popoverBorder = adaptive(
        "popoverBorder", light: srgb(0xFFFFFF, 0.8), dark: srgb(0xFFFFFF, 0.2),
        highContrastDark: srgb(0xFFFFFF, 0.5)
    )
    static let popoverRing = adaptive(
        "popoverRing", light: srgb(0x000000, 0.14), dark: srgb(0x000000, 0.6),
        highContrastLight: srgb(0x000000, 0.5), highContrastDark: srgb(0x000000, 0.8)
    )
    /// Opaque panel fill with Reduce Transparency, in place of the material and
    /// its wash. Derived: roughly the washed material over a neutral backdrop.
    static let popoverSolid = adaptive("popoverSolid", light: srgb(0xF6F5F2), dark: srgb(0x222229))
    static let popoverInsetTop = adaptive("popoverInsetTop", light: srgb(0xFFFFFF), dark: srgb(0xFFFFFF, 0.4))
    static let popoverInsetBottom = adaptive("popoverInsetBottom", light: srgb(0xFFFFFF, 0.4), dark: srgb(0xFFFFFF, 0.06))
    static let popoverShadowFar = adaptive("popoverShadowFar", light: srgb(0x3C280A, 0.25), dark: srgb(0x000000, 0.5))
    static let popoverShadowNear = adaptive("popoverShadowNear", light: srgb(0x3C280A, 0.12), dark: .clear)

    // MARK: Surfaces inside the popover

    static let glassCardFill = adaptive("glassCardFill", light: srgb(0xFFFFFF, 0.6), dark: srgb(0xFFFFFF, 0.08))
    static let glassCardBorder = adaptive(
        "glassCardBorder", light: srgb(0xFFFFFF, 0.8), dark: srgb(0xFFFFFF, 0.1),
        highContrastLight: srgb(0x1B2531, 0.3), highContrastDark: srgb(0xFFFFFF, 0.4)
    )
    static let glassCardInset = adaptive("glassCardInset", light: srgb(0xFFFFFF), dark: srgb(0xFFFFFF, 0.12))

    static let circleButtonFill = adaptive("circleButtonFill", light: srgb(0xFFFFFF, 0.6), dark: srgb(0xFFFFFF, 0.12))
    static let circleButtonBorder = adaptive(
        "circleButtonBorder", light: srgb(0xFFFFFF, 0.8), dark: srgb(0xFFFFFF, 0.16),
        highContrastLight: srgb(0x1B2531, 0.35), highContrastDark: srgb(0xFFFFFF, 0.45)
    )
    static let circleButtonInset = adaptive("circleButtonInset", light: srgb(0xFFFFFF), dark: srgb(0xFFFFFF, 0.2))
    /// `0 1px 3px` under white buttons and capsules; none in dark.
    static let buttonShadow = adaptive("buttonShadow", light: srgb(0x000000, 0.08), dark: .clear)

    static let deskCardFill = adaptive("deskCardFill", light: srgb(0x141B24), dark: srgb(0x0B1017))
    static let deskCardBorder = adaptive("deskCardBorder", light: .clear, dark: srgb(0xFFBF00, 0.35))
    static let deskCardInset = adaptive("deskCardInset", light: srgb(0xFFFFFF, 0.08), dark: srgb(0xFFFFFF, 0.06))
    static let deskCardShadow = adaptive("deskCardShadow", light: srgb(0x141B24, 0.25), dark: .clear)
    static let deskCardGlow = adaptive("deskCardGlow", light: .clear, dark: srgb(0xFFBF00, 0.12))
    static let onDarkHairline = contrastAware("onDarkHairline", srgb(0xFFFFFF, 0.08), increased: srgb(0xFFFFFF, 0.3))

    static let chipFill = adaptive("chipFill", light: srgb(0xFFFFFF, 0.5), dark: srgb(0xFFFFFF, 0.08))
    static let chipBorder = adaptive(
        "chipBorder", light: srgb(0xFFFFFF, 0.7), dark: srgb(0xFFFFFF, 0.12),
        highContrastLight: srgb(0x1B2531, 0.35), highContrastDark: srgb(0xFFFFFF, 0.45)
    )

    static let splitFill = adaptive("splitFill", light: srgb(0xFFFFFF, 0.65), dark: srgb(0xFFFFFF, 0.12))
    static let splitBorder = adaptive(
        "splitBorder", light: srgb(0xFFFFFF, 0.85), dark: srgb(0xFFFFFF, 0.16),
        highContrastLight: srgb(0x1B2531, 0.35), highContrastDark: srgb(0xFFFFFF, 0.45)
    )
    static let splitInset = adaptive("splitInset", light: srgb(0xFFFFFF), dark: srgb(0xFFFFFF, 0.2))
    static let splitDivider = adaptive(
        "splitDivider", light: srgb(0x000000, 0.12), dark: srgb(0xFFFFFF, 0.16),
        highContrastLight: srgb(0x000000, 0.4), highContrastDark: srgb(0xFFFFFF, 0.45)
    )

    /// Derived for dark.
    static let emptyCardFill = adaptive("emptyCardFill", light: srgb(0xFFFFFF, 0.3), dark: srgb(0xFFFFFF, 0.04))

    /// Boost callout. Derived for dark: cream on a dark panel glares.
    static let calloutFill = adaptive("calloutFill", light: srgb(0xFFF4D6), dark: srgb(0xFFBF00, 0.16))
    static let calloutText = adaptive("calloutText", light: srgb(0x5A3B00), dark: srgb(0xFFD466))

    /// White capsule buttons ("Back to 100%", "Check Now", "Back"). Derived for dark.
    static let secondaryButtonFill = adaptive("secondaryButtonFill", light: srgb(0xFFFFFF), dark: srgb(0xFFFFFF, 0.12))
    /// rgba(27,37,49,0.12): "Back to 100%", onboarding "Back".
    static let secondaryButtonBorder = adaptive(
        "secondaryButtonBorder", light: srgb(0x1B2531, 0.12), dark: srgb(0xFFFFFF, 0.16),
        highContrastLight: srgb(0x1B2531, 0.4), highContrastDark: srgb(0xFFFFFF, 0.45)
    )
    /// rgba(27,37,49,0.14): "Check Now" (Settings2-General).
    static let secondaryButtonBorderStrong = adaptive(
        "secondaryButtonBorderStrong", light: srgb(0x1B2531, 0.14), dark: srgb(0xFFFFFF, 0.16),
        highContrastLight: srgb(0x1B2531, 0.4), highContrastDark: srgb(0xFFFFFF, 0.45)
    )
    /// `0 1px 3px` rgba(0,0,0,0.1): "Back to 100%", the HUD's "Turn Back On".
    /// "Check Now" and "Back" use `buttonShadow` (0.08).
    static let secondaryButtonShadow = adaptive("secondaryButtonShadow", light: srgb(0x000000, 0.1), dark: .clear)

    static let appIconShadow = adaptive("appIconShadow", light: srgb(0x785000, 0.25), dark: srgb(0x000000, 0.4))

    // MARK: Keycaps

    static let keyFace = adaptive("keyFace", light: srgb(0xFFFFFF), dark: srgb(0x222C38))
    static let keyBorder = adaptive(
        "keyBorder", light: srgb(0x000000, 0.12), dark: srgb(0xFFFFFF, 0.16),
        highContrastLight: srgb(0x000000, 0.4), highContrastDark: srgb(0xFFFFFF, 0.45)
    )
    static let keyEdge = adaptive("keyEdge", light: srgb(0x000000, 0.12), dark: srgb(0x0B0F14))
    static let keyText = adaptive("keyText", light: srgb(0x1B2531), dark: srgb(0xF5F5F7))
    static let keyAccentBorder = adaptive("keyAccentBorder", light: srgb(0x785000, 0.3), dark: srgb(0xFFFFFF, 0.3))
    static let keyAccentEdge = adaptive("keyAccentEdge", light: srgb(0x785000, 0.3), dark: srgb(0x8A5A00))
    /// The 68/76 pt keycaps sit on dark heroes in both appearances.
    static let keyLargeBorder = fixed(0xFFFFFF, 0.14)

    // MARK: Status

    static let thermalNominal = adaptive("thermalNominal", light: srgb(0x1E8E3E), dark: srgb(0x32D74B))
    /// Dark value derived.
    static let thermalFair = adaptive("thermalFair", light: srgb(0xD99A00), dark: srgb(0xFFD60A))
    /// Not designed: proposed orange.
    static let thermalSerious = adaptive("thermalSerious", light: srgb(0xE8590C), dark: srgb(0xFF9F0A))
    /// Not designed: proposed red.
    static let thermalCritical = adaptive("thermalCritical", light: srgb(0xD93025), dark: srgb(0xFF453A))

    // MARK: Settings and onboarding
    // Designed in light only; the dark values are derived in the popover's dark language.

    /// Window wash, rgba(250,248,244,0.9) over the window's blur.
    static let settingsWindowBg = adaptive("settingsWindowBg", light: srgb(0xFAF8F4, 0.9), dark: srgb(0x1E1E24, 0.9))
    static let settingsCardFill = adaptive("settingsCardFill", light: srgb(0xFFFFFF, 0.84), dark: srgb(0xFFFFFF, 0.08))
    static let settingsCardBorder = adaptive("settingsCardBorder", light: srgb(0xFFFFFF, 0.9), dark: srgb(0xFFFFFF, 0.1))
    /// `0 0 0 1px` ring just outside the card's border.
    static let settingsCardRing = adaptive(
        "settingsCardRing", light: srgb(0x000000, 0.05), dark: srgb(0x000000, 0.3),
        highContrastLight: srgb(0x000000, 0.35), highContrastDark: srgb(0xFFFFFF, 0.35)
    )
    static let settingsCardShadow = adaptive("settingsCardShadow", light: srgb(0x281E0A, 0.06), dark: srgb(0x000000, 0.25))
    /// rgba(27,37,49,0.07): segmented nav track, neutral badges, icon-state chips.
    static let neutralFill = adaptive("neutralFill", light: srgb(0x1B2531, 0.07), dark: srgb(0xFFFFFF, 0.08))
    /// Segmented nav track's `inset 0 1px 2px`.
    static let segmentedTrackInset = adaptive("segmentedTrackInset", light: srgb(0x000000, 0.06), dark: srgb(0x000000, 0.25))
    /// Selected segment's `0 1px 3px`.
    static let segmentedSelectedShadow = adaptive("segmentedSelectedShadow", light: srgb(0x785000, 0.3), dark: srgb(0x000000, 0.35))
    /// TokenMenu pill; its fill and text are `calloutFill` / `calloutText`.
    static let tokenBorder = adaptive(
        "tokenBorder", light: srgb(0xF2C94C), dark: srgb(0xFFBF00, 0.45),
        highContrastLight: srgb(0x8A5A00), highContrastDark: srgb(0xFFD466)
    )
    static let methodCardFill = adaptive("methodCardFill", light: srgb(0xFFFFFF, 0.6), dark: srgb(0xFFFFFF, 0.05))
    static let methodCardSelectedFill = adaptive("methodCardSelectedFill", light: srgb(0xFFFBEF), dark: srgb(0xFFBF00, 0.1))
    static let methodCardBorder = adaptive(
        "methodCardBorder", light: srgb(0x1B2531, 0.1), dark: srgb(0xFFFFFF, 0.12),
        highContrastLight: srgb(0x1B2531, 0.4), highContrastDark: srgb(0xFFFFFF, 0.45)
    )
    /// NumberBadge circle: ink in light, a light wash in dark (ink vanishes on a dark card).
    static let numberBadgeFill = adaptive("numberBadgeFill", light: srgb(0x1B2531), dark: srgb(0xFFFFFF, 0.12))

    // Ceiling slider, on the dark hero in both appearances.
    static let ceilingTrackBg = fixed(0xFFFFFF, 0.07)
    static let ceilingHatch = fixed(0xFFFFFF, 0.14)
    static let ceilingMarker = fixed(0xFFFFFF, 0.5)

    // MARK: On dark heroes (both appearances)

    static let onDarkToggleOff = fixed(0xFFFFFF, 0.2)
    /// Off track of the Settings heroes' switches (Settings2-DeskMode: rgba(255,255,255,0.18)).
    static let onDarkToggleOffSettingsHero = fixed(0xFFFFFF, 0.18)
    static let onDarkToggleDisabledTrack = fixed(0xFFFFFF, 0.1)
    static let onDarkToggleDisabledKnob = fixed(0xFFFFFF, 0.35)
    static let onDarkGhostFill = fixed(0xFFFFFF, 0.1)
    static let onDarkGhostBorder = fixed(0xFFFFFF, 0.18)
    static let onDarkChip = fixed(0xFFFFFF, 0.09)
    static let onDarkChipActive = fixed(0xFFBF00, 0.18)

    // MARK: Builders

    private static func fixed(_ hex: UInt32, _ alpha: CGFloat = 1) -> Color {
        Color(nsColor: srgb(hex, alpha))
    }

    private static func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Every appearance an adaptive token tells apart. The high-contrast names
    /// only work for matching: macOS picks them when Increase Contrast is on.
    private static let appearanceNames: [NSAppearance.Name] = [
        .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
    ]

    // Built in a nonisolated context on purpose: AppKit may call the provider
    // off the main thread while drawing, and a main-actor closure would trap.
    /// - Parameters:
    ///   - highContrastLight, highContrastDark: Used with Increase Contrast
    ///     (design-spec §13); nil keeps the normal value.
    private static func adaptive(
        _ name: String,
        light: NSColor,
        dark: NSColor,
        highContrastLight: NSColor? = nil,
        highContrastDark: NSColor? = nil
    ) -> Color {
        let color = NSColor(name: NSColor.Name("Lidless." + name)) { appearance in
            let match = appearance.bestMatch(from: appearanceNames)
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            // The Settings and onboarding windows force plain `.aqua`, so the
            // system setting is checked as well as the appearance.
            let isHighContrast = match == .accessibilityHighContrastAqua
                || match == .accessibilityHighContrastDarkAqua
                || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            if isHighContrast {
                return isDark ? highContrastDark ?? dark : highContrastLight ?? light
            }
            return isDark ? dark : light
        }
        return Color(nsColor: color)
    }

    /// A token that looks the same in light and dark but gets stronger with
    /// Increase Contrast (for colours on the dark heroes or on the white thumb).
    private static func contrastAware(_ name: String, _ normal: NSColor, increased: NSColor) -> Color {
        adaptive(name, light: normal, dark: normal, highContrastLight: increased, highContrastDark: increased)
    }
}

/// Corner radii (design-spec §1.3).
nonisolated enum Radius {
    static let popover: CGFloat = 22
    static let hud: CGFloat = 24
    static let heroSettings: CGFloat = 20
    static let heroOnboarding: CGFloat = 18
    static let window: CGFloat = 16
    static let card: CGFloat = 14
    static let note: CGFloat = 12
    static let tile: CGFloat = 10
    static let keyIcon: CGFloat = 9
    static let stateChip: CGFloat = 8
}

/// Spacing in use (design-spec §1.5).
nonisolated enum Spacing {
    static let popoverPadding: CGFloat = 12
    static let sectionGap: CGFloat = 10
    static let settingsPadding: CGFloat = 18
    static let settingsGridGap: CGFloat = 14
    /// CSS borders sit inside the box but outside the padding; SwiftUI strokes
    /// don't take space, so bordered surfaces add this to their padding.
    static let hairline: CGFloat = 1
}
