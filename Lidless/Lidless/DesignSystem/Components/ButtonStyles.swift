import SwiftUI

/// Gold capsule button (design-spec §4 `PrimaryButton`).
struct PrimaryButtonStyle: ButtonStyle {
    enum Size {
        /// 38 pt, bold, with the gold drop ("Continue", "Keep Off").
        case large
        /// 32 pt, semibold, flat ("Try It").
        case small
    }

    var size: Size = .large
    var horizontalPadding: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        let isLarge = size == .large
        configuration.label
            .font(isLarge ? TypeStyle.buttonPrimary.font : TypeStyle.bodyStrong.font)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, isLarge ? horizontalPadding : 16)
            .frame(height: isLarge ? 38 : 32)
            .background {
                Capsule()
                    .fill(Palette.gold)
                    .overlay { CapsuleInsetHighlight(color: Palette.white.opacity(isLarge ? 0.5 : 0), dy: 1) }
                    .lidlessShadow(.css(y: 4, blur: 12, color: isLarge ? Palette.primaryButtonShadow : .clear))
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// White capsule with a hairline border (design-spec §4 `SecondaryButton`).
struct SecondaryButtonStyle: ButtonStyle {
    enum Size {
        /// 38 pt, 13/600 ("Back", "Turn Back On").
        case large
        /// 32 pt, 13/500 ("Check Now").
        case medium
        /// 30 pt, 12/600 ("Back to 100%").
        case small
    }

    var size: Size = .medium

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding + Spacing.hairline)
            .frame(height: height)
            .background {
                Capsule()
                    .fill(Palette.secondaryButtonFill)
                    .overlay { Capsule().strokeBorder(Palette.secondaryButtonBorder, lineWidth: 1) }
                    .lidlessShadow(.css(y: 1, blur: 3, color: Palette.secondaryButtonShadow))
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var font: Font {
        switch size {
        case .large: TypeStyle.bodyStrong.font
        case .medium: TypeStyle.bodyMedium.font
        case .small: TypeStyle.smallStrong.font
        }
    }

    private var height: CGFloat {
        switch size {
        case .large: 38
        case .medium: 32
        case .small: 30
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .large: 20
        case .medium: 16
        case .small: 14
        }
    }
}

/// Full-width ink capsule ("Test the safety net"), design-spec §4 `DarkButton`.
struct DarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeStyle.bodyStrong.font)
            .foregroundStyle(Palette.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
                Capsule()
                    .fill(Palette.ink)
                    .overlay { CapsuleInsetHighlight(color: Palette.white.opacity(0.15), dy: 1) }
                    .lidlessShadow(.css(y: 4, blur: 12, color: Palette.ink.opacity(0.25)))
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Translucent capsule on a dark hero ("Change Keys"), design-spec §4 `GhostOnDarkButton`.
struct GhostOnDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeStyle.bodyMedium.font)
            .foregroundStyle(Palette.white)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background {
                Capsule()
                    .fill(Palette.onDarkGhostFill)
                    .overlay { Capsule().strokeBorder(Palette.onDarkGhostBorder, lineWidth: 1) }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
