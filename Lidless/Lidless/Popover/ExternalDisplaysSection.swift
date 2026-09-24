import LidlessCore
import SwiftUI

/// "EXTERNAL DISPLAYS" and one row per connected monitor, or the empty state.
struct ExternalDisplaysSection: View {
    @ObservedObject var system: SystemStore
    let brightness: ExternalBrightnessStore
    @Binding var fit: PanelFit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: Text("EXTERNAL DISPLAYS", comment: "Section heading in the popover, uppercase by design"))
            if system.externals.isEmpty {
                EmptyDisplaysCard()
            } else {
                ExternalDisplayList(displays: system.externals, brightness: brightness, fit: $fit)
            }
        }
    }
}

private struct ExternalDisplayList: View {
    let displays: [DisplayDescriptor]
    /// Levels, and how each display is dimmed: shades get a hint, probing rows wait.
    @ObservedObject var brightness: ExternalBrightnessStore
    @Binding var fit: PanelFit
    /// The rows' full height, scrolling or not.
    @State private var contentHeight: CGFloat?

    var body: some View {
        Group {
            if fit.listScrolls, let contentHeight {
                ScrollView {
                    rows
                }
                // Never taller than the rows: room to spare goes above the footer, as usual.
                .frame(minHeight: 0, idealHeight: contentHeight, maxHeight: contentHeight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card - Spacing.hairline, style: .circular))
                .onSizeChange { fit.listMeasured(visible: $0.height, content: contentHeight) }
            } else {
                rows
            }
        }
        .glassCard(padding: EdgeInsets())
    }

    private var rows: some View {
        let firstID = displays.first?.id
        return VStack(spacing: 0) {
            ForEach(displays) { display in
                let method = brightness.method(for: display.id)
                let probing = method == .probing
                DisplayRow(
                    name: display.name,
                    subtitle: subtitle(resolutionClass: display.resolutionClass, role: display.role, method: method),
                    level: probing ? .constant(brightness.level(for: display.id)) : $brightness[levelFor: display.id],
                    showsDivider: display.id != firstID
                )
                // Until the probe picks DDC or a shade there's nothing to apply a level through.
                .disabled(probing)
                .opacity(probing ? 0.5 : 1)
                .help(method == .shade ? shadeHelp : Text(verbatim: ""))
            }
        }
        .onSizeChange { contentHeight = $0.height }
    }

    /// Tooltip on shaded rows (not designed).
    private var shadeHelp: Text {
        Text("This display doesn't take brightness commands, so Lidless darkens its picture instead.", comment: "Tooltip on an external display row whose brightness Lidless changes with a dark overlay, because the monitor ignores DDC brightness commands")
    }

    /// "{resolution} · {role}", or "{resolution} · Dimmed by Lidless" when the
    /// slider drives a shade: the row has no room for all three, and on a
    /// shade the method matters more than the role. DDC, native and not yet known: no hint.
    private func subtitle(resolutionClass: String, role: DisplayDescriptor.Role, method: ExternalBrightnessMethod?) -> Text {
        if method == .shade {
            return Text("\(resolutionClass) · Dimmed by Lidless", comment: "External display row subtitle when the monitor can't change its own brightness, so Lidless darkens the picture with an overlay; the variable is a resolution such as 5K or 1080p. Keep it short: it shares one line with the slider.")
        }
        return switch role {
        case .main:
            Text("\(resolutionClass) · Main display", comment: "External display row subtitle; the variable is a resolution such as 5K or 1080p")
        case .extended:
            Text("\(resolutionClass) · Extended", comment: "External display row subtitle; the variable is a resolution such as 5K or 1080p")
        case .mirrored:
            Text("\(resolutionClass) · Mirrored", comment: "External display row subtitle; the variable is a resolution such as 5K or 1080p")
        }
    }
}
