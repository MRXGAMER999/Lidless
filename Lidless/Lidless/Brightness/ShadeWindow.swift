import AppKit
import CoreGraphics
import LidlessCore

/// A dimming overlay for one external display, as `ExternalBrightnessController`
/// sees it. Main-actor; tests use a fake.
protocol ExternalShade: AnyObject {
    /// Covers the display at brightness `level` 0...1 (full brightness removes
    /// the window). Changes only the opacity while shown. False when the screen
    /// isn't found or the display is the built-in.
    @discardableResult
    func show(level: Double) -> Bool
    /// Sizes a shown window to its screen again (after a display change).
    /// False when it isn't shown or the screen is gone; then it's removed.
    @discardableResult
    func refit() -> Bool
    /// Takes the window off the screen. Safe to call twice.
    func remove()
    /// A window is up. It removes itself when AppKit moves it to another
    /// screen or its screen goes away, and waits for the next `show`.
    var isShown: Bool { get }
}

/// Software dimming for an external monitor that can't be dimmed any other
/// way: a black, click-through `OverlayPanel` whose opacity comes from
/// `ShadeMath`, so the screen never goes fully black.
///
/// It never goes on the built-in screen or a mirror set, and gamma tables are
/// never touched. The window lives in our process, so a crash or quit removes
/// it. The hardware cursor isn't dimmed.
///
/// Screenshots and recordings: `OverlayPanel` sets `sharingType = .none`, so
/// the legacy capture APIs (`CGWindowListCreateImage` and friends) leave the
/// shade out, but ScreenCaptureKit on macOS 15.4 and later may include it
/// anyway (phase4-research §4.2). Whether a screenshot or a shared screen
/// comes out dimmed is to be checked on the Mac.
///
/// The owner calls `remove()` before letting go of a shade.
final class ShadeWindow: ExternalShade {
    let displayID: CGDirectDisplayID
    private var panel: OverlayPanel?

    /// One below the main menu level (23), so the shade covers app windows,
    /// floating panels and the Dock, but not the menu bar and its status items,
    /// and never Lidless's own windows at `.statusBar`: the keep-or-revert
    /// prompt (`ConfirmationPanel`) and the popover (`StatusPanel`) must stay
    /// readable on a dimmed display. Pop-up menus sit higher and stay
    /// undimmed too. Below `.mainMenu`, not at it, so the
    /// menu bar is never half-covered by window order within one level.
    ///
    /// Full-screen apps are still covered: their windows sit at the normal
    /// level in their own Space, and `OverlayPanel` joins every Space as a
    /// full-screen auxiliary window (`.canJoinAllSpaces`, `.fullScreenAuxiliary`,
    /// `.stationary`). A game that captures the display draws above every
    /// window level, shade included.
    static var windowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
    }

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    var isShown: Bool { panel != nil }

    @discardableResult
    func show(level: Double) -> Bool {
        let alpha = ShadeMath.alpha(forLevel: level)
        guard alpha > 0 else {
            // Nothing to dim: no window, so full-screen video keeps direct scan-out.
            remove()
            return true
        }
        guard Self.mayCover(displayID) else {
            remove()
            return false
        }
        if let panel {
            panel.alphaValue = CGFloat(alpha)
            return true
        }
        let panel = OverlayPanel(displayID: displayID, level: Self.windowLevel)
        // OverlayPanel is already clear, click-through and shadowless.
        panel.backgroundColor = .black
        panel.alphaValue = CGFloat(alpha)
        panel.onLost = { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            self.panel = nil
        }
        guard panel.present() else {
            panel.remove()
            return false
        }
        self.panel = panel
        return true
    }

    @discardableResult
    func refit() -> Bool {
        guard let panel else { return false }
        guard Self.mayCover(displayID), panel.present() else {
            remove()
            return false
        }
        return true
    }

    /// Never the built-in, whatever the caller thinks the display is, and
    /// nothing in a mirror set: the built-in may be showing the same pixels.
    private static func mayCover(_ display: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(display) == 0 && CGDisplayIsInMirrorSet(display) == 0
    }

    func remove() {
        guard let panel else { return }
        self.panel = nil
        panel.onLost = nil
        panel.remove()
    }
}
