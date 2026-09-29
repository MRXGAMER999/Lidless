import LidlessCore
import SwiftUI

/// Cream note with a leading glyph (the Boost callout), design-spec §4 `Callout`.
struct Callout: View {
    let glyph: LidlessGlyph
    let message: Text
    /// What VoiceOver reads instead of `message`, when the message leans on
    /// symbols such as "≈" or "·". Nil reads the message.
    var accessibilityMessage: Text? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphView(glyph: glyph, size: 14, lineWidth: 2)
                .padding(.top, 1)
            message
                .lidlessStyle(.small)
                .lineBox(.small, lineHeight: 1.35)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Palette.calloutText)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: Radius.tile, style: .circular)
                .fill(Palette.calloutFill)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityMessage ?? message)
    }
}

/// Dashed placeholder shown when no external display is connected.
struct EmptyDisplaysCard: View {
    var body: some View {
        VStack(spacing: 4) {
            GlyphView(glyph: .monitor, size: 22, lineWidth: 1.6)
                .foregroundStyle(Palette.text4)
            // Line boxes of the 2x render: 15 pt for 13 pt text, 14 pt for 12 pt.
            Text("No external displays", comment: "Empty state title in the popover's external displays section")
                .lidlessStyle(.bodyStrong)
                .foregroundStyle(Palette.textPrimary)
                .lineBox(.bodyStrong, lineHeight: 15.0 / 13)
            Text("They'll show up here when you plug one in.", comment: "Empty state message in the popover's external displays section")
                .lidlessStyle(.small)
                .foregroundStyle(Palette.text3)
                .lineBox(.small, lineHeight: 14.0 / 12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16 + 1.5)
        .padding(.horizontal, 12 + 1.5)
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .circular)
            shape.fill(Palette.emptyCardFill)
                .overlay {
                    // The 2x render draws the 1.5 px CSS dashed border as 3 pt dashes with 1.5 pt gaps.
                    shape.strokeBorder(Palette.dashedBorder, style: StrokeStyle(lineWidth: 1.5, dash: [3, 1.5]))
                }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small caps heading above a group of cards, e.g. "EXTERNAL DISPLAYS".
/// Pass the text already uppercased so translators control the casing.
struct SectionLabel: View {
    let title: Text

    var body: some View {
        title
            .lidlessStyle(.overlineSection)
            .foregroundStyle(Palette.text3)
            .lineBox(.overlineSection)
            // CSS `padding-top: 2px`, less the half point the 2x render sets
            // the 11 pt baseline above SwiftUI's.
            .padding(.top, 1.5)
            .padding(.bottom, 0.5)
            .padding(.horizontal, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One external display: icon, name and role, a brightness bar and its percentage.
struct DisplayRow: View {
    let name: String
    let subtitle: Text
    @Binding var level: Double
    var showsDivider = false

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Rectangle()
                    .fill(Palette.divider)
                    .frame(height: 1)
                    .padding(.leading, 42)
                    .padding(.trailing, 14)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 10) {
                GlyphView(glyph: .monitor, size: 18, lineWidth: 1.8)
                    .foregroundStyle(Palette.rowIcon)
                // The 2x renders set 13 pt text on a 15 pt line and put 11–13 pt
                // baselines half a point above SwiftUI's, which gives 49 pt rows.
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name)
                        .lidlessStyle(.bodyMedium)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .lineBox(.bodyMedium, lineHeight: 15.0 / 13)
                    subtitle
                        .lidlessStyle(.caption)
                        .foregroundStyle(Palette.text4)
                        .lineLimit(1)
                        .lineBox(.caption)
                        .padding(.top, -0.5)
                        .padding(.bottom, 0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // One VoiceOver stop for name and role; the slider carries the name itself.
                .accessibilityElement(children: .combine)
                MiniSlider(level: $level, label: Text("\(name) brightness", comment: "VoiceOver label of an external display's brightness slider; the variable is the display name"))
                Text(SliderMath.percent(level: level), format: .percent)
                    .lidlessStyle(.smallStrong)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    // "100%" is a little wider than the column; let it grow
                    // into the gap instead of wrapping the sign.
                    .lineLimit(1)
                    .fixedSize()
                    // The renders centre these digits on the bar a little lower
                    // than SwiftUI does. Half a point snaps the same way at 1x
                    // and 2x wherever the row sits; smaller offsets don't.
                    .offset(y: 0.5)
                    .frame(width: 34, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        }
    }
}
