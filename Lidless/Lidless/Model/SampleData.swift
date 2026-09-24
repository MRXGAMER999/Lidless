import Foundation
import LidlessCore

/// Sample states matching the design canvas, for previews and screenshot mode.
enum SampleData {
    static let builtIn = DisplayDescriptor(
        id: "sample-built-in",
        displayID: 1,
        name: "Built-in Retina Display",
        isBuiltIn: true,
        pixelWidth: 3024,
        pixelHeight: 1964,
        refreshRate: 120,
        role: .extended,
        supportsBoost: true,
        brightnessControl: .native
    )

    static let studioMonitor = DisplayDescriptor(
        id: "sample-lg",
        displayID: 2,
        name: "LG UltraFine 27",
        isBuiltIn: false,
        pixelWidth: 5120,
        pixelHeight: 2880,
        refreshRate: 60,
        role: .main,
        brightnessControl: .native
    )

    static let officeMonitor = DisplayDescriptor(
        id: "sample-dell",
        displayID: 3,
        name: "Dell U2723QE",
        isBuiltIn: false,
        pixelWidth: 3840,
        pixelHeight: 2160,
        refreshRate: 60,
        role: .extended,
        brightnessControl: .ddc
    )

    /// "Popover · Default": lid open, two monitors, on power, Desk Mode off, 70%.
    static func deskSetup() -> AppModel {
        AppModel(
            system: SystemStore(lid: .open, power: .adapter, thermal: .nominal, builtIn: builtIn, externals: [studioMonitor, officeMonitor]),
            deskMode: DeskModeStore(state: .off),
            brightness: BrightnessStore(position: 70, scale: .init(normalMaxNits: 500, ceilingNits: 1000)),
            externalBrightness: ExternalBrightnessStore(levels: [studioMonitor.id: 0.8, officeMonitor.id: 0.55])
        )
    }

    /// "Popover · On the go, Boost on": no monitors, on battery, boosted to 160%.
    static func onTheGo() -> AppModel {
        AppModel(
            system: SystemStore(lid: .open, power: .battery(percent: 64), thermal: .fair, builtIn: builtIn, externals: []),
            deskMode: DeskModeStore(state: .unavailable(.needsDisplay)),
            brightness: BrightnessStore(position: 130, scale: .init(normalMaxNits: 500, ceilingNits: 1000))
        )
    }

    /// "Popover · Desk Mode on": built-in off, turned on automatically at 9:14 AM.
    static func deskModeOn() -> AppModel {
        var components = DateComponents()
        components.hour = 9
        components.minute = 14
        let since = Calendar.current.date(from: components) ?? .now
        var external = officeMonitor
        external.role = .extended
        return AppModel(
            system: SystemStore(lid: .open, power: .adapter, thermal: .nominal, builtIn: builtIn, externals: [studioMonitor, external]),
            deskMode: DeskModeStore(state: .on(since: since, trigger: .automatic(displayName: studioMonitor.name))),
            brightness: BrightnessStore(position: 70, scale: .init(normalMaxNits: 500, ceilingNits: 1000)),
            externalBrightness: ExternalBrightnessStore(levels: [studioMonitor.id: 0.8, officeMonitor.id: 0.55])
        )
    }
}
