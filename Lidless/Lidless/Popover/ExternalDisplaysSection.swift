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
                DisplayRow(
                    name: display.name,
                    subtitle: subtitle(resolutionClass: display.resolutionClass, role: display.role),
                    level: $brightness[levelFor: display.id],
                    showsDivider: display.id != firstID
                )
            }
        }
        .onSizeChange { contentHeight = $0.height }
    }

    private func subtitle(resolutionClass: String, role: DisplayDescriptor.Role) -> Text {
        switch role {
        case .main:
            Text("\(resolutionClass) · Main display", comment: "External display row subtitle; the variable is a resolution such as 5K or 1080p")
        case .extended:
            Text("\(resolutionClass) · Extended", comment: "External display row subtitle; the variable is a resolution such as 5K or 1080p")
        case .mirrored:
            Text("\(resolutionClass) · Mirrored", comment: "External display row subtitle; the variable is a resolution such as 5K or 1080p")
        }
    }
}
