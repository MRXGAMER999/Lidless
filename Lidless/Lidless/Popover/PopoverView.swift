import LidlessCore
import SwiftUI

/// The popover's content column (design-spec §5.2). Each section observes only
/// the stores it shows, so dragging a slider redraws just its card.
struct PopoverView: View {
    let model: AppModel
    let actions: PopoverActions
    /// The tallest the panel may be, border included; nil when nothing limits it.
    var maxHeight: CGFloat?

    @State private var fit = PanelFit()

    var body: some View {
        // CSS column with `gap: 10` and the footer at `margin-top: auto`: at
        // least 10 pt above the footer. One stack with a Spacer would put the
        // gap on both sides of it.
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                PopoverHeader(
                    system: model.system,
                    deskMode: model.deskMode,
                    brightness: model.brightness,
                    openSettings: actions.openSettings
                )
                DeskModeCard(deskMode: model.deskMode)
                BuiltInDisplayCard(deskMode: model.deskMode, brightness: model.brightness)
                ExternalDisplaysSection(system: model.system, brightness: model.externalBrightness, fit: $fit)
            }
            // A scrolling list takes all the room the footer leaves.
            .layoutPriority(fit.listScrolls ? 1 : 0)
            Spacer(minLength: Spacing.sectionGap)
            PopoverFooter(system: model.system, actions: actions)
        }
        .padding(Spacing.popoverPadding + Spacing.hairline)
        .frame(width: PopoverMetrics.width)
        // Every board is 640 tall with the footer pinned to the bottom; grow if
        // content needs more, and past the screen's room scroll the list instead.
        .frame(
            minHeight: fit.minimumHeight(design: PopoverMetrics.designHeight),
            maxHeight: fit.listScrolls ? fit.limit : nil
        )
        .onSizeChange { fit.panelMeasured(height: $0.height) }
        .onAppearAndChange(of: maxHeight) { fit.limit = $0 }
    }
}
