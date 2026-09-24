import CoreGraphics
import Foundation

/// A screen, reduced to the numbers the popover placement needs.
///
/// All rects use AppKit screen coordinates: origin at the bottom left of the
/// primary display, y growing upwards.
public struct ScreenGeometry: Sendable, Equatable {
    public var frame: CGRect
    /// The frame minus the menu bar and the Dock.
    public var visibleFrame: CGRect
    /// The menu bar height on displays with a camera housing, otherwise 0.
    public var safeAreaTop: CGFloat
    public var backingScale: CGFloat
    /// The camera housing at the top of the display, if it has one.
    public var notch: CGRect?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat = 0, backingScale: CGFloat = 2, notch: CGRect? = nil) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.backingScale = backingScale
        self.notch = notch
    }

    /// The camera housing lies between the two unobscured areas either side of it.
    public static func notch(topLeftArea: CGRect?, topRightArea: CGRect?) -> CGRect? {
        guard let left = topLeftArea, let right = topRightArea, right.minX > left.maxX else { return nil }
        return CGRect(x: left.maxX, y: min(left.minY, right.minY), width: right.minX - left.maxX, height: max(left.height, right.height))
    }
}

/// Where the menu bar popover goes on screen.
///
/// The popover window is larger than the panel people see: a transparent
/// margin around the panel holds its drop shadow. "Visual" rects below are
/// the panel itself; "window" rects include the margin.
public enum PanelPlacement {
    /// The status item the panel hangs from.
    public struct Anchor: Sendable, Equatable {
        /// The status item button, in screen coordinates.
        public var buttonRect: CGRect
        /// Bottom edge of the menu bar that holds the button.
        public var menuBarBottom: CGFloat

        public init(buttonRect: CGRect, menuBarBottom: CGFloat) {
            self.buttonRect = buttonRect
            self.menuBarBottom = menuBarBottom
        }
    }

    public struct Insets: Sendable, Equatable {
        public var top: CGFloat
        public var left: CGFloat
        public var bottom: CGFloat
        public var right: CGFloat

        public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }

        public var horizontal: CGFloat { left + right }
        public var vertical: CGFloat { top + bottom }
    }

    /// Menu bar height to assume when nothing better is known.
    public static let fallbackMenuBarHeight: CGFloat = 24
    /// No menu bar is taller than this; an item lower down isn't in one.
    public static let maxMenuBarHeight: CGFloat = 100

    /// An item can anchor the panel only while it sits in the menu bar at the
    /// top of a screen and isn't parked behind the camera housing, where macOS
    /// hides items that don't fit. On macOS 27 a new item's window also sits at
    /// the screen origin until the menu bar has placed it.
    public static func isUsable(_ anchor: Anchor, on screens: [ScreenGeometry]) -> Bool {
        guard anchor.buttonRect.width > 0, anchor.buttonRect.height > 0 else { return false }
        let mid = CGPoint(x: anchor.buttonRect.midX, y: anchor.buttonRect.midY)
        guard let screen = screens.first(where: { $0.frame.contains(mid) }) else { return false }
        let menuBarBand = (screen.frame.maxY - maxMenuBarHeight)...screen.frame.maxY
        guard menuBarBand.contains(mid.y), menuBarBand.contains(anchor.menuBarBottom) else { return false }
        return !(screen.notch?.contains(mid) ?? false)
    }

    /// The screen the panel should open on: the one holding the anchor, else
    /// the one under the pointer, else the first.
    public static func screenIndex(for anchor: Anchor?, pointer: CGPoint, in screens: [ScreenGeometry]) -> Int? {
        if let anchor {
            let mid = CGPoint(x: anchor.buttonRect.midX, y: anchor.buttonRect.midY)
            if let index = screens.firstIndex(where: { $0.frame.contains(mid) }) { return index }
        }
        if let index = screens.firstIndex(where: { $0.frame.contains(pointer) }) { return index }
        return screens.isEmpty ? nil : 0
    }

    /// Bottom of the menu bar on `screen`, from the anchor when there is one.
    public static func menuBarBottom(anchor: Anchor?, screen: ScreenGeometry) -> CGFloat {
        if let anchor {
            return min(anchor.menuBarBottom, screen.frame.maxY)
        }
        if screen.safeAreaTop > 0 {
            return screen.frame.maxY - screen.safeAreaTop
        }
        // An auto-hidden menu bar reserves nothing in the visible frame.
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        return screen.frame.maxY - (reserved > 0 ? reserved : fallbackMenuBarHeight)
    }

    /// The panel's own rect: centred under the status item, kept `margin`
    /// inside the visible frame, hanging `gap` below the menu bar, and snapped
    /// to the screen's pixel grid. Without an anchor it hugs the right edge,
    /// where status items live.
    public static func visualFrame(size: CGSize, anchor: Anchor?, screen: ScreenGeometry, gap: CGFloat, margin: CGFloat) -> CGRect {
        let top = menuBarBottom(anchor: anchor, screen: screen) - gap
        let minX = screen.visibleFrame.minX + margin
        let maxX = max(minX, screen.visibleFrame.maxX - margin - size.width)
        let preferredX = anchor.map { $0.buttonRect.midX - size.width / 2 } ?? maxX
        let x = min(max(preferredX, minX), maxX)
        let height = max(1, min(size.height, maxVisualHeight(anchor: anchor, screen: screen, gap: gap, margin: margin)))
        let rect = CGRect(x: x, y: top - height, width: size.width, height: height)
        return align(rect, scale: screen.backingScale)
    }

    /// The tallest the panel can be: from `gap` below the menu bar down to
    /// `margin` above the Dock or the bottom of the screen, whole pixels only.
    /// The popover lays itself out within this, so the panel is never cut off.
    public static func maxVisualHeight(anchor: Anchor?, screen: ScreenGeometry, gap: CGFloat, margin: CGFloat) -> CGFloat {
        let top = menuBarBottom(anchor: anchor, screen: screen) - gap
        let room = top - (screen.visibleFrame.minY + margin)
        let scale = max(screen.backingScale, 1)
        return max(1, (room * scale).rounded(.down) / scale)
    }

    /// The window rect for a panel rect: the panel plus its shadow margin.
    public static func windowFrame(visual: CGRect, insets: Insets) -> CGRect {
        CGRect(
            x: visual.minX - insets.left,
            y: visual.minY - insets.bottom,
            width: visual.width + insets.horizontal,
            height: visual.height + insets.vertical
        )
    }

    /// The panel rect inside a window of `size`, in window coordinates (origin bottom left).
    public static func visualRect(inWindowOf size: CGSize, insets: Insets) -> CGRect {
        CGRect(
            x: insets.left,
            y: insets.bottom,
            width: max(0, size.width - insets.horizontal),
            height: max(0, size.height - insets.vertical)
        )
    }

    /// Snaps to the pixel grid of a screen with this backing scale, keeping
    /// the top edge where it is, so one-point hairlines stay crisp.
    public static func align(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let s = max(scale, 1)
        let minX = (rect.minX * s).rounded() / s
        let maxY = (rect.maxY * s).rounded() / s
        let width = (rect.width * s).rounded() / s
        let height = (rect.height * s).rounded() / s
        return CGRect(x: minX, y: maxY - height, width: width, height: height)
    }
}
