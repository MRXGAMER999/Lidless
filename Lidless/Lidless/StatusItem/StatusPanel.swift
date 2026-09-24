import AppKit
import LidlessCore
import SwiftUI

/// The window behind the menu bar popover: borderless, transparent and
/// non-activating, so it can take keyboard focus without making Lidless the
/// active app.
final class StatusPanel: NSPanel {
    init() {
        // `.nonactivatingPanel` only takes effect when it is in the initial style mask.
        super.init(
            contentRect: NSRect(origin: .zero, size: PopoverMetrics.defaultWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Lidless is usually not the active app; the controller closes the panel itself.
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        // SwiftUI draws the design's shadow inside the transparent margin.
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        autorecalculatesKeyViewLoop = true
        setAccessibilityTitle(String(localized: "Lidless", comment: "Accessibility title of the menu bar popover"))
    }

    /// ⌘W and Window › Close land here; the controller owns every close.
    var closeRequest: (() -> Void)?

    // Borderless windows refuse key status by default.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Without a close button NSWindow disables performClose(_:) and beeps, but
    // ⌘W should close the popover like it closes an NSPopover.
    override func performClose(_ sender: Any?) {
        guard let closeRequest else { return super.performClose(sender) }
        closeRequest()
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performClose(_:)), closeRequest != nil { return true }
        return super.validateMenuItem(menuItem)
    }
}

/// Content view of the panel: an optional material backdrop exactly behind
/// the visible panel rect, with the SwiftUI hosting view on top filling the window.
final class StatusPanelContentView: NSView {
    private let backdrop: NSView?

    init(hostingView: NSView) {
        if #available(macOS 26, *) {
            // The SwiftUI root draws Liquid Glass itself.
            backdrop = nil
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            // Stay vibrant while Lidless is inactive, which is most of the time.
            effect.state = .active
            effect.maskImage = PanelMask.roundedRect(radius: PopoverMetrics.cornerRadius)
            backdrop = effect
        }
        super.init(frame: NSRect(origin: .zero, size: PopoverMetrics.defaultWindowSize))
        if let backdrop {
            addSubview(backdrop)
        }
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        layoutBackdrop()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutBackdrop()
    }

    private func layoutBackdrop() {
        backdrop?.frame = PanelPlacement.visualRect(inWindowOf: bounds.size, insets: PopoverMetrics.placementInsets)
    }
}

/// Lets the first click on a control land even if the panel isn't key yet.
final class StatusPanelHostingView: NSHostingView<StatusPanelRoot> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum PanelMask {
    /// Stretchable rounded-rect mask for the material backdrop. Built in a
    /// nonisolated function so the drawing handler isn't main-actor isolated:
    /// AppKit may render it off the main thread, which would trap.
    nonisolated static func roundedRect(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - SwiftUI side

/// Receives the popover's size from SwiftUI.
final class PanelSizeSink {
    var onChange: ((CGSize) -> Void)?

    func report(_ size: CGSize) {
        onChange?(size)
    }
}

/// Root of the panel's hosting view. Measures `PopoverRoot` at its ideal size
/// (which includes the shadow margin) and reports it, so the window can follow
/// the content with its top edge pinned under the menu bar.
struct StatusPanelRoot: View {
    let model: AppModel
    let actions: PopoverActions
    let sizeSink: PanelSizeSink
    /// The tallest the visible panel may be on the screen it opens on.
    var maxPanelHeight: CGFloat?

    var body: some View {
        PopoverRoot(model: model, actions: actions, maxHeight: maxPanelHeight)
            .fixedSize()
            .reportingSize(to: sizeSink)
            // Zero minimum so the hosting view never forces the window bigger
            // than the controller made it.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// Sends this view's size to `sink` once it is laid out and whenever it changes.
    func reportingSize(to sink: PanelSizeSink) -> some View {
        onSizeChange { sink.report($0) }
    }
}
