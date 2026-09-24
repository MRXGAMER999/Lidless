import Combine
import Foundation
import LidlessCore

/// What the Mac looks like right now: lid, power, heat and connected displays.
///
/// A normal launch fills this from the live system through `SystemController`;
/// sample launches, previews and tests hold `SampleData` instead.
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

    // `@Published` emits even when assigned an equal value, so unchanged fields
    // are skipped and a repeated read doesn't redraw the popover.

    func update(lid: LidState, power: PowerSource, thermal: ThermalLevel) {
        if self.lid != lid { self.lid = lid }
        if self.power != power { self.power = power }
        if self.thermal != thermal { self.thermal = thermal }
    }

    func update(displays inventory: DisplayInventory) {
        if builtIn != inventory.builtIn { builtIn = inventory.builtIn }
        if externals != inventory.externals { externals = inventory.externals }
    }
}
