import AppKit
import SwiftUI

// Settings and onboarding components (design-spec §4). Frozen signatures for
// Phase 5; the components agent implements the bodies, tab agents use them.
// Settings and onboarding are designed in light only; dark values come from
// the derived tokens in `Palette` ("Settings and onboarding").

/// `SettingsCard`: r16, padding 16×18, `settingsCard` surface, optional `cardTitle`.
///
/// Fills the width it is offered; content is top-leading. Body text defaults
/// to the primary ink.
struct SettingsCard<Content: View>: View {
    var title: Text?
    var spacing: CGFloat = 12
    /// CSS padding inside the 1 pt border: 16×18, or 14×18 for "Your screens" and About.
    var padding = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    /// Takes all the height offered, like the design's `flex-grow` cards
    /// ("How it switches off", "Your screens", About).
    var fillsHeight = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                title
                    .lidlessStyle(.cardTitle)
                    .lineBox(.cardTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .foregroundStyle(Palette.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .padding(padding)
        .padding(Spacing.hairline)
        .background { SettingsCardSurface() }
    }
}

/// The `settingsCard` surface on its own: 0.84 white, 1 pt white border, a
/// 1 pt ring outside it and a soft drop. Onboarding's feature and list cards
/// use it at r14.
struct SettingsCardSurface: View {
    var cornerRadius: CGFloat = Radius.window

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        shape.fill(Palette.settingsCardFill)
            .overlay { shape.strokeBorder(Palette.settingsCardBorder, lineWidth: 1) }
            // `0 0 0 1px`: a ring just outside the border box, taking no layout space.
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius + 1, style: .circular)
                    .strokeBorder(Palette.settingsCardRing, lineWidth: 1)
                    .padding(-1)
            }
            .background {
                OuterShadow(cornerRadius: cornerRadius, far: .css(y: 2, blur: 8, color: Palette.settingsCardShadow))
            }
            .accessibilityHidden(true)
    }
}

/// `TokenMenu`: the inline dropdown pill used in the rule sentence and guard rails.
///
/// A drawn pill that opens a real `NSMenu` below itself, with a check mark on
/// the current value. SwiftUI's `Menu` can't be used: on macOS it wraps its
/// label in a system pop-up button that keeps only the text and image, and
/// ignores the font, colour and background (the capsule, the 600 weight, the
/// brown text and the drawn chevron). VoiceOver gets a real menu `Picker`
/// through `accessibilityRepresentation`, so it reads "Serious, Heat level,
/// pop-up button" and can change the value itself.
struct TokenMenu<Value: Hashable>: View {
    enum Size { case regular, compact }  // 14/600 vs 13/600
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> Text
    var size: Size = .regular
    /// VoiceOver label, e.g. "Heat level".
    var accessibilityLabel: Text
    /// Menu item titles. `NSMenu` needs strings and a SwiftUI `Text` can't be
    /// read back, so pass the same localized string `label` shows. The
    /// default only suits values that describe themselves (`String`).
    var menuTitle: (Value) -> String = { String(describing: $0) }

    @State private var anchor = MenuAnchor()
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 4) {
                label(selection)
                    .lidlessStyle(size == .regular ? .token : .bodyStrong)
                GlyphView(glyph: .chevronDown, size: 11, lineWidth: 2.6)
            }
        }
        .buttonStyle(TokenPillStyle())
        .background { MenuAnchorView(anchor: anchor) }
        .fixedSize()
        // Not designed: a faded pill, as the popover's disabled controls.
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityRepresentation {
            Picker(selection: $selection) {
                ForEach(options, id: \.self) { option in
                    label(option).tag(option)
                }
            } label: {
                accessibilityLabel
            }
            .pickerStyle(.menu)
        }
    }

    private func showMenu() {
        guard let view = anchor.view, !options.isEmpty else { return }
        let binding = $selection
        let options = options
        let target = MenuTarget { index in
            guard options.indices.contains(index) else { return }
            binding.wrappedValue = options[index]
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, option) in options.enumerated() {
            let item = NSMenuItem(title: menuTitle(option), action: #selector(MenuTarget.choose(_:)), keyEquivalent: "")
            item.target = target
            item.tag = index
            item.state = option == selection ? .on : .off
            menu.addItem(item)
        }
        menu.minimumWidth = view.bounds.width
        // A pull-down, like the chevron says: the menu's top-left corner 4 pt under the pill.
        let y = view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4
        // `popUp` tracks the menu before it returns; the item targets are weak.
        withExtendedLifetime(target) {
            _ = menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: y), in: view)
        }
    }
}

