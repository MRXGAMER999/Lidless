import CoreGraphics

/// Fits the popover into the height its screen has room for.
///
/// The panel keeps the design's height when there is room, grows when its
/// content needs more, and never grows past `limit`: from there on the
/// display list scrolls. The view reports what it measures, the panel's
/// height and, while the list scrolls, the list's visible and full heights,
/// and lays itself out from `listScrolls`.
public struct PanelFit: Equatable, Sendable {
    /// The tallest the panel may be; nil when nothing limits it.
    public var limit: CGFloat? {
        didSet { update() }
    }

    public private(set) var listScrolls = false
    private var panelHeight: CGFloat = 0

    /// Layout rounding; heights this close count as equal.
    static let tolerance: CGFloat = 0.25

    public init(limit: CGFloat? = nil) {
        self.limit = limit
    }

    /// The design's height, or all the room there is when that is less.
    public func minimumHeight(design: CGFloat) -> CGFloat {
        min(design, limit ?? design)
    }

    /// The panel's height as laid out. A scrolling list that shows every row
    /// is laid out as it would be without scrolling, so this is the content's
    /// own height unless rows are cut off.
    public mutating func panelMeasured(height: CGFloat) {
        panelHeight = height
        update()
    }

    /// The list's visible and full heights while it scrolls.
    public mutating func listMeasured(visible: CGFloat, content: CGFloat) {
        guard listScrolls, content <= visible + Self.tolerance else { return }
        listScrolls = false
    }

    private mutating func update() {
        guard let limit else {
            listScrolls = false
            return
        }
        // Only the list's own measurement can tell when scrolling may stop.
        if !listScrolls, panelHeight > limit + Self.tolerance {
            listScrolls = true
        }
    }
}
