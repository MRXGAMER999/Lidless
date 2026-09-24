#if DEBUG
import LidlessCore
import SwiftUI

/// The canvas's page colour and blobs behind the popover.
private enum CanvasBackdrop {
    case main
    case boost
    case deskDark
}

/// A 420×720 design board: the canvas's backdrop behind the popover, so the
/// glass reads the way it does on the boards. Previews only; the real panel
/// shows whatever is behind it on screen.
private struct CanvasBoard<Content: View>: View {
    let backdrop: CanvasBackdrop
    /// 2 matches the 2x design renders in design/renders for geometry,
    /// colour and material checks. The preview host draws at 1x, so text and
    /// glyphs are rasterized at 1x and then scaled (edges ramp over 3–4 px);
    /// judge stroke weight on the 1x boards against a box-downsampled render.
    var scale: CGFloat = 1
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasBackdropView(backdrop: backdrop)
            // The boards put the panel at (36, 38); PopoverRoot adds the shadow margin around it.
            content
                .fixedSize()
                .offset(x: 36 - PopoverMetrics.shadowPadding.leading, y: 38 - PopoverMetrics.shadowPadding.top)
        }
        .frame(width: 420, height: 720, alignment: .topLeading)
        .clipped()
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 420 * scale, height: 720 * scale, alignment: .topLeading)
    }
}

private struct CanvasBackdropView: View {
    let backdrop: CanvasBackdrop

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch backdrop {
            case .main:
                Color.hex(0xEFE7DA)
                CanvasBlob(x: -70, y: 90, diameter: 300, hex: 0xFFC94D)
                CanvasBlob(x: 240, y: 320, diameter: 260, hex: 0x7F9BE0)
                CanvasBlob(x: 30, y: 560, diameter: 230, hex: 0xFF9470)
            case .boost:
                Color.hex(0xF2E6DA)
                CanvasBlob(x: 180, y: 60, diameter: 320, hex: 0xFFB347)
                CanvasBlob(x: -90, y: 340, diameter: 280, hex: 0xFF6F61)
                CanvasBlob(x: 220, y: 540, diameter: 240, hex: 0x3FB8AF)
            case .deskDark:
                Color.hex(0x0F1224)
                CanvasBlob(x: -60, y: 110, diameter: 300, hex: 0x6B3FD1)
                CanvasBlob(x: 250, y: 300, diameter: 260, hex: 0x1F6FB8)
                CanvasBlob(x: 40, y: 560, diameter: 230, hex: 0xB0406E)
            }
        }
    }
}

private struct CanvasBlob: View {
    let x: CGFloat
    let y: CGFloat
    let diameter: CGFloat
    let hex: UInt32

    var body: some View {
        Circle()
            .fill(Color.hex(hex))
            .frame(width: diameter, height: diameter)
            .offset(x: x, y: y)
    }
}

private extension Color {
    // A factory, not a delegating init: the preview thunk wraps expressions,
    // and `self.init` can't be nested in one.
    static func hex(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

#Preview("Desk setup") {
    CanvasBoard(backdrop: .main) {
        PopoverRoot(model: SampleData.deskSetup(), actions: PopoverActions())
    }
    .preferredColorScheme(.light)
}

#Preview("On the go, Boost on") {
    CanvasBoard(backdrop: .boost) {
        PopoverRoot(model: SampleData.onTheGo(), actions: PopoverActions())
    }
    .preferredColorScheme(.light)
}

#Preview("Desk Mode on, dark") {
    CanvasBoard(backdrop: .deskDark) {
        PopoverRoot(model: SampleData.deskModeOn(), actions: PopoverActions())
    }
    .preferredColorScheme(.dark)
}

#Preview("Desk setup @2x") {
    CanvasBoard(backdrop: .main, scale: 2) {
        PopoverRoot(model: SampleData.deskSetup(), actions: PopoverActions())
    }
    .preferredColorScheme(.light)
}

#Preview("On the go, Boost on @2x") {
    CanvasBoard(backdrop: .boost, scale: 2) {
        PopoverRoot(model: SampleData.onTheGo(), actions: PopoverActions())
    }
    .preferredColorScheme(.light)
}

#Preview("Desk Mode on, dark @2x") {
    CanvasBoard(backdrop: .deskDark, scale: 2) {
        PopoverRoot(model: SampleData.deskModeOn(), actions: PopoverActions())
    }
    .preferredColorScheme(.dark)
}

// Live Boost and external-brightness states (not designed; built on the
// Boost board): the callout's one-line stand-ins, heat chips past Fair, and
// external rows dimmed by a shade or still being probed.

#Preview("Boost engaging") {
    CanvasBoard(backdrop: .boost) {
        PopoverRoot(model: SampleData.boostEngaging(), actions: PopoverActions())
    }
    .preferredColorScheme(.light)
}

#Preview("Boost paused, hot") {
    CanvasBoard(backdrop: .boost) {
        PopoverRoot(model: SampleData.boostPaused(.hot), actions: PopoverActions())
    }
    .preferredColorScheme(.light)
}

#Preview("Boost paused, Low Power Mode") {
    CanvasBoard(backdrop: .boost) {
        PopoverRoot(model: SampleData.boostPaused(.lowPower), actions: PopoverActions())
    }
    .preferredColorScheme(.light)
}

#Preview("Boost unavailable") {
    CanvasBoard(backdrop: .boost) {
        PopoverRoot(model: SampleData.boostUnavailable(), actions: PopoverActions())
    }
    .preferredColorScheme(.light)
}

#Preview("Shade and probing rows, critical heat") {
    CanvasBoard(backdrop: .main) {
        PopoverRoot(model: SampleData.shadedMonitors(), actions: PopoverActions())
    }
    .preferredColorScheme(.light)
}

/// "Desk setup" with four monitors, on a screen with room for a 520 pt panel
/// (a 1024×640 display with the Dock at the bottom): the list scrolls.
#Preview("Short screen @2x") {
    CanvasBoard(backdrop: .main, scale: 2) {
        PopoverRoot(model: fourMonitorDesk(), actions: PopoverActions(), maxHeight: 520)
    }
    .preferredColorScheme(.light)
}

private func fourMonitorDesk() -> AppModel {
    let model = SampleData.deskSetup()
    model.system.externals += [
        DisplayDescriptor(
            id: "sample-studio", displayID: 4, name: "Studio Display", isBuiltIn: false,
            pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60, role: .extended, brightnessControl: .native
        ),
        DisplayDescriptor(
            id: "sample-benq", displayID: 5, name: "BenQ PD2705U", isBuiltIn: false,
            pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60, role: .extended, brightnessControl: .ddc
        ),
    ]
    model.externalBrightness.levels["sample-studio"] = 0.65
    model.externalBrightness.levels["sample-benq"] = 0.4
    return model
}
#endif