/// The token's capsule: h28, padding 12 / 8 inside a 1 pt #F2C94C border, cream fill.
private struct TokenPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.calloutText)
            .lineLimit(1)
            .padding(.leading, 12 + Spacing.hairline)
            .padding(.trailing, 8 + Spacing.hairline)
            .frame(height: 28)
            .background {
                Capsule()
                    .fill(Palette.calloutFill)
                    .overlay { Capsule().strokeBorder(Palette.tokenBorder, lineWidth: 1) }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The AppKit view a `TokenMenu` pops its menu up from.
private final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }

    /// Never takes clicks from the SwiftUI button above it.
    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private final class MenuTarget: NSObject {
    private let select: (Int) -> Void

    init(select: @escaping (Int) -> Void) {
        self.select = select
    }

    @objc func choose(_ sender: NSMenuItem) {
        select(sender.tag)
    }
}

/// `SegmentedNav`: the Settings tab switcher (gold selected capsule).
///
/// One keyboard stop (with keyboard navigation on) whose arrow keys switch
/// tabs, as `NSSegmentedControl` does. VoiceOver gets a segmented `Picker`
/// labelled "Settings sections", so it reads each tab with its position and
/// selected state.
struct SegmentedNav<Tab: Hashable & Identifiable>: View {
    @Binding var selection: Tab
    let tabs: [Tab]
    let title: (Tab) -> Text
    let glyph: (Tab) -> LidlessGlyph

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                segment(tab)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Palette.neutralFill)
                .overlay { CapsuleInsetBlur(color: Palette.segmentedTrackInset) }
        }
        .modifier(KeyboardOnlyFocusable())
        .onMoveCommand(perform: move)
        .accessibilityRepresentation {
            Picker(selection: $selection) {
                ForEach(tabs) { tab in
                    title(tab).tag(tab)
                }
            } label: {
                Text("Settings sections", comment: "VoiceOver label of the tab switcher at the top of the Settings window")
            }
            .pickerStyle(.segmented)
        }
    }

    private func segment(_ tab: Tab) -> some View {
        let isSelected = tab == selection
        return HStack(spacing: 6) {
            GlyphView(glyph: glyph(tab), size: 15, lineWidth: 2)
            title(tab)
                .lidlessStyle(isSelected ? .bodyStrong : .bodyMedium)
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Palette.ink : Palette.text3)
        .fixedSize()
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background {
            if isSelected {
                Capsule()
                    .fill(Palette.gold)
                    .overlay { CapsuleInsetHighlight(color: Palette.white.opacity(0.5), dy: 1) }
                    .lidlessShadow(.css(y: 1, blur: 3, color: Palette.segmentedSelectedShadow))
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
        .contentShape(Capsule())
        .onTapGesture { select(tab) }
    }

    private func select(_ tab: Tab) {
        guard tab != selection else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
            selection = tab
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        let leftToRight = layoutDirection == .leftToRight
        let step: Int
        switch direction {
        case .left: step = leftToRight ? -1 : 1
        case .right: step = leftToRight ? 1 : -1
        default: return
        }
        guard let index = tabs.firstIndex(of: selection), tabs.indices.contains(index + step) else { return }
        select(tabs[index + step])
    }
}

/// CSS `inset 0 1px 2px`: a soft shade along a capsule's top inside edge.
private struct CapsuleInsetBlur: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            InsetHighlight(cornerRadius: min(proxy.size.width, proxy.size.height) / 2, color: color, dy: 1, blur: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// `InfoChip`: hero chips ("Lid open", "On power", "Built-in screen off").
struct InfoChip: View {
    let text: Text
    var isActive = false
    /// Semibold without the gold: the Desk Mode hero's state chip is 600 in
    /// both states, only its colours change (design-spec V6).
    var isEmphasized = false

    var body: some View {
        text
            .lidlessStyle(isActive || isEmphasized ? .smallStrong : .small)
            .foregroundStyle(isActive ? Palette.goldOnDark : Palette.textOnDark2)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background { Capsule().fill(isActive ? Palette.onDarkChipActive : Palette.onDarkChip) }
    }
}

/// `Badge`: "Always" (lock), "Boost ready" (gold), "Normal only" (neutral).
struct Badge: View {
    enum Style { case locked, gold, neutral }
    let text: Text
    let style: Style

    var body: some View {
        HStack(spacing: 4) {
            if style == .locked {
                GlyphView(glyph: .lock, size: 11, lineWidth: 2.4)
            }
            text.lidlessStyle(textStyle)
        }
        .foregroundStyle(style == .gold ? Palette.ink : Palette.text3)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, style == .locked ? 8 : 10)
        .frame(height: 22)
        .background { Capsule().fill(style == .gold ? Palette.gold : Palette.neutralFill) }
        .accessibilityElement(children: .combine)
    }

    private var textStyle: TypeStyle {
        switch style {
        case .locked: .caption
        case .gold: .badge
        case .neutral: .badgeSemibold
        }
    }
}

private extension TypeStyle {
    /// "Normal only": 11/600.
    static let badgeSemibold = TypeStyle(size: 11, weight: .semibold, design: .default, cssLineHeight: 13, nativeLineHeight: 14)
}

/// `NumberBadge`: 26 pt navy circle with a gold numeral.
struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text(number, format: .number)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Palette.gold)
            .frame(width: 26, height: 26)
            .background { Circle().fill(Palette.numberBadgeFill) }
    }
}

