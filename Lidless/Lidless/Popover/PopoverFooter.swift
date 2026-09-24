import LidlessCore
import SwiftUI

/// Heat status on the left, Settings and Quit on the right.
struct PopoverFooter: View {
    let system: SystemStore
    let actions: PopoverActions

    /// macOS 12 still calls the window Preferences (as the app menu does).
    private static var settingsTitle: Text {
        if #available(macOS 13, *) {
            Text("Settings…", comment: "Popover footer button that opens the Settings window")
        } else {
            Text("Preferences…", comment: "Popover footer button that opens the Preferences window (macOS 12 name for Settings)")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ThermalStatusChip(system: system)
            Spacer(minLength: 0)
            SplitCapsule(
                leadingTitle: Self.settingsTitle,
                leadingAction: { actions.openSettings(.deskMode) },
                trailingTitle: Text("Quit", comment: "Popover footer button that quits Lidless"),
                trailingAction: { actions.quit() }
            )
        }
    }
}

private struct ThermalStatusChip: View {
    @ObservedObject var system: SystemStore

    var body: some View {
        StatusChip(label: label, dotColor: dotColor)
    }

    private var label: Text {
        switch system.thermal {
        case .nominal: Text("Thermals: Normal", comment: "Popover footer heat status")
        case .fair: Text("Thermals: Fair", comment: "Popover footer heat status")
        case .serious: Text("Thermals: Serious", comment: "Popover footer heat status")
        case .critical: Text("Thermals: Critical", comment: "Popover footer heat status")
        }
    }

    private var dotColor: Color {
        switch system.thermal {
        case .nominal: Palette.thermalNominal
        case .fair: Palette.thermalFair
        case .serious: Palette.thermalSerious
        case .critical: Palette.thermalCritical
        }
    }
}
