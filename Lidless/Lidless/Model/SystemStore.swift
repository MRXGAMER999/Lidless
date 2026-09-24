import Combine
import Foundation
import LidlessCore

/// What the Mac looks like right now: lid, power, heat and connected displays.
///
/// Phase 2 feeds this from IOKit and CoreGraphics; until then it holds sample data.
final class SystemStore: ObservableObject {
    @Published var lid: LidState
    @Published var power: PowerSource
    @Published var thermal: ThermalLevel
    /// The MacBook's own panel, if this Mac has one.
    @Published var builtIn: DisplayDescriptor?
    /// Real external displays, main display first. Virtual displays are left out.
    @Published var externals: [DisplayDescriptor]

    init(
        lid: LidState = .unknown,
        power: PowerSource = .unknown,
        thermal: ThermalLevel = .nominal,
        builtIn: DisplayDescriptor? = nil,
        externals: [DisplayDescriptor] = []
    ) {
        self.lid = lid
        self.power = power
        self.thermal = thermal
        self.builtIn = builtIn
        self.externals = externals
    }
}