/// `IconTile`: 34×34 r10 tile with a glyph.
struct IconTile: View {
    enum Style { case cream, dark, gold }
    let glyph: LidlessGlyph
    let style: Style

    var body: some View {
        GlyphView(glyph: glyph, size: 18, lineWidth: 2)
            .foregroundStyle(glyphColor)
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: Radius.tile, style: .circular).fill(fillColor)
            }
            .accessibilityHidden(true)
    }

    private var fillColor: Color {
        switch style {
        case .cream: Palette.calloutFill
        case .dark: Palette.heroBackground
        case .gold: Palette.gold
        }
    }

    private var glyphColor: Color {
        switch style {
        case .cream: Palette.goldDeep
        case .dark: Palette.gold
        case .gold: Palette.ink
        }
    }
}

/// `PageDots` for onboarding: `count` dots, `current` 0-based.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(count, 0), id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.textPrimary : Palette.dashedBorder)
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current + 1) of \(count)", comment: "VoiceOver label of the onboarding page dots, e.g. \"Step 1 of 2\""))
    }
}

/// `NoteCallout`: Settings' cream note with an info glyph; `content` may hold a link.
///
/// Content gets 12 pt brown text on 1.4 lines; links inside take the tint
/// (#8A5A00, derived #FFD466 in dark).
struct NoteCallout<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphView(glyph: .info, size: 15, lineWidth: 2.2)
                .padding(.top, 1)
            content()
                .font(TypeStyle.small.font)
                .lineBox(.small, lineHeight: 1.4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Palette.calloutText)
        .tint(Palette.goldDeep)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: Radius.note, style: .circular).fill(Palette.calloutFill)
        }
        // `.contain`, not `.combine`: a link inside must stay its own button.
        .accessibilityElement(children: .contain)
    }
}

/// `IconStateChips`: the three menu bar glyph states (normal, Desk Mode, Boost).
struct IconStateChips: View {
    private static let glyphs: [LidlessGlyph] = [.laptop, .laptopScreenFilled, .laptopBoost]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.glyphs, id: \.self) { glyph in
                GlyphView(glyph: glyph, size: 16, lineWidth: 1.9)
                    .frame(width: 34, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.stateChip, style: .circular).fill(Palette.neutralFill)
                    }
            }
        }
        .foregroundStyle(Palette.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Icon states: normal, Desk Mode, Boost", comment: "VoiceOver label of the three menu bar icon previews in Settings"))
    }
}

/// `F2KeyIcon`: the brightness key illustration.
struct F2KeyIcon: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.keyIcon, style: .circular)
        VStack(spacing: 1) {
            GlyphView(glyph: .sun, size: 16, lineWidth: 2)
            Text(verbatim: "F2")
                .lidlessStyle(.keyIconLabel)
                .lineBox(.keyIconLabel)
        }
        .foregroundStyle(Palette.keyText)
        .frame(width: 40, height: 40)
        .background {
            shape.fill(Palette.keyFace)
                .overlay { shape.strokeBorder(Palette.keyBorder, lineWidth: 1) }
                // `0 3px 0`: the key's hard bottom edge.
                .background { shape.fill(Palette.keyEdge).offset(y: 3) }
        }
        .accessibilityHidden(true)
    }
}

