import SwiftUI

/// The design's type scale (design-spec §1.4).
///
/// Fonts come from `Font.system(size:weight:design:)` with explicit values,
/// which binds to an overload that exists on macOS 12. Letter-spacing is Text
/// tracking, so apply a style with `Text.lidlessStyle(_:)` before any View
/// modifier (View-level tracking is macOS 13+).
nonisolated struct TypeStyle: Sendable {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    /// Letter-spacing in points (CSS em × size).
    var tracking: CGFloat = 0
    /// CSS `line-height: normal` as the canvas was laid out: WebKit/Chrome on
    /// macOS round SF's ascent and descent separately (`NSLayoutManager.defaultLineHeight`).
    let cssLineHeight: CGFloat
    /// SwiftUI's own line height for this font. SwiftUI rounds line boxes to
    /// whole points, one point taller than CSS at 10, 11, 11.5, 15, 16 and 19 pt
    /// (measured on macOS 27).
    let nativeLineHeight: CGFloat

    var font: Font { .system(size: size, weight: weight, design: design) }

    static let heroNumber = TypeStyle(size: 46, weight: .heavy, design: .rounded, cssLineHeight: 54, nativeLineHeight: 54)
    static let heroTitleLarge = TypeStyle(size: 30, weight: .bold, design: .rounded, cssLineHeight: 35, nativeLineHeight: 35)
    static let onboardingTitle = TypeStyle(size: 28, weight: .heavy, design: .rounded, cssLineHeight: 33, nativeLineHeight: 33)
    static let heroTitleMedium = TypeStyle(size: 26, weight: .bold, design: .rounded, cssLineHeight: 30, nativeLineHeight: 30)
    static let onboardingTitle2 = TypeStyle(size: 26, weight: .heavy, design: .rounded, cssLineHeight: 30, nativeLineHeight: 30)
    static let hudTitle = TypeStyle(size: 19, weight: .bold, design: .rounded, cssLineHeight: 22, nativeLineHeight: 23)
    static let appTitle = TypeStyle(size: 16, weight: .bold, design: .rounded, cssLineHeight: 18, nativeLineHeight: 19)
    static let unitLabel = TypeStyle(size: 16, weight: .semibold, design: .default, cssLineHeight: 18, nativeLineHeight: 19)
    static let readout = TypeStyle(size: 15, weight: .bold, design: .rounded, cssLineHeight: 18, nativeLineHeight: 19)
    static let cardTitle = TypeStyle(size: 15, weight: .bold, design: .rounded, cssLineHeight: 18, nativeLineHeight: 19)
    static let ruleSentence = TypeStyle(size: 15, weight: .regular, design: .default, cssLineHeight: 18, nativeLineHeight: 19)
    static let heroToggleLabel = TypeStyle(size: 15, weight: .semibold, design: .default, cssLineHeight: 18, nativeLineHeight: 19)
    static let featureTitle = TypeStyle(size: 14, weight: .bold, design: .rounded, cssLineHeight: 17, nativeLineHeight: 17)
    static let token = TypeStyle(size: 14, weight: .semibold, design: .default, cssLineHeight: 17, nativeLineHeight: 17)
    static let heroBody = TypeStyle(size: 14, weight: .regular, design: .default, cssLineHeight: 17, nativeLineHeight: 17)
    static let onboardingBody = TypeStyle(size: 13.5, weight: .regular, design: .default, cssLineHeight: 16, nativeLineHeight: 16)
    static let body = TypeStyle(size: 13, weight: .regular, design: .default, cssLineHeight: 16, nativeLineHeight: 16)
    static let bodyStrong = TypeStyle(size: 13, weight: .semibold, design: .default, cssLineHeight: 16, nativeLineHeight: 16)
    static let bodyMedium = TypeStyle(size: 13, weight: .medium, design: .default, cssLineHeight: 16, nativeLineHeight: 16)
    static let buttonPrimary = TypeStyle(size: 13, weight: .bold, design: .default, cssLineHeight: 16, nativeLineHeight: 16)
    static let description = TypeStyle(size: 12.5, weight: .regular, design: .default, cssLineHeight: 15, nativeLineHeight: 15)
    static let small = TypeStyle(size: 12, weight: .regular, design: .default, cssLineHeight: 15, nativeLineHeight: 15)
    static let smallStrong = TypeStyle(size: 12, weight: .semibold, design: .default, cssLineHeight: 15, nativeLineHeight: 15)
    static let helper = TypeStyle(size: 11.5, weight: .regular, design: .default, cssLineHeight: 13, nativeLineHeight: 14)
    static let caption = TypeStyle(size: 11, weight: .regular, design: .default, cssLineHeight: 13, nativeLineHeight: 14)
    static let captionStrong = TypeStyle(size: 11, weight: .bold, design: .default, cssLineHeight: 13, nativeLineHeight: 14)
    static let overlineSection = TypeStyle(size: 11, weight: .bold, design: .default, tracking: 0.88, cssLineHeight: 13, nativeLineHeight: 14)
    static let overlineHero = TypeStyle(size: 11, weight: .bold, design: .default, tracking: 1.32, cssLineHeight: 13, nativeLineHeight: 14)
    static let overlineCard = TypeStyle(size: 10, weight: .bold, design: .default, tracking: 1.2, cssLineHeight: 12, nativeLineHeight: 13)
    static let badge = TypeStyle(size: 11, weight: .bold, design: .default, cssLineHeight: 13, nativeLineHeight: 14)
    static let keyXL = TypeStyle(size: 30, weight: .regular, design: .monospaced, cssLineHeight: 35, nativeLineHeight: 35)
    static let keyL = TypeStyle(size: 26, weight: .regular, design: .monospaced, cssLineHeight: 30, nativeLineHeight: 30)
    static let keyM = TypeStyle(size: 12, weight: .regular, design: .monospaced, cssLineHeight: 15, nativeLineHeight: 15)
    static let keyS = TypeStyle(size: 11, weight: .regular, design: .monospaced, cssLineHeight: 13, nativeLineHeight: 14)
    static let keyIconLabel = TypeStyle(size: 8, weight: .bold, design: .default, cssLineHeight: 10, nativeLineHeight: 10)
}

extension Text {
    /// Font and letter-spacing of a design style. Returns `Text`, so it can be
    /// followed by other Text modifiers such as `monospacedDigit()`.
    func lidlessStyle(_ style: TypeStyle) -> Text {
        style.tracking == 0
            ? font(style.font)
            : font(style.font).tracking(style.tracking)
    }
}

extension View {
    /// Lays text out on the canvas's CSS line boxes, so stacked text lands
    /// where the design has it: `line-height: normal`, or a unitless CSS
    /// `line-height` multiple (e.g. 1.3).
    ///
    /// SwiftUI puts the baseline where WebKit does and adds its extra point
    /// below the descender, so CSS half-leading goes on top and the rest of
    /// the difference is taken from the bottom.
    func lineBox(_ style: TypeStyle, lineHeight multiple: CGFloat? = nil) -> some View {
        let pitch = multiple.map { $0 * style.size } ?? style.cssLineHeight
        let halfLeading = (pitch - style.cssLineHeight) / 2
        let extra = pitch - style.nativeLineHeight
        return lineSpacing(max(0, extra))
            .padding(.top, halfLeading)
            .padding(.bottom, extra - halfLeading)
    }
}
