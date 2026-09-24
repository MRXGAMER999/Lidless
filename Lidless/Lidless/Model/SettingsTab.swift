/// The three sections of the Settings window.
enum SettingsTab: String, CaseIterable, Identifiable {
    case deskMode
    case brightness
    case keysAndApp

    var id: Self { self }

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
