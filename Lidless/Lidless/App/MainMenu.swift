import AppKit

/// The main menu, built in code. A menu bar app only shows it while one of its
/// windows is active, but it is what makes ⌘C, ⌘V, ⌘W and friends work there.
enum MainMenu {
    /// - Parameters:
    ///   - target: Receives `settingsAction` and, in debug builds, `showOnboardingAction`.
    ///   - showOnboardingAction: Debug › Show Onboarding (debug builds only).
    static func make(target: AnyObject, settingsAction: Selector, showOnboardingAction: Selector) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenuItem(appMenu(settingsTarget: target, settingsAction: settingsAction)))
        main.addItem(submenuItem(editMenu()))
        #if DEBUG
        main.addItem(submenuItem(debugMenu(target: target, showOnboardingAction: showOnboardingAction)))
        #endif
        let window = windowMenu()
        main.addItem(submenuItem(window))
        NSApp.windowsMenu = window
        return main
    }

    private static func appMenu(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let menu = NSMenu(title: "Lidless")
        menu.addItem(
            withTitle: String(localized: "About Lidless", comment: "App menu item"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        let settingsTitle: String
        if #available(macOS 13, *) {
            settingsTitle = String(localized: "Settings…", comment: "App menu item that opens the Settings window")
        } else {
            // macOS 12 still calls them Preferences.
            settingsTitle = String(localized: "Preferences…", comment: "App menu item that opens the Settings window, on macOS 12 (which calls settings Preferences)")
        }
        let settings = menu.addItem(
            withTitle: settingsTitle,
            action: settingsAction,
            keyEquivalent: ","
        )
        settings.target = settingsTarget
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Hide Lidless", comment: "App menu item"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit Lidless", comment: "App menu item"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit", comment: "Main menu title"))
        // undo:/redo: are responder-chain actions with no Swift-visible declaration.
        menu.addItem(withTitle: String(localized: "Undo", comment: "Edit menu item"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: String(localized: "Redo", comment: "Edit menu item"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Cut", comment: "Edit menu item"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: String(localized: "Copy", comment: "Edit menu item"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: String(localized: "Paste", comment: "Edit menu item"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: String(localized: "Select All", comment: "Edit menu item"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    #if DEBUG
    /// Developer-only, so its titles aren't localised.
    private static func debugMenu(target: AnyObject, showOnboardingAction: Selector) -> NSMenu {
        let menu = NSMenu(title: "Debug")
        let onboarding = menu.addItem(withTitle: "Show Onboarding", action: showOnboardingAction, keyEquivalent: "")
        onboarding.target = target
        return menu
    }
    #endif

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Window", comment: "Main menu title"))
        menu.addItem(withTitle: String(localized: "Minimize", comment: "Window menu item"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: String(localized: "Close", comment: "Window menu item"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
