import CoreGraphics
import Testing
@testable import LidlessCore

struct PanelFitTests {
    let design: CGFloat = 640

    @Test func `without a limit the panel is the design's height and never scrolls`() {
        var fit = PanelFit()
        fit.panelMeasured(height: 2000)
        #expect(fit.minimumHeight(design: design) == 640)
        #expect(!fit.listScrolls)
    }

    @Test func `the design's height holds when there is room for it`() {
        let fit = PanelFit(limit: 859)
        #expect(fit.minimumHeight(design: design) == 640)
    }

    @Test func `on a short screen the panel fills the room, footer pinned`() {
        var fit = PanelFit(limit: 530)
        #expect(fit.minimumHeight(design: design) == 530)
        fit.panelMeasured(height: 530)
        #expect(!fit.listScrolls)
    }

    @Test func `content taller than the room scrolls the list`() {
        var fit = PanelFit(limit: 530)
        fit.panelMeasured(height: 586)
        #expect(fit.listScrolls)
    }

    @Test func `rounding within a quarter point doesn't scroll`() {
        var fit = PanelFit(limit: 530)
        fit.panelMeasured(height: 530.2)
        #expect(!fit.listScrolls)
    }

    @Test func `a shorter panel doesn't stop the scrolling by itself`() {
        var fit = PanelFit(limit: 530)
        fit.panelMeasured(height: 586)
        fit.panelMeasured(height: 400)
        #expect(fit.listScrolls)
    }

    @Test func `the list keeps scrolling while its rows are cut off`() {
        var fit = PanelFit(limit: 530)
        fit.panelMeasured(height: 586)
        fit.listMeasured(visible: 145, content: 201)
        #expect(fit.listScrolls)
    }

    @Test func `the list stops scrolling once every row shows`() {
        var fit = PanelFit(limit: 530)
        fit.panelMeasured(height: 586)
        // A display was unplugged: the rows now fit the room they have.
        fit.listMeasured(visible: 101, content: 101)
        #expect(!fit.listScrolls)
        fit.panelMeasured(height: 530)
        #expect(!fit.listScrolls)
    }

    @Test func `list heights are ignored while it doesn't scroll`() {
        var fit = PanelFit(limit: 530)
        fit.listMeasured(visible: 50, content: 201)
        #expect(!fit.listScrolls)
    }

    @Test func `a smaller screen scrolls content that fit the last one`() {
        var fit = PanelFit(limit: 859)
        fit.panelMeasured(height: 686)
        #expect(!fit.listScrolls)
        fit.limit = 610
        #expect(fit.listScrolls)
    }

    @Test func `the height measured while every row shows counts once scrolling stops`() {
        var fit = PanelFit(limit: 440)
        fit.panelMeasured(height: 486)
        // A taller screen and more displays: the scrolling layout shows every row.
        fit.limit = 859
        fit.panelMeasured(height: 686)
        fit.listMeasured(visible: 301, content: 301)
        #expect(!fit.listScrolls)
        // Laid out in full the panel is just as tall, so no new height arrives.
        fit.limit = 660
        #expect(fit.listScrolls)
    }

    @Test func `removing the limit stops the scrolling`() {
        var fit = PanelFit(limit: 530)
        fit.panelMeasured(height: 586)
        fit.limit = nil
        #expect(!fit.listScrolls)
    }

    @Test func `a larger screen leaves scrolling to the list's own measurement`() {
        var fit = PanelFit(limit: 530)
        fit.panelMeasured(height: 586)
        fit.limit = 859
        #expect(fit.listScrolls)
        fit.listMeasured(visible: 201, content: 201)
        #expect(!fit.listScrolls)
    }
}
