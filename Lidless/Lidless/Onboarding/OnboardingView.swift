import LidlessCore
import SwiftUI

nonisolated enum OnboardingMetrics {
    /// design-spec §8: 640×560, title bar included.
    static let windowSize = CGSize(width: 640, height: 560)
    static let stepCount = 2
}

/// Undesigned copy that the flow also needs outside a view.
enum OnboardingCopy {
    /// Not designed (design-spec §11.3 Q9): the status pill once the panic key works.
    static var panicKeyWorked: String {
        String(localized: "It works. Press it any time you can't see a screen.", comment: "Onboarding status after the user pressed the panic key while trying it; replaces “Try it now. We'll show a check mark when it works.”")
    }
}

/// The onboarding window's content: one page per step, over the Settings
/// window background. The pages slide sideways (crossfade with Reduce Motion).
struct OnboardingView: View {
    @ObservedObject var flow: OnboardingFlow
    let deskMode: DeskModeStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch flow.step {
            case .welcome:
                WelcomePage(onContinue: { navigate(flow.goToSetup) })
                    .transition(pageTransition(from: .leading))
            case .setup:
                SetupPage(
                    flow: flow,
                    deskMode: deskMode,
                    onBack: { navigate(flow.goToWelcome) },
                    onStart: flow.finish
                )
                .transition(pageTransition(from: .trailing))
            }
        }
        // The design's 1 pt window border.
        .padding(Spacing.hairline)
        .frame(width: OnboardingMetrics.windowSize.width, height: OnboardingMetrics.windowSize.height)
        .clipped()
        .background { SettingsWindowBackground() }
        // The title bar is part of the layout (the traffic-light row).
        .ignoresSafeArea()
        .id(flow.presentation)
    }

    private func navigate(_ change: () -> Void) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3)) {
            change()
        }
    }

    /// Welcome comes and goes on the leading side, Setup on the trailing side,
    /// so each direction reads as moving forward or back.
    private func pageTransition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

// MARK: - Step 1: Welcome (Onboarding-Welcome.dc.html)

private struct WelcomePage: View {
    let onContinue: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Traffic lights (system): padding 16 · 12 pt · 12.
            Color.clear.frame(height: 40)
            WelcomeHero(titleFocused: $titleFocused)
                .padding(.horizontal, 16)
            FeatureGrid()
                .padding(.top, 14)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                OnboardingPageDots(current: 0)
                Spacer(minLength: 0)
                Button(action: onContinue) {
                    Text("Continue", comment: "Onboarding step 1 button that goes to step 2")
                }
                .buttonStyle(PrimaryButtonStyle(size: .large, horizontalPadding: 24))
                .keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
        }
        .onAppear { titleFocused = true }
    }
}

private struct WelcomeHero: View {
    var titleFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Image(.appIconArt)
                    .resizable()
                    .frame(width: 58, height: 58)
                    // drop-shadow(0 6px 14px); see PopoverHeader for the radius.
                    .lidlessShadow(ShadowLayer(color: Palette.gold.opacity(0.3), radius: 14, y: 6))
                    .accessibilityLabel(Text("Lidless app icon", comment: "VoiceOver label of the app icon"))
                Text("Welcome to Lidless", comment: "Onboarding step 1 title")
                    .lidlessStyle(.onboardingTitle)
                    .foregroundStyle(Palette.white)
                    .lineBox(.onboardingTitle, lineHeight: 1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(titleFocused)
                Text("A small, open-source menu bar app for your MacBook's screen.", comment: "Onboarding step 1 introduction")
                    .lidlessStyle(.onboardingBody)
                    .foregroundStyle(Palette.textOnDark)
                    .lineBox(.onboardingBody, lineHeight: 1.45)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 262, alignment: .leading)
            DeskHeroArt(deskModeOn: true, width: 262)
                .accessibilityElement()
                .accessibilityLabel(Text("MacBook with lid open and screen off, next to a glowing monitor", comment: "VoiceOver label of the Desk Mode illustration when the built-in screen is off"))
                .accessibilityAddTraits(.isImage)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 24, leading: 28, bottom: 24, trailing: 24))
        // The board's 226 pt, taller if a translation needs it (the space
        // above the footer shrinks first).
        .frame(minHeight: 226)
        .background { HeroCardSurface(cornerRadius: Radius.heroOnboarding, elevation: .flat) }
    }
}

