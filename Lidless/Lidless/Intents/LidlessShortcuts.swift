import AppIntents
import Foundation

/// App Shortcuts: Lidless's actions in Spotlight, Siri and the Shortcuts app
/// with no setup. Every phrase names the app (`\(.applicationName)`), or the
/// system drops it. Phrases are a contract with the user's muscle memory:
/// add new ones, don't rename shipped ones. At most 10 App Shortcuts.
///
/// Phrases are extracted into their own catalog, `AppShortcuts.xcstrings`
/// (not `Localizable.xcstrings`); localized phrases need that file. Short
/// titles are ordinary metadata strings with translator comments.
@available(macOS 13, *)
nonisolated struct LidlessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TurnDeskModeOnIntent(),
            phrases: [
                "Turn on Desk Mode in \(.applicationName)",
                "Start Desk Mode with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Desk Mode On", comment: "Short name of the App Shortcut that turns Desk Mode on, on its tile in Spotlight and the Shortcuts app; keep it short"),
            systemImageName: "laptopcomputer.slash"
        )
        AppShortcut(
            intent: TurnDeskModeOffIntent(),
            phrases: [
                "Turn off Desk Mode in \(.applicationName)",
                "Stop Desk Mode with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Desk Mode Off", comment: "Short name of the App Shortcut that turns Desk Mode off, on its tile in Spotlight and the Shortcuts app; keep it short"),
            systemImageName: "laptopcomputer"
        )
        AppShortcut(
            intent: ToggleDeskModeIntent(),
            phrases: [
                "Toggle Desk Mode in \(.applicationName)",
                "Switch Desk Mode with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Toggle Desk Mode", comment: "Short name of the App Shortcut that switches Desk Mode on or off, on its tile in Spotlight and the Shortcuts app; keep it short"),
            systemImageName: "switch.2"
        )
        AppShortcut(
            intent: TurnBuiltInDisplayBackOnIntent(),
            phrases: [
                "Turn the built-in display back on with \(.applicationName)",
                "Bring my screen back with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Screen Back On", comment: "Short name of the App Shortcut that brings the built-in screen back like the panic key, on its tile in Spotlight and the Shortcuts app; keep it short"),
            systemImageName: "lifepreserver"
        )
        AppShortcut(
            intent: SetBrightnessBoostIntent(),
            phrases: [
                "Turn Brightness Boost \(\.$isOn) in \(.applicationName)",
                "Boost my screen with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Brightness Boost", comment: "Short name of the App Shortcut that turns Brightness Boost (Lidless’s extra-brightness feature) on or off, on its tile in Spotlight and the Shortcuts app; keep it short"),
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: GetDeskModeStateIntent(),
            phrases: [
                "Is Desk Mode on in \(.applicationName)",
                "Get Desk Mode state in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Desk Mode State", comment: "Short name of the App Shortcut that tells whether Desk Mode is on, on its tile in Spotlight and the Shortcuts app; keep it short"),
            systemImageName: "info.circle"
        )
    }
}