/// `MethodCard`: a selectable card with art, title and description (radio semantics).
///
/// Fills the width and height it is offered, content top-leading: put two in
/// an `HStack` with `.fixedSize(horizontal: false, vertical: true)` to give
/// them the same height, as the design's grid row does.
struct MethodCard<Art: View>: View {
    let title: Text
    let detail: Text
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var art: () -> Art

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                art()
                    .accessibilityHidden(true)
                title
                    .lidlessStyle(.bodyStrong)
                    .foregroundStyle(Palette.textPrimary)
                    .lineBox(.bodyStrong)
                detail
                    .lidlessStyle(.helper)
                    .foregroundStyle(Palette.text4)
                    .lineBox(.helper, lineHeight: 1.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // CSS border-box: 12 pt padding inside the 2 pt border.
            .padding(12 + 2)
        }
        .buttonStyle(MethodCardStyle(isSelected: isSelected))
        // Not designed: faded like the other disabled controls.
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MethodCardStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .circular)
        configuration.label
            .background {
                shape.fill(isSelected ? Palette.methodCardSelectedFill : Palette.methodCardFill)
                    .overlay {
                        shape.strokeBorder(isSelected ? Palette.goldBorderSelected : Palette.methodCardBorder, lineWidth: 2)
                    }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// The Settings/onboarding window background (`settingsWindowBg`): a
/// behind-window blur under a 0.9 warm paper wash. Fills the whole window,
/// title bar included.
struct SettingsWindowBackground: View {
    var body: some View {
        ZStack {
            BehindWindowBlur()
            Palette.settingsWindowBg
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Takes keyboard focus only when the user navigates by keyboard (System
/// Settings › Keyboard › Keyboard navigation), so a click never leaves a
/// focus ring on a custom control. Same rule as the popover's sliders.
struct KeyboardOnlyFocusable: ViewModifier {
    @ObservedObject private var keyboardNavigation = KeyboardNavigation.shared

    func body(content: Content) -> some View {
        content.focusable(keyboardNavigation.isEnabled)
    }
}

#if DEBUG
private enum PreviewTab: String, CaseIterable, Identifiable {
    case desk, brightness, keys
    var id: Self { self }
}

private struct SettingsPartsPreview: View {
    @State private var tab = PreviewTab.desk
    @State private var heat = "Serious"
    @State private var disconnect = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SegmentedNav(
                selection: $tab,
                tabs: PreviewTab.allCases,
                title: { Text(verbatim: $0.rawValue.capitalized) },
                glyph: { tab in
                    switch tab {
                    case .desk: .laptopSlash
                    case .brightness: .sun
                    case .keys: .keyboard
                    }
                }
            )
            SettingsCard(title: Text(verbatim: "Guard rails")) {
                HStack(spacing: 12) {
                    IconTile(glyph: .thermometer, style: .cream)
                    Text(verbatim: "Mac gets hot").lidlessStyle(.bodyStrong)
                    Spacer()
                    TokenMenu(
                        selection: $heat,
                        options: ["Fair", "Serious", "Critical"],
                        label: { Text(verbatim: $0) },
                        size: .compact,
                        accessibilityLabel: Text(verbatim: "Heat level")
                    )
                }
                NoteCallout { Text(verbatim: "Auto-brightness can block Boost on some Macs.") }
                HStack(spacing: 10) {
                    Badge(text: Text(verbatim: "Always"), style: .locked)
                    Badge(text: Text(verbatim: "Boost ready"), style: .gold)
                    Badge(text: Text(verbatim: "Normal only"), style: .neutral)
                    NumberBadge(number: 1)
                    F2KeyIcon()
                    IconStateChips()
                    PageDots(count: 2, current: 0)
                }
            }
            HStack(spacing: 10) {
                MethodCard(title: Text(verbatim: "Disconnect"), detail: Text(verbatim: "Windows move to your other screen."), isSelected: disconnect, action: { disconnect = true }) {
                    MethodDisconnectArt()
                }
                MethodCard(title: Text(verbatim: "Black out"), detail: Text(verbatim: "Screen goes dark, windows stay put."), isSelected: !disconnect, action: { disconnect = false }) {
                    MethodBlackOutArt()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                InfoChip(text: Text(verbatim: "Lid open"))
                InfoChip(text: Text(verbatim: "Built-in screen on"), isEmphasized: true)
                InfoChip(text: Text(verbatim: "Built-in screen off"), isActive: true)
            }
            .padding(12)
            .background { HeroCardSurface(cornerRadius: Radius.heroSettings, elevation: .flat) }
        }
        .padding(18)
        .frame(width: 520)
        .background { SettingsWindowBackground() }
    }
}

#Preview("Settings parts") {
    SettingsPartsPreview()
}

#Preview("Settings parts, dark") {
    SettingsPartsPreview()
        .preferredColorScheme(.dark)
}
#endif
