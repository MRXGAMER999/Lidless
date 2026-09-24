import Foundation
import LidlessCore

/// Owns the app's stores. Created once by the app delegate and passed down to views,
/// so no view ever creates a store itself.
final class AppModel {
    let system: SystemStore
    let deskMode: DeskModeStore
    let brightness: BrightnessStore
    let externalBrightness: ExternalBrightnessStore
    let preferences: PreferencesStore

    init(
        system: SystemStore = SystemStore(),
        deskMode: DeskModeStore = DeskModeStore(),
        brightness: BrightnessStore = BrightnessStore(),
        externalBrightness: ExternalBrightnessStore = ExternalBrightnessStore(),
        preferences: PreferencesStore = PreferencesStore()
    ) {
        self.system = system
        self.deskMode = deskMode
        self.brightness = brightness
        self.externalBrightness = externalBrightness
        self.preferences = preferences
    }
}
