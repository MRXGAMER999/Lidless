import AppKit
import os

/// A borderless, click-through panel pinned to one display: the base for the
/// Boost overlay (built-in) and the dimming shades (externals).
///
/// It covers the whole screen at `level`, joins every Space and full-screen
/// app, never takes focus, and removes itself (calling `onLost`) the moment
/// AppKit moves it to another screen or its screen goes away. It never
/// re-appears by itself.
final class OverlayPanel: NSPanel {
    /// The display this panel belongs to.
    let displayID: CGDirectDisplayID
    /// Called on the main actor after the panel removed itself.
    var onLost: (@MainActor () -> Void)?

    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Overlay")
    /// Between `present` and `remove`: screen changes are checked.
    private var isWatching = false

    /// - Parameters:
    ///   - displayID: The screen to cover.
    ///   - level: `CGShieldingWindowLevel()` for Boost, `.mainMenu - 1` for shades (below the menu bar and Lidless's own panels).
    init(displayID: CGDirectDisplayID, level: NSWindow.Level) {
        self.displayID = displayID
        // `.nonactivatingPanel` only takes effect when it is in the initial style mask.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        self.level = level
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        // A menu bar app is nearly always inactive; a panel that hid on
        // deactivate (or with the app) would drop the overlay unannounced.
        hidesOnDeactivate = false
        canHide = false
        isMovable = false
        // Asks captures to leave the panel out. The legacy window-capture APIs
        // honour it, but ScreenCaptureKit ignores `.none` since macOS 15.4
        // (research: phase4-research §4.2, boost.md §5), and that is what
        // screenshots, recordings and screen sharing use today: expect them to
        // include the overlay (a shade dims them; Boost's multiply may show or
        // clip). Kept for older systems and legacy capture. Unverified on the
        // Mac: check with ⇧⌘3/⇧⌘5 and a screen share.
        sharingType = .none
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        if #available(macOS 13.0, *) {
            behavior.insert(.canJoinAllApplications)
        }
        collectionBehavior = behavior
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The `NSScreen` for `displayID`, if connected (`cgDirectDisplayID` on
    /// macOS 26+, else `NSScreenNumber`).
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { Self.displayID(of: $0) == displayID }
    }

    /// The display ID behind an `NSScreen`.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        if #available(macOS 26.0, *) {
            return screen.cgDirectDisplayID
        }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Sizes the panel to its screen and orders it front. False when the screen is gone.
    @discardableResult
    func present() -> Bool {
        guard let screen = Self.screen(for: displayID) else {
            remove()
            return false
        }
        if frame != screen.frame {
            setFrame(screen.frame, display: false)
        }
        orderFrontRegardless()
        // Borderless windows aren't constrained, so a frame equal to the
        // screen's always lands on it; checked anyway, never trusted.
        if let current = self.screen, Self.displayID(of: current) != displayID {
            log.error("Overlay for display \(self.displayID) landed on another screen")
            remove()
            return false
        }
        startWatching()
        return true
    }

    /// Orders the panel out and stops watching screens. Safe to call twice.
    func remove() {
        stopWatching()
        orderOut(nil)
    }

    // MARK: - Watching the screen

    private func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        // Selector observers go away with the panel, so no token outlives it.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged(_:)), name: NSWindow.didChangeScreenNotification, object: self)
        center.addObserver(self, selector: #selector(screensChanged(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func stopWatching() {
        guard isWatching else { return }
        isWatching = false
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: self)
        center.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screensChanged(_ note: Notification) {
        guard isWatching else { return }
        guard let screen = Self.screen(for: displayID) else {
            lost("its screen is gone")
            return
        }
        guard let current = self.screen, Self.displayID(of: current) == displayID else {
            lost("it left its screen")
            return
        }
        // Same screen, new size (a resolution change): follow it.
        if frame != screen.frame {
            setFrame(screen.frame, display: true)
        }
    }

    private func lost(_ why: String) {
        log.notice("Overlay for display \(self.displayID) removed: \(why, privacy: .public)")
        remove()
        onLost?()
    }
}
