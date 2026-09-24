import AppKit
import Combine
import LidlessCore
import os
import SwiftUI

/// Owns the menu bar item and the popover panel that hangs from it.
///
/// macOS 27 hands the item's clicks, highlight and keyboard navigation to an
/// expanded-interface session; the panel then just follows the session.
/// macOS 12–26 use the button's action and do all of that by hand.
final class StatusItemController: NSObject, NSWindowDelegate {
    enum Presentation: Equatable {
        case hidden
        /// Opened by a click on macOS 12–26, or by the app itself on any version
        /// (there is no public API to start a session on 27).
        case legacy
        /// Opened by AppKit inside an expanded-interface session (macOS 27).
        case systemSession
    }

    let statusItem: NSStatusItem
    private(set) var presentation: Presentation = .hidden
    var isShown: Bool { presentation != .hidden }

    private let panel = StatusPanel()
    private let hostingView: StatusPanelHostingView
    private let sizeSink: PanelSizeSink
    /// SwiftUI's size for the whole window, shadow margin included.
    private var windowSize = PopoverMetrics.defaultWindowSize
    private var subscriptions: Set<AnyCancellable> = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var menuBarLocked = false
    private var fadeGeneration = 0
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "StatusItem")

    /// - Parameter iconShowsState: Settings › "Icon shows what's on".
    init(
        model: AppModel,
        actions: PopoverActions,
        iconShowsState: AnyPublisher<Bool, Never> = Just(true).eraseToAnyPublisher(),
        statusBar: NSStatusBar = .system
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        let sink = PanelSizeSink()
        sizeSink = sink
        hostingView = StatusPanelHostingView(rootView: StatusPanelRoot(model: model, actions: actions, sizeSink: sink))
        super.init()

        // The controller sets the window size; SwiftUI's size must never push the window around.
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            hostingView.setContentHuggingPriority(.defaultLow, for: orientation)
            hostingView.setContentCompressionResistancePriority(.defaultLow, for: orientation)
        }
        panel.contentView = StatusPanelContentView(hostingView: hostingView)
        panel.delegate = self
        panel.closeRequest = { [weak self] in
            self?.requestClose()
        }
        sizeSink.onChange = { [weak self] size in
            self?.contentSizeDidChange(size)
        }
        configureStatusItem()
        bindIcon(model: model, iconShowsState: iconShowsState)
    }

    // MARK: Public API

    /// Opens the panel from code (onboarding, a shortcut). On macOS 27 this
    /// can't start a session, so the item isn't highlighted (FB23688090).
    func open() {
        if !isShown { present(.legacy) }
    }

    func close(animated: Bool = true) {
        requestClose(animated: animated)
    }

    func toggle() {
        isShown ? requestClose() : open()
    }

    /// Closes cleanly before the app quits: ends the macOS 27 session and
    /// releases the menu bar so it can't stay stuck visible.
    func prepareForTermination() {
        requestClose(animated: false)
        unlockMenuBarIfNeeded()
    }

    // MARK: Status item

    private func configureStatusItem() {
        statusItem.autosaveName = "LidlessStatusItem"
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        if #available(macOS 27, *) {
            // The session replaces target/action; AppKit calls the delegate instead.
            button.target = nil
            button.action = nil
            statusItem.expandedInterfaceDelegate = self
        } else {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Open on mouse-down, like a menu.
            _ = button.sendAction(on: [.leftMouseDown])
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        isShown ? requestClose() : present(.legacy)
    }

    /// The glyph the item should show, published whenever it changes.
    static func iconStates(model: AppModel, iconShowsState: AnyPublisher<Bool, Never>) -> AnyPublisher<MenuBarIconState, Never> {
        // @Published emits before the property changes, so work from the emitted values.
        Publishers.CombineLatest4(
            model.deskMode.$state,
            model.brightness.$position,
            model.brightness.$scale,
            model.brightness.$boostAllowed
        )
        .combineLatest(iconShowsState)
        .map { values, showsState in
            let (desk, position, scale, boostAllowed) = values
            return MenuBarIconState.state(
                desk: desk.isOn,
                boosted: scale.allowingBoost(boostAllowed).isBoosted(position),
                iconShowsState: showsState
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    private func bindIcon(model: AppModel, iconShowsState: AnyPublisher<Bool, Never>) {
        Self.iconStates(model: model, iconShowsState: iconShowsState)
            .sink { [weak self] state in
                self?.applyIcon(state)
            }
            .store(in: &subscriptions)
    }

    private func applyIcon(_ state: MenuBarIconState) {
        guard let button = statusItem.button else { return }
        let image = NSImage(resource: state.imageResource)
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityLabel
        button.image = image
        button.setAccessibilityLabel(state.accessibilityLabel)
    }

    // MARK: Show and hide

    /// Every close goes through here: on macOS 27 it ends the session first.
    private func requestClose(animated: Bool = true) {
        guard isShown else { return }
        if #available(macOS 27, *), presentation == .systemSession, let session = statusItem.expandedInterfaceSession {
            session.cancel()
        }
        // Idempotent; also covers a session end that never arrives.
        dismiss(animated: animated)
    }

    private func present(_ mode: Presentation) {
        let wasShown = isShown
        fadeGeneration += 1
        presentation = mode
        if !wasShown {
            windowSize = measuredWindowSize()
        }
        reposition()
        // Lay out at the final size before the first frame is on screen.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        if NSApp.currentEvent?.type != .keyDown {
            // Opened with the mouse: no focus ring on the first control.
            panel.makeFirstResponder(nil)
        }
        installMonitors()
        installObservers()
        if mode == .legacy {
            scheduleLegacyHighlight()
            lockMenuBarIfNeeded()
        }
        log.debug("Presented (\(String(describing: mode), privacy: .public)) at \(NSStringFromRect(self.panel.frame), privacy: .public)")
    }

    private func dismiss(animated: Bool) {
        guard isShown else { return }
        let wasLegacy = presentation == .legacy
        presentation = .hidden
        removeMonitors()
        removeObservers()
        if wasLegacy { clearLegacyHighlight() }
        unlockMenuBarIfNeeded()

        fadeGeneration += 1
        let generation = fadeGeneration
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Reopened while fading: leave the new presentation alone.
                guard let self, self.fadeGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
    }

    // MARK: Highlight and menu bar (macOS 12–26; the session does both on 27)

    private func scheduleLegacyHighlight() {
        guard #unavailable(macOS 27) else { return }
        // The button clears its highlight when its mouse tracking ends. perform(afterDelay:)
        // runs in the default run loop mode, so after tracking; a main-queue block could
        // run inside the tracking loop and be undone on mouse-up.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyLegacyHighlight), object: nil)
        perform(#selector(applyLegacyHighlight), with: nil, afterDelay: 0)
    }

    @objc private func applyLegacyHighlight() {
        statusItem.button?.highlight(presentation == .legacy)
    }

    private func clearLegacyHighlight() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyLegacyHighlight), object: nil)
        guard #unavailable(macOS 27) else { return }
        statusItem.button?.highlight(false)
    }

    private func lockMenuBarIfNeeded() {
        guard #unavailable(macOS 27), !menuBarLocked else { return }
        menuBarLocked = true
        MenuBarVisibility.post(begin: true)
    }

    private func unlockMenuBarIfNeeded() {
        guard menuBarLocked else { return }
        menuBarLocked = false
        MenuBarVisibility.post(begin: false)
    }

    // MARK: Placement

    private func measuredWindowSize() -> CGSize {
        hostingView.layoutSubtreeIfNeeded()
        let ideal = hostingView.intrinsicContentSize
        if ideal.width > 1, ideal.height > 1 { return ideal }
        let fitting = hostingView.fittingSize
        if fitting.width > 1, fitting.height > 1 { return fitting }
        return windowSize
    }

    private func contentSizeDidChange(_ size: CGSize) {
        guard size.width > 1, size.height > 1,
              abs(size.width - windowSize.width) > 0.5 || abs(size.height - windowSize.height) > 0.5
        else { return }
        windowSize = size
        log.debug("Content size \(size.width, privacy: .public)×\(size.height, privacy: .public)")
        if isShown { reposition() }
    }

    /// The status item button in screen coordinates, if it is on screen.
    private func statusButtonScreenRect() -> CGRect? {
        guard statusItem.isVisible, let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private struct PlacementTarget {
        var anchor: PanelPlacement.Anchor?
        var screen: ScreenGeometry
    }

    /// The screen the panel opens on and the item it hangs from, if it can use one.
    private func placementTarget() -> PlacementTarget? {
        let screens = NSScreen.screens.map(ScreenGeometry.init)
        var anchor: PanelPlacement.Anchor?
        if let rect = statusButtonScreenRect(), let window = statusItem.button?.window {
            let candidate = PanelPlacement.Anchor(buttonRect: rect, menuBarBottom: Self.menuBarBottom(itemWindow: window, buttonRect: rect))
            anchor = PanelPlacement.isUsable(candidate, on: screens) ? candidate : nil
        }
        guard let index = PanelPlacement.screenIndex(for: anchor, pointer: NSEvent.mouseLocation, in: screens) else { return nil }
        return PlacementTarget(anchor: anchor, screen: screens[index])
    }

    /// Tells SwiftUI how tall the panel may be on the target screen, so the
    /// content fits the panel instead of running past its bottom edge.
    /// Returns whether that changed.
    private func updateHeightLimit(for target: PlacementTarget) -> Bool {
        let limit = PanelPlacement.maxVisualHeight(
            anchor: target.anchor,
            screen: target.screen,
            gap: PopoverMetrics.gapBelowMenuBar,
            margin: PopoverMetrics.screenMargin
        )
        guard hostingView.rootView.maxPanelHeight != limit else { return false }
        hostingView.rootView.maxPanelHeight = limit
        log.debug("Panel height limit \(limit, privacy: .public)")
        return true
    }

    private func reposition() {
        guard let target = placementTarget() else { return }
        if updateHeightLimit(for: target) {
            // SwiftUI lays out for the new room synchronously.
            windowSize = measuredWindowSize()
        }
        let insets = PopoverMetrics.placementInsets
        let visualSize = CGSize(
            width: max(1, windowSize.width - insets.horizontal),
            height: max(1, windowSize.height - insets.vertical)
        )
        // SwiftUI already fits the limit; the clamp is only a safety net.
        let visual = PanelPlacement.visualFrame(
            size: visualSize,
            anchor: target.anchor,
            screen: target.screen,
            gap: PopoverMetrics.gapBelowMenuBar,
            margin: PopoverMetrics.screenMargin
        )
        let frame = PanelPlacement.windowFrame(visual: visual, insets: insets)
        if panel.frame != frame {
            panel.setFrame(frame, display: isShown)
        }
    }

    /// Bottom edge of the menu bar holding the item. The button can be shorter
    /// than the bar on notched displays, and on macOS 27 the item's window is as
    /// tall as the tallest menu bar of any display, centred on this one's
    /// (39 pt around a 30 pt bar), so the bar's own reserved area is preferred.
    private static func menuBarBottom(itemWindow: NSWindow, buttonRect: CGRect) -> CGFloat {
        let mid = CGPoint(x: buttonRect.midX, y: buttonRect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mid) }) else { return itemWindow.frame.minY }
        // An auto-hidden or full-screen menu bar reserves nothing.
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        return reserved > 0 ? screen.visibleFrame.maxY : itemWindow.frame.minY
    }

    // MARK: Event monitors

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps, the desktop or other status items. On macOS 27 a
        // click on our own item arrives here too.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleGlobalMouseDown(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.filterLocalEvent(event)
        }
    }

    private func handleGlobalMouseDown(_ event: NSEvent) {
        // The event's own location: NSEvent.mouseLocation is read later and may have moved.
        let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        if let button = statusButtonScreenRect(), button.contains(point) {
            // A second click on the item doesn't end a macOS 27 session (the menu
            // bar sends nothing), so it closes the panel here. A panel opened from
            // code gets a new session from that click, and didBegin closes it.
            guard presentation == .systemSession else { return }
        }
        requestClose()
    }

    private func filterLocalEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            guard event.keyCode == 53 else { return event } // kVK_Escape
            requestClose()
            return nil
        }
        if event.window === panel {
            // The shadow margin is part of our window but reads as "outside".
            let visual = PanelPlacement.visualRect(inWindowOf: panel.frame.size, insets: PopoverMetrics.placementInsets)
            guard visual.contains(event.locationInWindow) else {
                requestClose()
                return nil
            }
            return event
        }
        if let buttonWindow = statusItem.button?.window, event.window === buttonWindow {
            // The button action (12–26) or the session (27) toggles.
            return event
        }
        // Another Lidless window, such as Settings.
        requestClose()
        return event
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    // MARK: Observers

    private func installObservers() {
        removeObservers()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersDidChange() }
        })
        if let buttonWindow = statusItem.button?.window {
            // Items shift when others appear or change width.
            for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
                observers.append(center.addObserver(forName: name, object: buttonWindow, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reposition() }
                })
            }
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestClose() }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestClose(animated: false) }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.requestClose() }
        })
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.removeAll()
    }

    private func screenParametersDidChange() {
        // Displays came, went or changed scale. Desk Mode turning the built-in off
        // lands here if the panel was still on it.
        guard let screen = panel.screen, NSScreen.screens.contains(screen) else {
            requestClose(animated: false)
            return
        }
        reposition()
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Inside a macOS 27 session AppKit owns the lifecycle; losing key isn't a dismissal.
        guard presentation == .legacy else { return }
        // A click on our own item takes key first; let the button action or the
        // session begin/cancel handle it, or the panel closes and reopens.
        if let button = statusButtonScreenRect(), button.contains(NSEvent.mouseLocation) { return }
        requestClose()
    }
}

