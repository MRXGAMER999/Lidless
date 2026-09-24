import AppIntents
import Foundation
import LidlessCore

/// Why an intent couldn't do what it was asked. Siri and Shortcuts show the
/// message and stop the shortcut; only `CustomLocalizedStringResourceConvertible`
/// errors surface a real message (a plain `Error` reads as a generic failure).
@available(macOS 13, *)
nonisolated enum LidlessIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The bridge isn't installed: safe mode, or the launch didn't finish in time.
    case notReady
    case deskModeUnavailable(DeskModeState.UnavailableReason)
    case deskModeFailed
    case deskModeBusy
    case boostNotAllowed
    case boostUnsupported

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady:
            LocalizedStringResource("Lidless isn't ready yet. Try again in a moment.", comment: "Shortcuts/Siri error: the app is still starting (or started in safe mode) and can't run the action")
        case .deskModeUnavailable(.needsDisplay):
            LocalizedStringResource("Desk Mode needs an external display. Plug in a monitor and try again.", comment: "Shortcuts/Siri error when turning Desk Mode on with no external display connected")
        case .deskModeUnavailable(.lidClosed):
            LocalizedStringResource("The lid is closed. Open it and Lidless can turn the built-in screen off.", comment: "Shortcuts/Siri error when turning Desk Mode on with the MacBook lid closed")
        case .deskModeUnavailable(.unsupportedMac):
            LocalizedStringResource("This Mac can't bring its screen back reliably, so Lidless leaves it on.", comment: "Shortcuts/Siri error when turning Desk Mode on, on a Mac that can't use Desk Mode (same text as the popover)")
        case .deskModeUnavailable(.unsupportedSystem):
            LocalizedStringResource("This version of macOS can't turn the screen off safely.", comment: "Shortcuts/Siri error when turning Desk Mode on, on a macOS version that can't use Desk Mode (same text as the popover)")
        case .deskModeFailed:
            LocalizedStringResource("Lidless couldn't turn the built-in screen off. Try again in a moment.", comment: "Shortcuts/Siri error: Desk Mode was asked to turn on but the built-in screen stayed on")
        case .deskModeBusy:
            LocalizedStringResource("The built-in screen is still coming back. Try again in a moment.", comment: "Shortcuts/Siri error: Desk Mode was asked to turn on while the built-in screen is being turned back on")
        case .boostNotAllowed:
            LocalizedStringResource("Brightness Boost is turned off in Lidless Settings.", comment: "Shortcuts/Siri error: “Boost allowed” is off in Settings › Brightness, so Boost can't be turned on")
        case .boostUnsupported:
            LocalizedStringResource("This screen can't boost right now.", comment: "Shortcuts/Siri error: the built-in screen has no extra brightness to give, for example because a fixed reference preset is selected in System Settings › Displays (same text as the popover)")
        }
    }
}

@available(macOS 13, *)
extension AppIntentBridge {
    /// The installed bridge, or `notReady` when the app delegate never installed one.
    static func forIntent() async throws -> AppIntentBridge {
        guard let bridge = await current() else { throw LidlessIntentError.notReady }
        return bridge
    }
}
