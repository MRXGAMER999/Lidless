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

    /// How the sample monitors are dimmed: neither needs a hint.
    static let externalMethods: [String: ExternalBrightnessMethod] = [
        studioMonitor.id: .native,
        officeMonitor.id: .ddc(maximum: 100),
    ]

    /// "Popover · Default": lid open, two monitors, on power, Desk Mode off, 70%.
    static func deskSetup() -> AppModel {
        AppModel(
            system: SystemStore(lid: .open, power: .adapter, thermal: .nominal, builtIn: builtIn, externals: [studioMonitor, officeMonitor]),
            deskMode: DeskModeStore(state: .off),
            brightness: BrightnessStore(position: 70, scale: .init(normalMaxNits: 500, ceilingNits: 1000)),
            externalBrightness: ExternalBrightnessStore(levels: [studioMonitor.id: 0.8, officeMonitor.id: 0.55], methods: externalMethods)
        )
    }

    /// "Popover · On the go, Boost on": no monitors, on battery, boosted to 160%.
    static func onTheGo() -> AppModel {
        AppModel(
            system: SystemStore(lid: .open, power: .battery(percent: 64), thermal: .fair, builtIn: builtIn, externals: []),
            deskMode: DeskModeStore(state: .unavailable(.needsDisplay)),
            brightness: BrightnessStore(position: 130, scale: .init(normalMaxNits: 500, ceilingNits: 1000)),
            boostStatus: BoostStatusStore(status: .on(factor: 1.6))
        )
    }

    /// "On the go" while Boost waits for macOS to give the screen headroom.
    static func boostEngaging() -> AppModel {
        let model = onTheGo()
        model.boostStatus.update(.engaging)
        return model
    }

    /// "On the go" with Boost paused by a guard rail. The thermal chip shows
    /// the matching heat level for `.hot`.
    static func boostPaused(_ block: BoostBlock = .hot) -> AppModel {
        let model = onTheGo()
        model.boostStatus.update(.blocked(block))
        if block == .hot { model.system.thermal = .serious }
        return model
    }

    /// "On the go" after macOS gave no headroom three times.
    static func boostUnavailable() -> AppModel {
        let model = onTheGo()
        model.boostStatus.update(.unavailable)
        return model
    }

    /// The target Mac's LG ULTRAGEAR over HDMI (no DDC), dimmed by a shade,
    /// with a second monitor still being probed. Critical heat for the chip.
    static func shadedMonitors() -> AppModel {
        let ultragear = DisplayDescriptor(
            id: "sample-ultragear",
            displayID: 4,
            name: "LG ULTRAGEAR",
            isBuiltIn: false,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshRate: 144,
            role: .main,
            brightnessControl: .ddc
        )
        return AppModel(
            system: SystemStore(lid: .open, power: .adapter, thermal: .critical, builtIn: builtIn, externals: [ultragear, officeMonitor]),
            deskMode: DeskModeStore(state: .off),
            brightness: BrightnessStore(position: 70, scale: .init(normalMaxNits: 500, ceilingNits: 1000)),
            externalBrightness: ExternalBrightnessStore(
                levels: [ultragear.id: 0.7, officeMonitor.id: 0.55],
                methods: [ultragear.id: .shade, officeMonitor.id: .probing]
            )
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
            externalBrightness: ExternalBrightnessStore(levels: [studioMonitor.id: 0.8, officeMonitor.id: 0.55], methods: externalMethods)
        )
    }
}
