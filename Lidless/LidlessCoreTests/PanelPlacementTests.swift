import CoreGraphics
import Testing
@testable import LidlessCore

struct PanelPlacementTests {
    /// A 14-inch MacBook Pro at its default scaled resolution, notched, Dock at the bottom.
    let builtIn = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 875),
        safeAreaTop: 37,
        backingScale: 2,
        notch: CGRect(x: 662, y: 945, width: 188, height: 37)
    )
    let panel = CGSize(width: 360, height: 486)

    func anchor(midX: CGFloat) -> PanelPlacement.Anchor {
        PanelPlacement.Anchor(buttonRect: CGRect(x: midX - 16, y: 949, width: 32, height: 30), menuBarBottom: 945)
    }

    @Test func `centres under the status item and hangs below the menu bar`() {
        let frame = PanelPlacement.visualFrame(size: panel, anchor: anchor(midX: 1000), screen: builtIn, gap: 8, margin: 8)
        #expect(frame.midX == 1000)
        #expect(frame.maxY == 937)
        #expect(frame.size == panel)
    }

    @Test func `stays inside the right edge`() {
        let frame = PanelPlacement.visualFrame(size: panel, anchor: anchor(midX: 1490), screen: builtIn, gap: 8, margin: 8)
        #expect(frame.maxX == 1504)
    }

    @Test func `stays inside the left edge`() {
        let frame = PanelPlacement.visualFrame(size: panel, anchor: anchor(midX: 20), screen: builtIn, gap: 8, margin: 8)
        #expect(frame.minX == 8)
    }

    @Test func `without an anchor it sits at the right under the notched menu bar`() {
        let frame = PanelPlacement.visualFrame(size: panel, anchor: nil, screen: builtIn, gap: 8, margin: 8)
        #expect(frame.maxX == 1504)
        #expect(frame.maxY == builtIn.frame.maxY - builtIn.safeAreaTop - 8)
    }

    @Test func `without an anchor or notch it uses the reserved menu bar height`() {
        let external = ScreenGeometry(
            frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1055),
            backingScale: 1
        )
        #expect(PanelPlacement.menuBarBottom(anchor: nil, screen: external) == 1055)
    }

    @Test func `an auto-hidden menu bar falls back to the default height`() {
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(PanelPlacement.menuBarBottom(anchor: nil, screen: screen) == 1080 - PanelPlacement.fallbackMenuBarHeight)
    }

    @Test func `never taller than the room above the dock`() {
        let tall = CGSize(width: 360, height: 2000)
        let frame = PanelPlacement.visualFrame(size: tall, anchor: anchor(midX: 1000), screen: builtIn, gap: 8, margin: 8)
        #expect(frame.minY == 78)
        #expect(frame.maxY == 937)
    }

    @Test func `the height limit is the room between the menu bar and the dock`() {
        #expect(PanelPlacement.maxVisualHeight(anchor: anchor(midX: 1000), screen: builtIn, gap: 8, margin: 8) == 859)
        // A 13-inch MacBook Air at 1024×640, Dock at the bottom: the design's 640 pt panel doesn't fit.
        let air = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1024, height: 640), visibleFrame: CGRect(x: 0, y: 70, width: 1024, height: 546))
        #expect(PanelPlacement.maxVisualHeight(anchor: nil, screen: air, gap: 8, margin: 8) == 530)
    }

    @Test(arguments: [(CGFloat(2), CGFloat(530.5)), (CGFloat(1), CGFloat(530)), (CGFloat(3), CGFloat(530) + 2.0 / 3)])
    func `the height limit rounds down to whole pixels`(scale: CGFloat, expected: CGFloat) {
        let screen = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1024, height: 640),
            visibleFrame: CGRect(x: 0, y: 69.3, width: 1024, height: 546.7),
            backingScale: scale
        )
        let limit = PanelPlacement.maxVisualHeight(anchor: nil, screen: screen, gap: 8, margin: 8)
        #expect(abs(limit - expected) < 1e-9)
    }

    @Test func `a panel at the height limit isn't clamped`() {
        let limit = PanelPlacement.maxVisualHeight(anchor: anchor(midX: 1000), screen: builtIn, gap: 8, margin: 8)
        let fitting = PanelPlacement.visualFrame(size: CGSize(width: 360, height: limit), anchor: anchor(midX: 1000), screen: builtIn, gap: 8, margin: 8)
        #expect(fitting.height == limit)
        let taller = PanelPlacement.visualFrame(size: CGSize(width: 360, height: limit + 40), anchor: anchor(midX: 1000), screen: builtIn, gap: 8, margin: 8)
        #expect(taller.height == limit)
    }

    @Test func `an item behind the notch can't anchor the panel`() {
        let hidden = anchor(midX: 700)
        #expect(!PanelPlacement.isUsable(hidden, on: [builtIn]))
        #expect(PanelPlacement.isUsable(anchor(midX: 1000), on: [builtIn]))
    }

    @Test func `an item that isn't in the menu bar yet can't anchor the panel`() {
        // macOS 27 keeps a new item's window at the screen origin until the menu bar places it.
        let unplaced = PanelPlacement.Anchor(buttonRect: CGRect(x: 0, y: 0, width: 30, height: 24), menuBarBottom: 0)
        #expect(!PanelPlacement.isUsable(unplaced, on: [builtIn]))
        let wrongBottom = PanelPlacement.Anchor(buttonRect: CGRect(x: 984, y: 949, width: 32, height: 30), menuBarBottom: 0)
        #expect(!PanelPlacement.isUsable(wrongBottom, on: [builtIn]))
    }

    @Test func `an item on no screen can't anchor the panel`() {
        let offscreen = PanelPlacement.Anchor(buttonRect: CGRect(x: -500, y: -500, width: 30, height: 22), menuBarBottom: -500)
        #expect(!PanelPlacement.isUsable(offscreen, on: [builtIn]))
        let empty = PanelPlacement.Anchor(buttonRect: .zero, menuBarBottom: 945)
        #expect(!PanelPlacement.isUsable(empty, on: [builtIn]))
    }

    @Test func `picks the screen that holds the item, then the pointer`() {
        let external = ScreenGeometry(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1055))
        let screens = [builtIn, external]
        let onExternal = PanelPlacement.Anchor(buttonRect: CGRect(x: 3000, y: 1057, width: 30, height: 22), menuBarBottom: 1055)
        #expect(PanelPlacement.screenIndex(for: onExternal, pointer: .zero, in: screens) == 1)
        #expect(PanelPlacement.screenIndex(for: nil, pointer: CGPoint(x: 2000, y: 500), in: screens) == 1)
        #expect(PanelPlacement.screenIndex(for: nil, pointer: CGPoint(x: -9000, y: 0), in: screens) == 0)
        #expect(PanelPlacement.screenIndex(for: nil, pointer: .zero, in: []) == nil)
    }

    @Test func `snaps to half points on a Retina screen and whole points at 1x`() {
        let rect = CGRect(x: 10.3, y: 20.2, width: 100.26, height: 50.1)
        let retina = PanelPlacement.align(rect, scale: 2)
        #expect(retina.minX == 10.5)
        #expect(retina.maxY == 70.5)
        #expect(retina.width == 100.5)
        #expect(retina.height == 50)
        let standard = PanelPlacement.align(rect, scale: 1)
        #expect(standard.minX == 10)
        #expect(standard.maxY == 70)
    }

    @Test func `window frame and visual rect round-trip through the shadow insets`() {
        let insets = PanelPlacement.Insets(top: 8, left: 56, bottom: 84, right: 56)
        let visual = CGRect(x: 820, y: 451, width: 360, height: 486)
        let window = PanelPlacement.windowFrame(visual: visual, insets: insets)
        #expect(window == CGRect(x: 764, y: 367, width: 472, height: 578))
        #expect(window.maxY == visual.maxY + 8)
        let inside = PanelPlacement.visualRect(inWindowOf: window.size, insets: insets)
        #expect(inside == CGRect(x: 56, y: 84, width: 360, height: 486))
    }

    @Test func `notch lies between the two unobscured top areas`() {
        let left = CGRect(x: 0, y: 945, width: 662, height: 37)
        let right = CGRect(x: 850, y: 945, width: 662, height: 37)
        #expect(ScreenGeometry.notch(topLeftArea: left, topRightArea: right) == CGRect(x: 662, y: 945, width: 188, height: 37))
        #expect(ScreenGeometry.notch(topLeftArea: nil, topRightArea: right) == nil)
    }
}