/// Three equal cards; the grid stretches them to the tallest.
private struct FeatureGrid: View {
    var body: some View {
        HStack(spacing: 10) {
            FeatureCard(
                glyph: .laptopSlash,
                tile: .dark,
                title: Text("Desk Mode", comment: "Onboarding feature card title"),
                detail: Text("Screen off, lid open. Your Mac runs cooler at a desk.", comment: "Onboarding Desk Mode card description")
            )
            FeatureCard(
                glyph: .sun,
                tile: .gold,
                title: Text("Brightness Boost", comment: "Onboarding feature card title"),
                detail: Text("Go past normal brightness on XDR screens, for bright rooms and sun.", comment: "Onboarding Brightness Boost card description")
            )
            FeatureCard(
                glyph: .shield,
                tile: .dark,
                title: Text("Safety net", comment: "Onboarding feature card title"),
                detail: Text("Unplug your displays and the built-in screen comes right back.", comment: "Onboarding Safety net card description")
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FeatureCard: View {
    let glyph: LidlessGlyph
    let tile: IconTile.Style
    let title: Text
    let detail: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            IconTile(glyph: glyph, style: tile)
                .accessibilityHidden(true)
            title
                .lidlessStyle(.featureTitle)
                .foregroundStyle(Palette.ink)
                .lineBox(.featureTitle)
                .padding(.top, 2)
            detail
                .lidlessStyle(.small)
                .foregroundStyle(Palette.text4)
                .lineBox(.small, lineHeight: 1.4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14 + Spacing.hairline)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { OnboardingCardSurface() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Step 2: Safety shortcut (Onboarding-Setup.dc.html)

private struct SetupPage: View {
    @ObservedObject var flow: OnboardingFlow
    let deskMode: DeskModeStore
    let onBack: () -> Void
    let onStart: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Traffic lights (system): padding 16 · 12 pt · 8.
            Color.clear.frame(height: 36)
            SetupHeader(titleFocused: $titleFocused)
                .padding(EdgeInsets(top: 0, leading: 48, bottom: 14, trailing: 48))
            PanicKeyHero(deskMode: deskMode, worked: flow.panicKeyWorked)
                .padding(.horizontal, 16)
            SetupChoices(
                turnOnWhenPluggedIn: $flow.turnOnWhenPluggedIn,
                launchAtLogin: $flow.launchAtLogin,
                showsLaunchAtLogin: flow.showsLaunchAtLogin
            )
            .padding(.top, 14)
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Text("Back", comment: "Onboarding step 2 button that returns to step 1")
                }
                .buttonStyle(SecondaryButtonStyle(size: .large, horizontalPadding: 18))
                OnboardingPageDots(current: 1)
                    .frame(maxWidth: .infinity)
                Button(action: onStart) {
                    Text("Start Using Lidless", comment: "Onboarding's last button: closes onboarding and opens the menu bar popover")
                }
                .buttonStyle(PrimaryButtonStyle(size: .large, horizontalPadding: 22))
                .keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
        }
        .onAppear { titleFocused = true }
    }
}

private struct SetupHeader: View {
    var titleFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 6) {
            Text("ONE LAST THING", comment: "Overline above the onboarding panic key title; uppercase on purpose")
                .lidlessStyle(.overlineHero)
                .foregroundStyle(Palette.goldDeepFixed)
                .lineBox(.overlineHero)
            Text("Learn your panic key", comment: "Onboarding step 2 title")
                .lidlessStyle(.onboardingTitle2)
                .foregroundStyle(Palette.ink)
                .lineBox(.onboardingTitle2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocused)
            Text("If you ever can't see a screen, press it. The built-in display comes back, no matter what.", comment: "Onboarding step 2 introduction; “it” is the panic key")
                .lidlessStyle(.onboardingBody)
                .foregroundStyle(Palette.text3)
                .lineBox(.onboardingBody, lineHeight: 1.45)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// The panic key as big keycaps with captions, and the "Try it now" status.
private struct PanicKeyHero: View {
    @ObservedObject var deskMode: DeskModeStore
    let worked: Bool

    var body: some View {
        let keys = deskMode.panicKeys
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ForEach(Array(keys.keycaps.enumerated()), id: \.element) { item in
                    let isLetter = item.offset == keys.keycaps.count - 1
                    VStack(spacing: 8) {
                        KeyCap(label: item.element, size: .large, isAccent: isLetter)
                        Self.caption(for: item.element, isLetter: isLetter)
                            .font(.system(size: 11, weight: isLetter ? .semibold : .regular))
                            .foregroundStyle(isLetter ? Palette.gold : Palette.textOnDark)
                            .lineBox(.caption)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: keys.spokenName))
            PanicKeyStatus(worked: worked)
        }
        .padding(EdgeInsets(top: 24, leading: 20, bottom: 18, trailing: 20))
        .frame(maxWidth: .infinity)
        .background { HeroCardSurface(cornerRadius: Radius.heroOnboarding, elevation: .flat) }
    }

    private static func caption(for keycap: String, isLetter: Bool) -> Text {
        if isLetter {
            return Text("back", comment: "Caption under the panic key's letter keycap in onboarding: the key that brings the screen back. Lowercase like the other captions.")
        }
        switch keycap {
        case "⌃": return Text("control", comment: "Caption under the Control keycap in onboarding; lowercase as printed on Apple keyboards")
        case "⌥": return Text("option", comment: "Caption under the Option keycap in onboarding; lowercase as printed on Apple keyboards")
        case "⇧": return Text("shift", comment: "Caption under the Shift keycap in onboarding; lowercase as printed on Apple keyboards")
        default: return Text("command", comment: "Caption under the Command keycap in onboarding; lowercase as printed on Apple keyboards")
        }
    }
}

/// "Try it now…" with a glowing dot, then a check mark once the key worked.
private struct PanicKeyStatus: View {
    let worked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if worked {
                    ViewBoxShape(path: Self.checkPath)
                        .stroke(Palette.gold, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 12)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(Palette.gold)
                        .frame(width: 8, height: 8)
                        .transition(.opacity)
                }
            }
            .lidlessShadow(.css(y: 0, blur: 8, color: Palette.gold.opacity(0.8)))
            .accessibilityHidden(true)
            statusText
                .lidlessStyle(.small)
                .foregroundStyle(Palette.textOnDark2)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background { Capsule().fill(Palette.white.opacity(0.08)) }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: worked)
        .accessibilityElement(children: .combine)
    }

