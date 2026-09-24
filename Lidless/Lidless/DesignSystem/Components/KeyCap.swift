import LidlessCore
import SwiftUI

/// A keyboard key (design-spec §4 `KeyCap`).
///
/// The small sizes follow the appearance (white in light, #222C38 in dark).
/// The large sizes sit on dark heroes, so they are always dark.
struct KeyCap: View {
    enum Size {
        /// 22 pt, popover and HUD.
        case small
        /// 26 pt, settings shortcut rows.
        case medium
        /// 68 pt, onboarding.
        case large
        /// 76 pt, settings panic-key hero.
        case extraLarge
    }

    let label: String
    var size: Size = .small
    var isAccent = false

    var body: some View {
        let metrics = Metrics(size)
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .circular)
        Text(verbatim: label)
            .font(.system(size: metrics.fontSize, weight: isAccent ? .bold : .regular, design: .monospaced))
            .foregroundStyle(textColor)
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(minWidth: metrics.side, minHeight: metrics.side, maxHeight: metrics.side)
            .frame(width: metrics.isFixedSquare ? metrics.side : nil)
            .background {
                shape.fill(faceColor)
                    .overlay {
                        InsetHighlight(cornerRadius: metrics.cornerRadius - 1, color: highlightColor, dy: 1)
                            .padding(Spacing.hairline)
                    }
                    .overlay { shape.strokeBorder(borderColor, lineWidth: 1) }
                    .background { shape.fill(edgeColor).offset(y: metrics.edge) }
                    .lidlessShadow(glow(metrics))
            }
    }

    private var isLarge: Bool { size == .large || size == .extraLarge }

    private var faceColor: Color {
        isAccent ? Palette.gold : (isLarge ? Palette.keyDark : Palette.keyFace)
    }

    private var borderColor: Color {
        if isAccent { return isLarge ? Palette.white.opacity(0.3) : Palette.keyAccentBorder }
        return isLarge ? Palette.keyLargeBorder : Palette.keyBorder
    }

    private var edgeColor: Color {
        if isAccent { return isLarge ? Palette.goldDeepFixed : Palette.keyAccentEdge }
        return isLarge ? Palette.keyDarkEdge : Palette.keyEdge
    }

    private var textColor: Color {
        if isAccent { return Palette.ink }
        return isLarge ? Palette.white : Palette.keyText
    }

    private var highlightColor: Color {
        guard isLarge else { return .clear }
        return Palette.white.opacity(isAccent ? 0.5 : 0.12)
    }

    private func glow(_ metrics: Metrics) -> ShadowLayer {
        .css(y: 0, blur: metrics.glowBlur, color: isAccent && isLarge ? Palette.goldGlow : .clear)
    }

    private struct Metrics {
        let side: CGFloat
        let horizontalPadding: CGFloat
        let cornerRadius: CGFloat
        let fontSize: CGFloat
        let edge: CGFloat
        let glowBlur: CGFloat
        let isFixedSquare: Bool

        init(_ size: Size) {
            switch size {
            case .small:
                side = 22; horizontalPadding = 5 + 1; cornerRadius = 6; fontSize = 11; edge = 2; glowBlur = 0; isFixedSquare = false
            case .medium:
                side = 26; horizontalPadding = 6 + 1; cornerRadius = 7; fontSize = 12; edge = 2; glowBlur = 0; isFixedSquare = false
            case .large:
                side = 68; horizontalPadding = 0; cornerRadius = 15; fontSize = 26; edge = 5; glowBlur = 26; isFixedSquare = true
            case .extraLarge:
                side = 76; horizontalPadding = 0; cornerRadius = 16; fontSize = 30; edge = 5; glowBlur = 28; isFixedSquare = true
            }
        }
    }
}

/// A shortcut as a row of keycaps; the last key (the letter) is gold.
///
/// Takes finished labels rather than a `KeyShortcut`: naming the key needs the
/// keyboard layout, which a store tracks so layout switches reach the view.
struct KeyCombo: View {
    let keys: ShortcutLabels
    var size: KeyCap.Size = .small

    var body: some View {
        let caps = keys.keycaps
        HStack(spacing: spacing) {
            ForEach(Array(caps.enumerated()), id: \.element) { item in
                KeyCap(label: item.element, size: size, isAccent: item.offset == caps.count - 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: keys.spokenName))
    }

    private var spacing: CGFloat {
        switch size {
        case .small: 3
        case .medium: 4
        case .large, .extraLarge: 12
        }
    }
}

#if DEBUG
extension KeyCombo {
    /// The recorded labels, for the gallery and previews.
    init(shortcut: KeyShortcut, size: KeyCap.Size = .small) {
        self.init(keys: ShortcutLabels(shortcut, keyLabel: shortcut.keyLabel), size: size)
    }
}
#endif

/// A shortcut's keycaps and VoiceOver name, with the key named as `keyLabel`.
nonisolated struct ShortcutLabels: Equatable, Sendable {
    /// Keycap labels in macOS order: ⌃ ⌥ ⇧ ⌘, then the key.
    let keycaps: [String]
    /// "Control Option Command B".
    let spokenName: String

    init(_ shortcut: KeyShortcut, keyLabel: String) {
        keycaps = shortcut.keycaps(keyLabel: keyLabel)
        var words: [String] = []
        if shortcut.modifiers.contains(.control) { words.append(String(localized: "Control", comment: "Spoken name of the Control key")) }
        if shortcut.modifiers.contains(.option) { words.append(String(localized: "Option", comment: "Spoken name of the Option key")) }
        if shortcut.modifiers.contains(.shift) { words.append(String(localized: "Shift", comment: "Spoken name of the Shift key")) }
        if shortcut.modifiers.contains(.command) { words.append(String(localized: "Command", comment: "Spoken name of the Command key")) }
        words.append(keyLabel)
        spokenName = words.joined(separator: " ")
    }
}
