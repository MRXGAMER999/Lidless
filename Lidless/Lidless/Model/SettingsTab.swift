import SwiftUI

/// The three sections of the Settings window.
enum SettingsTab: String, CaseIterable, Identifiable {
    case deskMode
    case brightness
    case keysAndApp

    var id: Self { self }

    /// The name in the Settings window's section switcher.
    var title: Text {
        switch self {
        case .deskMode: Text("Desk Mode", comment: "Settings section switcher: the Desk Mode tab")
        case .brightness: Text("Brightness", comment: "Settings section switcher: the Brightness tab")
        case .keysAndApp: Text("Keys & App", comment: "Settings section switcher: the shortcuts and app tab")
        }
    }

    /// The glyph beside `title` (Settings2 boards).
    var glyph: LidlessGlyph {
        switch self {
        case .deskMode: .laptopSlash
        case .brightness: .sun
        case .keysAndApp: .keyboard
        }
    }

    /// The tab the popover's settings button opens: Brightness while Boost is
    /// on or Desk Mode can't be used (Popover-Boost links there), otherwise Desk Mode.
    static func forPopoverButton(boosted: Bool, deskModeAvailable: Bool) -> SettingsTab {
        boosted || !deskModeAvailable ? .brightness : .deskMode
    }
}

/// Things the popover asks the app to do. Closures are supplied by the app shell.
struct PopoverActions {
    var openSettings: (SettingsTab) -> Void = { _ in }
    var quit: () -> Void = {}
}
