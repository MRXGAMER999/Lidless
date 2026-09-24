import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import LidlessCore
import SwiftUI

/// The keep-or-revert prompt (safety.md §5): a floating, non-activating panel
/// centred on the display Desk Mode left on, over full-screen apps and on
/// every Space.
///
/// It never decides anything. The controller's ticks enforce the deadline, so
/// a hidden or covered panel still reverts on time. It doesn't take keyboard
/// focus when it appears, so typing in another app can't answer it; once
/// clicked it handles Escape (Turn Back On), Tab (moves focus between the two
/// buttons) and Space (presses the focused one). Return does nothing.
final class ConfirmationPanel: ConfirmationPresenter {
    private let deskMode: DeskModeStore
    private let model = ConfirmHUDModel()
    private let sizeSink = PanelSizeSink()
    private var window: ConfirmationWindow?
    private var hostingView: ConfirmationHostingView?
    /// The window size SwiftUI last asked for, shadow margin included.
    private var windowSize = HUDMetrics.defaultWindowSize
    private var displayUUID: String?
    /// Only while shown; its block holds `self` weakly, so the app-lifetime
    /// presenter needs no deinit.
    private var screenObserver: (any NSObjectProtocol)?

    /// - Parameter deskMode: Supplies the panic shortcut for the footer, named
    ///   by the keyboard layout in use.
    init(deskMode: DeskModeStore) {
        self.deskMode = deskMode
        sizeSink.onChange = { [weak self] size in
            self?.contentSizeDidChange(size)
        }
    }

    // MARK: ConfirmationPresenter

    func show(
        deadline: TimeInterval,
        total: TimeInterval,
        onDisplayUUID: String?,
        keep: @escaping @MainActor () -> Void,
        revert: @escaping @MainActor () -> Void
    ) {
        let window = window ?? makeWindow()
        if !model.isShown {
            // A new prompt: fresh view state (VoiceOver intro), no focus.
            model.presentation &+= 1
            model.focus = nil
        }
        model.countdown = ConfirmationCountdown(deadline: deadline, total: total)
        model.keep = keep
        model.revert = revert
        model.isShown = true
        displayUUID = onDisplayUUID
        if let hostingView {
            windowSize = Self.measuredSize(of: hostingView, fallback: windowSize)
        }
        place(window)
        window.orderFrontRegardless()
        observeScreens()
    }

    func hide() {
        model.isShown = false
        model.focus = nil
        // Stops the view's timelines and announcements.
        model.countdown.deadline = 0
        window?.orderOut(nil)
        stopObservingScreens()
    }

    // MARK: Window

    private func makeWindow() -> ConfirmationWindow {
        let window = ConfirmationWindow(size: windowSize)
        let root = ConfirmationPanelRoot(
            model: model,
            deskMode: deskMode,
            sizeSink: sizeSink,
            announce: { [weak window] text in
                ConfirmHUDView.postAnnouncement(text, from: window ?? NSApp as Any)
            }
        )
        let hostingView = ConfirmationHostingView(rootView: root)
        // The panel sets the window size; SwiftUI's size must never push the window around.
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            hostingView.setContentHuggingPriority(.defaultLow, for: orientation)
            hostingView.setContentCompressionResistancePriority(.defaultLow, for: orientation)
        }
        window.contentView = ConfirmationContentView(hostingView: hostingView, size: windowSize)
        window.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.window = window
        self.hostingView = hostingView
        return window
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard model.isShown else { return false }
        // ⌘ and ⌃ combinations go on to the menus as usual.
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape:
            if !event.isARepeat { model.press(.turnBackOn) }
            return true
        case kVK_Tab:
            model.moveFocus(backward: event.modifierFlags.contains(.shift))
            return true
        case kVK_Space:
            if !event.isARepeat, let focus = model.focus { model.press(focus) }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // Never a default button: someone who can't see this screen must
            // not keep the built-in off by pressing Return.
            return true
        default:
            return false
        }
    }

    // MARK: Placement

    private func contentSizeDidChange(_ size: CGSize) {
        guard size.width > 1, size.height > 1,
              abs(size.width - windowSize.width) > 0.5 || abs(size.height - windowSize.height) > 0.5
        else { return }
        windowSize = size
        if model.isShown, let window { place(window) }
    }

    /// Centres the card (not the shadow margin) in the target screen's visible area.
    private func place(_ window: NSWindow) {
        guard let screen = targetScreen() else { return }
        let insets = HUDMetrics.shadowInsets
        let area = screen.visibleFrame
        let card = CGSize(
            width: windowSize.width - insets.left - insets.right,
            height: windowSize.height - insets.top - insets.bottom
        )
        let origin = CGPoint(
            x: (area.midX - card.width / 2 - insets.left).rounded(),
            y: (area.midY - card.height / 2 - insets.bottom).rounded()
        )
        let frame = NSRect(origin: origin, size: windowSize)
        if window.frame != frame {
            window.setFrame(frame, display: window.isVisible)
        }
    }

    /// The display with `displayUUID`; failing that the main screen, unless
    /// that is the built-in (black out keeps it in the list, covered); then any
    /// other screen.
    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let uuid = displayUUID,
           let match = screens.first(where: { Self.uuid(of: $0)?.caseInsensitiveCompare(uuid) == .orderedSame }) {
            return match
        }
        if let main = NSScreen.main, !Self.isBuiltIn(main) { return main }
        return screens.first { !Self.isBuiltIn($0) } ?? NSScreen.main ?? screens.first
    }

    /// `NSScreen.screens` is a snapshot refreshed just before this notification,
    /// so a display arriving, leaving or changing mode moves the panel here.
    private func observeScreens() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.isShown, let window = self.window else { return }
                self.place(window)
            }
        }
    }

    private func stopObservingScreens() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    private static func measuredSize(of hostingView: NSView, fallback: CGSize) -> CGSize {
        hostingView.layoutSubtreeIfNeeded()
        let ideal = hostingView.intrinsicContentSize
        if ideal.width > 1, ideal.height > 1 { return ideal }
        let fitting = hostingView.fittingSize
        if fitting.width > 1, fitting.height > 1 { return fitting }
        return fallback
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        if #available(macOS 26.0, *) {
            return screen.cgDirectDisplayID
        }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func uuid(of screen: NSScreen) -> String? {
        guard let id = displayID(of: screen),
              let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, cf) as String?
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        displayID(of: screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }
}

