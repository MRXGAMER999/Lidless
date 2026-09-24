import Foundation
import LidlessCore

/// Owns the app's stores. Created once by the app delegate and passed down to views,
/// so no view ever creates a store itself.
final class AppModel {
    let system: SystemStore
    let deskMode: DeskModeStore
    let brightness: BrightnessStore
    let externalBrightness: ExternalBrightnessStore
    /// What Boost is doing (engaging, on, paused), fed by `BoostController`.
    let boostStatus: BoostStatusStore
    let preferences: PreferencesStore

    init(
        system: SystemStore = SystemStore(),
        deskMode: DeskModeStore = DeskModeStore(),
        brightness: BrightnessStore = BrightnessStore(),
        externalBrightness: ExternalBrightnessStore = ExternalBrightnessStore(),
        boostStatus: BoostStatusStore = BoostStatusStore(),
        preferences: PreferencesStore = PreferencesStore()
    ) {
        self.system = system
        self.deskMode = deskMode
        self.brightness = brightness
        self.externalBrightness = externalBrightness
        self.boostStatus = boostStatus
        self.preferences = preferences
    }
}
