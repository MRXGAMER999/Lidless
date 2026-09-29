import AppKit
import Combine
import SwiftUI

/// The Settings window (design-spec §7.1, `Settings2-*`): a fixed 880×720
/// window with a hidden title bar. The traffic lights sit in a 56 pt title row
/// beside the centred section switcher and the app icon; the tab fills the rest.
///
/// Only the light appearance is designed, so the window is always light, as
/// onboarding is. The title stays set, hidden, for VoiceOver and the Window menu.
final class SettingsWindow: NSWindow {
    static let contentSize = NSSize(width: 880, height: 720)
    static let titleRowHeight: CGFloat = 56
    private static let autosaveName = "LidlessSettingsWindow"
    /// A title-bar button layout is waiting for the run loop (`windowButtonsNeedLayout`).
    private var buttonsLayoutQueued = false

    init(navigation: SettingsNavigation, model: AppModel, actions: SettingsActions, launchAtLogin: any LaunchAtLogin) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        title = Self.title
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenNone]
        tabbingMode = .disallowed
        appearance = NSAppearance(named: .aqua)

        let hostingView = NSHostingView(rootView: SettingsRootView(
            navigation: navigation,
            model: model,
            actions: actions,
            launchAtLogin: launchAtLogin
        ))
        if #available(macOS 13, *) {
            // The window's size is fixed; SwiftUI must never resize it.
            hostingView.sizingOptions = []
        }
        contentView = hostingView
        setContentSize(Self.contentSize)
        center()
        // Restores the last position; the size stays fixed.
        setFrameAutosaveName(Self.autosaveName)
        setContentSize(Self.contentSize)

        observeWindowButtons()
        layOutWindowButtons()
    }

    /// "Lidless Settings", or "Lidless Preferences" on macOS 12, which still
    /// calls them Preferences.
    static var title: String {
        if #available(macOS 13, *) {
            return String(localized: "Lidless Settings", comment: "Title of the Settings window (hidden; read by VoiceOver and shown in the Window menu)")
        } else {
            return String(localized: "Lidless Preferences", comment: "Title of the Settings window on macOS 12, which calls settings Preferences (hidden; read by VoiceOver and shown in the Window menu)")
        }
    }

    // MARK: Traffic lights

    /// Centres the traffic lights in the 56 pt title row, the way Electron's
    /// `trafficLightPosition` does: the title bar container grows to the row's
    /// height and the buttons move down to its middle, keeping their x. Does
    /// nothing if AppKit's view hierarchy isn't the expected one.
    private func layOutWindowButtons() {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(standardWindowButton)
        guard let first = buttons.first, let container = first.superview?.superview,
              let frameView = container.superview else { return }
        // The row sits inside the 1 pt window border: centred 1 + 28 pt down.
        let height = Self.titleRowHeight + 2 * Spacing.hairline
        var frame = container.frame
        frame.size.height = height
        frame.origin.y = frameView.bounds.height - height
        if container.frame != frame { container.frame = frame }
        for button in buttons {
            guard let row = button.superview else { continue }
            let y = ((row.bounds.height - button.frame.height) / 2).rounded()
            if button.frame.origin.y != y { button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y)) }
        }
    }

    /// AppKit lays the title bar out again on its own (key changes, screen
    /// changes, appearance): follow every move of the container or a button.
    private func observeWindowButtons() {
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification,
                     NSWindow.didDeminiaturizeNotification] {
            center.addObserver(self, selector: #selector(windowButtonsNeedLayout(_:)), name: name, object: self)
        }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(standardWindowButton)
        let views = buttons + [buttons.first?.superview?.superview].compactMap { $0 }
        for view in views {
            view.postsFrameChangedNotifications = true
            center.addObserver(self, selector: #selector(windowButtonsNeedLayout(_:)), name: NSView.frameDidChangeNotification, object: view)
        }
    }

    @objc private func windowButtonsNeedLayout(_ notification: Notification) {
        guard notification.name == NSView.frameDidChangeNotification else {
            layOutWindowButtons()
            return
        }
        // A button or its container moved inside AppKit's own title-bar layout
        // pass: moving them again from there can recurse. Lay out once, after it.
        guard !buttonsLayoutQueued else { return }
        buttonsLayoutQueued = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                self?.buttonsLayoutQueued = false
                self?.layOutWindowButtons()
            }
        }
    }
}

/// Which Settings tab shows. The coordinator sets it; the section switcher binds to it.
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .deskMode
}

/// Title row plus the selected tab.
struct SettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigation
    let model: AppModel
    let actions: SettingsActions
    let launchAtLogin: any LaunchAtLogin

    var body: some View {
        VStack(spacing: 0) {
            SettingsTitleRow(selection: $navigation.tab)
            tabContent
                .padding(EdgeInsets(top: 0, leading: Spacing.settingsPadding, bottom: Spacing.settingsPadding, trailing: Spacing.settingsPadding))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // The board's 1 pt window border: content 878×718, cards 842 wide.
        .padding(Spacing.hairline)
        .frame(width: SettingsWindow.contentSize.width, height: SettingsWindow.contentSize.height)
        .background(SettingsBackdrop())
        // The content reaches under the (transparent) title bar.
        .ignoresSafeArea()
        .settingsAccessibilityOptions()
    }

    @ViewBuilder private var tabContent: some View {
        switch navigation.tab {
        case .deskMode:
            DeskModeTab(model: model, preferences: model.preferences, actions: actions)
        case .brightness:
            BrightnessTab(model: model, preferences: model.preferences, actions: actions)
        case .keysAndApp:
            KeysTab(model: model, preferences: model.preferences, actions: actions, launchAtLogin: launchAtLogin)
        }
    }
}

/// The 56 pt row: a 90 pt slot for the traffic lights, the centred section
/// switcher, and the app icon right-aligned in a 90 pt slot.
private struct SettingsTitleRow: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 90, height: 1)
            Spacer(minLength: 0)
            // Labelled "Settings sections" by SegmentedNav itself, which reads
            // as one control with the selected tab and its position.
            SegmentedNav(selection: $selection, tabs: SettingsTab.allCases, title: \.title, glyph: \.glyph)
                .modifier(TabBarTrait())
                // Increase Contrast: the grey track gets an edge.
                .overlay { IncreasedContrastRing(shape: Capsule()) }
            Spacer(minLength: 0)
            Image(.appIconArt)
                .resizable()
                .frame(width: 26, height: 26)
                .frame(width: 90, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(height: SettingsWindow.titleRowHeight)
        // The title bar is transparent and covered by content: this keeps the
        // row's empty space working as one.
        .background(WindowDragArea())
    }
}

/// Announces the section switcher as a tab group (macOS 14 and later; before
/// that it stays a segmented control, which reads the same apart from the role).
private struct TabBarTrait: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.accessibilityAddTraits(.isTabBar)
        } else {
            content
        }
    }
}

/// Moves the window when dragged, like a title bar, and applies the user's
/// title-bar double-click action (only "Minimize" applies: zoom is disabled).
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                if UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") == "Minimize" {
                    window.performMiniaturize(nil)
                }
                return
            }
            window.performDrag(with: event)
        }
    }
}

#Preview("Desk Mode") {
    SettingsRootView(
        navigation: SettingsNavigation(),
        model: SampleData.deskSetup(),
        actions: SettingsActions(),
        launchAtLogin: LaunchAtLoginService()
    )
}