// MARK: - Model

/// What the HUD shows, and where its buttons lead.
final class ConfirmHUDModel: ObservableObject {
    @Published var countdown = ConfirmationCountdown(deadline: 0)
    @Published var focus: ConfirmHUDButton?
    /// Bumped for each new prompt, so the view starts from fresh state.
    @Published var presentation = 0
    /// Buttons and keys do nothing once the prompt is gone.
    var isShown = false
    var keep: @MainActor () -> Void = {}
    var revert: @MainActor () -> Void = {}

    func press(_ button: ConfirmHUDButton) {
        guard isShown else { return }
        switch button {
        case .turnBackOn: revert()
        case .keepOff: keep()
        }
    }

    /// Tab order: Turn Back On, then Keep Off. The first Tab lands on the safe one.
    func moveFocus(backward: Bool) {
        switch focus {
        case nil: focus = backward ? .keepOff : .turnBackOn
        case .turnBackOn: focus = .keepOff
        case .keepOff: focus = .turnBackOn
        }
    }
}

// MARK: - AppKit

private nonisolated enum HUDMetrics {
    /// Transparent margin around the card for its `0 24px 60px` shadow.
    static let shadowInsets = NSEdgeInsets(top: 40, left: 68, bottom: 100, right: 68)
    /// The design's card (380 × 295.7) plus the margin, until SwiftUI reports its size.
    static let defaultWindowSize = CGSize(
        width: 380 + shadowInsets.left + shadowInsets.right,
        height: 296 + shadowInsets.top + shadowInsets.bottom
    )
}

/// Borderless, transparent and non-activating: it floats over full-screen
/// apps on every Space and never activates Lidless, but becomes key when
/// clicked so Escape and Tab reach it.
private final class ConfirmationWindow: NSPanel {
    /// Returns true when it handled the key.
    var keyHandler: ((NSEvent) -> Bool)?

    init(size: CGSize) {
        // `.nonactivatingPanel` only takes effect when it is in the initial style mask.
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        // Still answers while one of our own modal alerts is up.
        worksWhenModal = true
        isOpaque = false
        backgroundColor = .clear
        // SwiftUI draws the design's shadow inside the transparent margin.
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        setAccessibilityTitle(ConfirmHUDView.title)
        setAccessibilitySubrole(.dialog)
    }

    // Borderless windows refuse key status by default.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Takes the prompt's keys before SwiftUI sees them, so they work the same
    /// with Full Keyboard Access on or off.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// The blur behind the card, masked to its rounded rect and always active:
/// Lidless is nearly always in the background, where a SwiftUI material
/// would draw its flat inactive look. SwiftUI draws the wash on top.
private final class ConfirmationContentView: NSView {
    init(hostingView: NSView, size: CGSize) {
        super.init(frame: NSRect(origin: .zero, size: size))
        let insets = HUDMetrics.shadowInsets
        let backdrop = NSVisualEffectView(frame: NSRect(
            x: insets.left,
            y: insets.bottom,
            width: size.width - insets.left - insets.right,
            height: size.height - insets.top - insets.bottom
        ))
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.maskImage = PanelMask.roundedRect(radius: Radius.hud)
        // Fixed margins, so it follows the card when the window resizes.
        backdrop.autoresizingMask = [.width, .height]
        addSubview(backdrop)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// Lets the first click on a button land even though the panel isn't key yet.
private final class ConfirmationHostingView: NSHostingView<ConfirmationPanelRoot> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Root of the hosting view: the HUD at its ideal size inside the shadow
/// margin, reporting that size so the window can follow it.
private struct ConfirmationPanelRoot: View {
    @ObservedObject var model: ConfirmHUDModel
    @ObservedObject var deskMode: DeskModeStore
    let sizeSink: PanelSizeSink
    let announce: (String) -> Void

    var body: some View {
        ConfirmHUDView(
            countdown: model.countdown,
            panicKeys: deskMode.panicKeys,
            focus: model.focus,
            revert: { model.press(.turnBackOn) },
            keep: { model.press(.keepOff) },
            announce: announce
        )
        .id(model.presentation)
        .fixedSize()
        .padding(EdgeInsets(
            top: HUDMetrics.shadowInsets.top,
            leading: HUDMetrics.shadowInsets.left,
            bottom: HUDMetrics.shadowInsets.bottom,
            trailing: HUDMetrics.shadowInsets.right
        ))
        .reportingSize(to: sizeSink)
        // Zero minimum so the hosting view never forces the window bigger
        // than the panel made it.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
    }
}
