#if DEBUG
import LidlessCore
import SwiftUI

/// Every design-system piece on one sheet, for previews.
struct DesignSystemGallery: View {
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var position = 70.0
    @State private var boosted = 130.0
    @State private var level = 0.8
    @State private var fullLevel = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GallerySection(title: "Type") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Desk Mode is on").lidlessStyle(.heroTitleLarge)
                    Text(verbatim: "Lidless").lidlessStyle(.appTitle)
                    Text(verbatim: "160%").lidlessStyle(.readout).monospacedDigit()
                    Text(verbatim: "Built-in Display").lidlessStyle(.bodyStrong)
                    Text(verbatim: "≈ 350 nits · Drag past the line to boost").lidlessStyle(.small)
                    Text(verbatim: "EXTERNAL DISPLAYS").lidlessStyle(.overlineSection)
                }
                .foregroundStyle(Palette.textPrimary)
            }

            GallerySection(title: "Toggles") {
                HStack(spacing: 14) {
                    Toggle(isOn: $toggleOn) { Text(verbatim: "S") }.toggleStyle(PillToggleStyle(size: .small))
                    Toggle(isOn: $toggleOff) { Text(verbatim: "S") }.toggleStyle(PillToggleStyle(size: .small))
                    Toggle(isOn: $toggleOn) { Text(verbatim: "M") }.toggleStyle(PillToggleStyle(size: .medium))
                    Toggle(isOn: $toggleOn) { Text(verbatim: "L") }.toggleStyle(PillToggleStyle(size: .large))
                    Toggle(isOn: $toggleOn) { Text(verbatim: "XL") }.toggleStyle(PillToggleStyle(size: .extraLarge))
                }
                HStack(spacing: 14) {
                    Toggle(isOn: $toggleOn) { Text(verbatim: "On") }.toggleStyle(PillToggleStyle(surface: .onDark))
                    Toggle(isOn: $toggleOff) { Text(verbatim: "Off") }.toggleStyle(PillToggleStyle(surface: .onDark))
                    Toggle(isOn: .constant(false)) { Text(verbatim: "Disabled") }
                        .toggleStyle(PillToggleStyle(surface: .onDark))
                        .disabled(true)
                    Toggle(isOn: $toggleOff) { Text(verbatim: "XL off") }.toggleStyle(PillToggleStyle(size: .extraLarge, surface: .onDark))
                }
                .padding(12)
                .background { HeroCardSurface(elevation: .flat) }
            }

            GallerySection(title: "Keys") {
                HStack(alignment: .top, spacing: 16) {
                    KeyCombo(shortcut: .defaultPanic, size: .small)
                    KeyCombo(shortcut: .defaultDeskMode, size: .medium)
                    KeyCombo(shortcut: .defaultPanic, size: .small)
                        .environment(\.colorScheme, .dark)
                        .padding(6)
                        .background { HeroCardSurface(elevation: .flat) }
                }
                KeyCombo(shortcut: .defaultPanic, size: .large)
                    .padding(14)
                    .background { HeroCardSurface(elevation: .flat) }
            }

            GallerySection(title: "Sliders") {
                BoostSlider(position: $position, scale: .init(normalMaxNits: 500, ceilingNits: 1000), label: Text(verbatim: "Normal"))
                BoostSlider(position: $boosted, scale: .init(normalMaxNits: 500, ceilingNits: 1000), label: Text(verbatim: "Boosted"))
                BoostSlider(position: $position, scale: .init(normalMaxNits: 600, ceilingNits: 600), label: Text(verbatim: "No Boost"))
                DisplayRow(name: "LG UltraFine 27", subtitle: Text(verbatim: "5K · Main display"), level: $level)
                    .glassCard(padding: EdgeInsets())
                DisplayRow(name: "Dell U2723QE", subtitle: Text(verbatim: "4K · Extended"), level: $fullLevel)
                    .glassCard(padding: EdgeInsets())
            }

            GallerySection(title: "Buttons and chips") {
                HStack(spacing: 10) {
                    Button {} label: { Text(verbatim: "Continue") }.buttonStyle(PrimaryButtonStyle())
                    Button {} label: { Text(verbatim: "Try It") }.buttonStyle(PrimaryButtonStyle(size: .small))
                    Button {} label: { Text(verbatim: "Check Now") }.buttonStyle(SecondaryButtonStyle(size: .medium))
                    Button {} label: { Text(verbatim: "Back to 100%") }.buttonStyle(SecondaryButtonStyle(size: .small))
                }
                HStack(spacing: 10) {
                    Button {} label: { GlyphView(glyph: .sliders, size: 16, lineWidth: 1.9) }
                        .buttonStyle(CircleIconButtonStyle())
                    StatusChip(label: Text(verbatim: "Thermals: Normal"), dotColor: Palette.thermalNominal)
                    StatusChip(label: Text(verbatim: "Serious"), dotColor: Palette.thermalSerious)
                    SplitCapsule(leadingTitle: Text(verbatim: "Settings…"), leadingAction: {}, trailingTitle: Text(verbatim: "Quit"), trailingAction: {})
                }
                HStack(spacing: 10) {
                    Button {} label: { Text(verbatim: "Change Keys") }.buttonStyle(GhostOnDarkButtonStyle())
                    Button {} label: {
                        HStack(spacing: 8) {
                            GlyphView(glyph: .play, size: 14).foregroundStyle(Palette.gold)
                            Text(verbatim: "Test the safety net")
                        }
                    }
                    .buttonStyle(DarkButtonStyle())
                    .frame(width: 220)
                }
                .padding(12)
                .background { HeroCardSurface(elevation: .flat) }
            }

            GallerySection(title: "Notes") {
                Callout(glyph: .flame, message: Text(verbatim: "Boost on · ≈ 800 nits. Uses more battery and heat."))
                EmptyDisplaysCard()
                SectionLabel(title: Text(verbatim: "EXTERNAL DISPLAYS"))
            }
        }
        .padding(20)
        .frame(width: 560)
        .background { Color(nsColor: .windowBackgroundColor) }
    }
}

private struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(.secondary)
            content
        }
    }
}

#Preview("Design system") {
    DesignSystemGallery()
}

#Preview("Design system, dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}
#endif