// MARK: - macOS 27 expanded interface session

@available(macOS 27, *)
extension StatusItemController: @MainActor NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) {
        switch presentation {
        case .legacy:
            // Opened from code, then the item was clicked: that click means "close".
            expandedInterfaceSession.cancel()
            dismiss(animated: true)
        case .hidden:
            present(.systemSession)
        case .systemSession:
            break
        }
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        guard presentation == .systemSession else { return }
        dismiss(animated: animated)
    }
}

// MARK: - Helpers

private enum MenuBarVisibility {
    /// Keeps an auto-hidden or full-screen menu bar down while the panel is open
    /// (undocumented HIToolbox notification; macOS 12–26 only).
    static func post(begin: Bool) {
        let name = Notification.Name(begin ? "com.apple.HIToolbox.beginMenuTrackingNotification" : "com.apple.HIToolbox.endMenuTrackingNotification")
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

extension ScreenGeometry {
    init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            backingScale: screen.backingScaleFactor,
            notch: ScreenGeometry.notch(topLeftArea: screen.auxiliaryTopLeftArea, topRightArea: screen.auxiliaryTopRightArea)
        )
    }
}

extension MenuBarIconState {
    var imageResource: ImageResource {
        switch self {
        case .normal: .menuBarNormal
        case .deskMode: .menuBarDesk
        case .boost: .menuBarBoost
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .normal: String(localized: "Lidless menu", comment: "VoiceOver label of the menu bar icon")
        case .deskMode: String(localized: "Lidless menu, Desk Mode on", comment: "VoiceOver label of the menu bar icon")
        case .boost: String(localized: "Lidless menu, Boost on", comment: "VoiceOver label of the menu bar icon")
        }
    }
}
