import SwiftUI

/// Footer status pill with a coloured dot (design-spec §4 `StatusChip`).
struct StatusChip: View {
    let label: Text
    let dotColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            label
                .lidlessStyle(.small)
                .foregroundStyle(Palette.text2)
                .lineLimit(1)
        }
        // CSS content-box: 30 pt tall plus the 1 pt border on each side.
        .padding(.horizontal, 12 + Spacing.hairline)
        .frame(height: 30 + 2 * Spacing.hairline)
        // The canvas's r15 is one point short of a capsule on this 32 pt chip.
        .background {
            RoundedRectangle(cornerRadius: 15, style: .circular)
                .fill(Palette.chipFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .circular)
                        .strokeBorder(Palette.chipBorder, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Two plain buttons sharing one glass capsule, split by a hairline
/// ("Settings…" | "Quit").
struct SplitCapsule: View {
    let leadingTitle: Text
    let leadingAction: () -> Void
    let trailingTitle: Text
    let trailingAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: leadingAction) { leadingTitle.lidlessStyle(.small) }
                .buttonStyle(CapsuleSegmentButtonStyle())
            Rectangle()
                .fill(Palette.splitDivider)
                .frame(width: 1)
                .padding(.vertical, 7)
                .accessibilityHidden(true)
            Button(action: trailingAction) { trailingTitle.lidlessStyle(.small) }
                .buttonStyle(CapsuleSegmentButtonStyle())
        }
        .padding(Spacing.hairline)
        .frame(height: 30)
        .background { GlassCapsuleSurface(fill: Palette.splitFill, border: Palette.splitBorder, highlight: Palette.splitInset, height: 30) }
    }
}

private struct CapsuleSegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// White glass capsule with a border, a top highlight and a soft drop
/// (`inset 0 1px 0 #FFF, 0 1px 3px rgba(0,0,0,.08)`).
struct GlassCapsuleSurface: View {
    let fill: Color
    let border: Color
    let highlight: Color
    let height: CGFloat

    var body: some View {
        let radius = height / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        shape.fill(fill)
            .overlay {
                InsetHighlight(cornerRadius: radius - 1, color: highlight, dy: 1)
                    .padding(Spacing.hairline)
            }
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
            .background {
                OuterShadow(cornerRadius: radius, far: .css(y: 1, blur: 3, color: Palette.buttonShadow))
            }
            .accessibilityHidden(true)
    }
}

/// 32 pt round glass button holding a 16 pt glyph (the popover's settings button).
struct CircleIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.textPrimary)
            .frame(width: 32, height: 32)
            .background {
                GlassCapsuleSurface(
                    fill: Palette.circleButtonFill,
                    border: Palette.circleButtonBorder,
                    highlight: Palette.circleButtonInset,
                    height: 32
                )
            }
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