    private var statusText: Text {
        worked
            ? Text(OnboardingCopy.panicKeyWorked)
            : Text("Try it now. We'll show a check mark when it works.", comment: "Onboarding status under the panic keycaps while waiting for the user to press the panic key")
    }

    /// A check mark in the glyphs' 24-point grid.
    private static let checkPath = Path { p in
        p.move(to: CGPoint(x: 5, y: 12.5))
        p.addLine(to: CGPoint(x: 10, y: 17.5))
        p.addLine(to: CGPoint(x: 19, y: 7))
    }
}

/// The two switches on step 2. They apply on "Start Using Lidless".
private struct SetupChoices: View {
    @Binding var turnOnWhenPluggedIn: Bool
    @Binding var launchAtLogin: Bool
    let showsLaunchAtLogin: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChoiceRow(
                title: Text("Turn on Desk Mode when I plug in a display", comment: "Onboarding switch: the rule that turns the built-in screen off when an external display is plugged in"),
                isOn: $turnOnWhenPluggedIn
            )
            if showsLaunchAtLogin {
                Rectangle()
                    .fill(Palette.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .accessibilityHidden(true)
                ChoiceRow(
                    title: Text("Start Lidless when I log in", comment: "Switch that registers Lidless as a login item"),
                    isOn: $launchAtLogin
                )
            }
        }
        .padding(Spacing.hairline)
        .background { OnboardingCardSurface() }
    }
}

private struct ChoiceRow: View {
    let title: Text
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            title
                .lidlessStyle(.body)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The switch carries the same label.
                .accessibilityHidden(true)
            Toggle(isOn: $isOn) { title }
                .toggleStyle(PillToggleStyle(size: .small))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
    }
}

// MARK: - Shared parts

/// `PageDots` for onboarding's two steps.
private struct OnboardingPageDots: View {
    let current: Int

    var body: some View {
        // PageDots labels itself "Step N of 2".
        PageDots(count: OnboardingMetrics.stepCount, current: current)
    }
}

/// The onboarding cards' `settingsCard` surface at r14: 0.84 white, a white
/// border, a 1 pt black 5% ring outside it and a soft warm drop.
private struct OnboardingCardSurface: View {
    var body: some View {
        let radius = Radius.card
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        shape.fill(Palette.white.opacity(0.84))
            .overlay { shape.strokeBorder(Palette.white.opacity(0.9), lineWidth: 1) }
            .background {
                RoundedRectangle(cornerRadius: radius + 1, style: .circular)
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                    .padding(-1)
            }
            .background {
                OuterShadow(cornerRadius: radius, far: .css(y: 2, blur: 8, color: Self.dropColor))
            }
            .accessibilityHidden(true)
    }

    /// rgba(40,30,10,0.06).
    private static let dropColor = Color(.sRGB, red: 40 / 255, green: 30 / 255, blue: 10 / 255, opacity: 0.06)
}

#if DEBUG
#Preview("Welcome") {
    OnboardingView(flow: .preview(step: .welcome), deskMode: DeskModeStore())
}

#Preview("Setup") {
    OnboardingView(flow: .preview(step: .setup), deskMode: DeskModeStore())
}

#Preview("Setup, key worked") {
    OnboardingView(flow: .preview(step: .setup, panicKeyWorked: true), deskMode: DeskModeStore())
}
#endif
