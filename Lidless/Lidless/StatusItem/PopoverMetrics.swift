import AppKit
import LidlessCore
import SwiftUI

/// Geometry of the menu bar popover (design-spec §5.2, Main.dc.html).
nonisolated enum PopoverMetrics {
    /// Panel width, border included.
    static let width: CGFloat = 360
    /// Panel height on every popover board. Real content may be shorter.
    static let designHeight: CGFloat = 640
    static let cornerRadius: CGFloat = 22
    /// Space between the bottom of the menu bar and the top of the panel.
    static let gapBelowMenuBar: CGFloat = 8
    /// The panel never comes closer than this to the edges of the visible screen.
    static let screenMargin: CGFloat = 8

    /// Transparent margin around the panel that holds its drop shadow
    /// (CSS `0 20px 50px`). The top margin is the gap under the menu bar, so the
    /// window starts exactly at the menu bar's bottom edge and never covers it.
    ///
    /// The window frame is the visible panel rect expanded by these insets.
    /// `PopoverRoot` pads itself by them and draws the shadow inside them.
    static let shadowInsets = NSEdgeInsets(top: gapBelowMenuBar, left: 56, bottom: 84, right: 56)

    /// `shadowInsets` for SwiftUI's `.padding(_:)`.
    static let shadowPadding = EdgeInsets(
        top: shadowInsets.top,
        leading: shadowInsets.left,
        bottom: shadowInsets.bottom,
        trailing: shadowInsets.right
    )

    static let placementInsets = PanelPlacement.Insets(
        top: shadowInsets.top,
        left: shadowInsets.left,
        bottom: shadowInsets.bottom,
        right: shadowInsets.right
    )

    /// Window size for a panel of the design's size, used until SwiftUI reports its own.
    static let defaultWindowSize = CGSize(
        width: width + placementInsets.horizontal,
        height: designHeight + placementInsets.vertical
    )
}
