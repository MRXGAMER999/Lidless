import AppIntents
import Foundation
import LidlessCore

// Desk Mode for Shortcuts and Siri. Each intent runs in the app with no UI and
// hops to the main actor to call `AppIntentBridge`, which takes the popover's
// and the keys' paths, so the safety net (sidecar, keep-or-revert prompt, panic
// key) covers these exactly as it covers a click.
//
// The type names are a contract with saved shortcuts: never rename them.
// Metadata strings (titles, descriptions) are `LocalizedStringResource`
// initializers with literal arguments only (key and translator comment), so the
// build-time App Intents extractor and the string catalog still read them.
// Never build one from a variable.

@available(macOS 13, *)
nonisolated struct TurnDeskModeOnIntent: AppIntent {
    static let title = LocalizedStringResource("Turn Desk Mode On", comment: "Name of the Shortcuts/Siri action that turns Desk Mode on (the built-in screen goes off, external displays stay on)")
    static var description: IntentDescription? {
        IntentDescription(LocalizedStringResource("Turns the built-in screen off while your external displays stay on. The lid stays open for cooling.", comment: "Description of the “Turn Desk Mode On” action in the Shortcuts app"))
    }

    static let openAppWhenRun = false
    @available(macOS 26, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await AppIntentBridge.forIntent().turnDeskMode(on: true)
        return .result(dialog: try outcome.switchDialog())
    }
}

@available(macOS 13, *)
nonisolated struct TurnDeskModeOffIntent: AppIntent {
    static let title = LocalizedStringResource("Turn Desk Mode Off", comment: "Name of the Shortcuts/Siri action that turns Desk Mode off (the built-in screen comes back)")
    static var description: IntentDescription? {
        IntentDescription(LocalizedStringResource("Turns the built-in screen back on.", comment: "Description of the “Turn Desk Mode Off” action in the Shortcuts app"))
    }

    static let openAppWhenRun = false
    @available(macOS 26, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await AppIntentBridge.forIntent().turnDeskMode(on: false)
        return .result(dialog: try outcome.switchDialog())
    }
}

@available(macOS 13, *)
nonisolated struct ToggleDeskModeIntent: AppIntent {
    static let title = LocalizedStringResource("Toggle Desk Mode", comment: "Name of the Shortcuts/Siri action that turns Desk Mode on if it is off, and off if it is on")
    static var description: IntentDescription? {
        IntentDescription(LocalizedStringResource("Turns Desk Mode on if it's off, and off if it's on. Returns whether Desk Mode is now on.", comment: "Description of the “Toggle Desk Mode” action in the Shortcuts app; the action outputs true or false"))
    }

    static let openAppWhenRun = false
    @available(macOS 26, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let bridge = try await AppIntentBridge.forIntent()
        let outcome = await bridge.toggleDeskMode()
        let dialog = try outcome.switchDialog()
        return .result(value: bridge.deskModeState().isOn, dialog: dialog)
    }
}

/// The panic key as an action. Never refused and needs no unlock: it only
/// ever brings the built-in screen back.
@available(macOS 13, *)
nonisolated struct TurnBuiltInDisplayBackOnIntent: AppIntent {
    static let title = LocalizedStringResource("Turn the Built-in Display Back On", comment: "Name of the Shortcuts/Siri action that works like the panic key: brings the MacBook’s own screen back right away")
    static var description: IntentDescription? {
        IntentDescription(LocalizedStringResource("Brings the built-in screen back right away, like the panic key. Also turns off Brightness Boost and any dimming of external displays.", comment: "Description of the “Turn the Built-in Display Back On” action in the Shortcuts app. “Brightness Boost” is Lidless’s feature name."))
    }

    static let openAppWhenRun = false
    @available(macOS 26, *)
    static var supportedModes: IntentModes { .background }
    /// Also the default; spelled out because this one must never wait for an unlock.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await AppIntentBridge.forIntent().panic()
        let dialog: IntentDialog = switch outcome {
        case .turnedOff:
            IntentDialog(LocalizedStringResource("The built-in screen is back on.", comment: "Shortcuts/Siri reply after “Turn the Built-in Display Back On” brought the screen back"))
        case .alreadyOff, .unavailable:
            IntentDialog(LocalizedStringResource("The built-in screen is already on.", comment: "Shortcuts/Siri reply after “Turn the Built-in Display Back On” when Desk Mode wasn't on"))
        case .stillSwitching, .turnedOn, .alreadyOn, .couldNotTurnOn, .busy:
            IntentDialog(LocalizedStringResource("Lidless is still bringing the built-in screen back.", comment: "Shortcuts/Siri reply when the built-in screen hasn’t come back yet after several seconds (Lidless keeps trying)"))
        }
        return .result(dialog: dialog)
    }
}

@available(macOS 13, *)
nonisolated struct GetDeskModeStateIntent: AppIntent {
    static let title = LocalizedStringResource("Get Desk Mode State", comment: "Name of the Shortcuts/Siri action that reports whether Desk Mode is on")
    static var description: IntentDescription? {
        IntentDescription(LocalizedStringResource("Returns whether Desk Mode is on, which means the built-in screen is off.", comment: "Description of the “Get Desk Mode State” action in the Shortcuts app; the action outputs true or false"))
    }

    static let openAppWhenRun = false
    @available(macOS 26, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let state = try await AppIntentBridge.forIntent().deskModeState()
        let dialog: IntentDialog = switch state {
        case .on:
            IntentDialog(LocalizedStringResource("Desk Mode is on. The built-in screen is off.", comment: "Shortcuts/Siri reply: Desk Mode is on"))
        case .off:
            IntentDialog(LocalizedStringResource("Desk Mode is off.", comment: "Shortcuts/Siri reply: Desk Mode is off and could be turned on"))
        case .switching(toOn: true):
            IntentDialog(LocalizedStringResource("Desk Mode is turning on.", comment: "Shortcuts/Siri reply: the built-in screen is switching off right now"))
        case .switching(toOn: false):
            IntentDialog(LocalizedStringResource("Desk Mode is turning off.", comment: "Shortcuts/Siri reply: the built-in screen is coming back right now"))
        case .unavailable(.needsDisplay):
            IntentDialog(LocalizedStringResource("Desk Mode is off. It needs an external display.", comment: "Shortcuts/Siri reply: Desk Mode is off and can't be turned on until a monitor is plugged in"))
        case .unavailable(.lidClosed):
            IntentDialog(LocalizedStringResource("Desk Mode is off while the lid is closed.", comment: "Shortcuts/Siri reply: Desk Mode is off and can't be turned on while the MacBook lid is closed"))
        case .unavailable(.unsupportedMac):
            IntentDialog(LocalizedStringResource("Desk Mode isn't available on this Mac.", comment: "Shortcuts/Siri reply: this Mac can't use Desk Mode"))
        case .unavailable(.unsupportedSystem):
            IntentDialog(LocalizedStringResource("Desk Mode isn't available on this version of macOS.", comment: "Shortcuts/Siri reply: this macOS version can't use Desk Mode"))
        }
        return .result(value: state.isOn, dialog: dialog)
    }
}

@available(macOS 13, *)
extension DeskModeIntentOutcome {
    /// The reply for Turn On, Turn Off and Toggle; failures throw so a shortcut stops.
    func switchDialog() throws -> IntentDialog {
        switch self {
        case .turnedOn(asksToKeep: true):
            IntentDialog(LocalizedStringResource("Desk Mode is on. Choose Keep Off on your other display to keep the built-in screen off.", comment: "Shortcuts/Siri reply after turning Desk Mode on when the keep-or-revert prompt is showing (“Ask before keeping it off” is on, or Lidless's setup isn't finished yet). “Keep Off” is the prompt's button; without it the screen comes back after 15 seconds."))
        case .turnedOn(asksToKeep: false):
            IntentDialog(LocalizedStringResource("Desk Mode is on. The built-in screen is off.", comment: "Shortcuts/Siri reply: Desk Mode is on"))
        case .alreadyOn:
            IntentDialog(LocalizedStringResource("Desk Mode is already on.", comment: "Shortcuts/Siri reply after “Turn Desk Mode On” when it was already on"))
        case .turnedOff:
            IntentDialog(LocalizedStringResource("Desk Mode is off. The built-in screen is back on.", comment: "Shortcuts/Siri reply after turning Desk Mode off"))
        case .alreadyOff:
            IntentDialog(LocalizedStringResource("Desk Mode is already off.", comment: "Shortcuts/Siri reply after “Turn Desk Mode Off” when it was already off"))
        case .stillSwitching(toOn: true):
            IntentDialog(LocalizedStringResource("Desk Mode is still turning on.", comment: "Shortcuts/Siri reply when the built-in screen is still switching off after several seconds"))
        case .stillSwitching(toOn: false):
            IntentDialog(LocalizedStringResource("Lidless is still bringing the built-in screen back.", comment: "Shortcuts/Siri reply when the built-in screen hasn’t come back yet after several seconds (Lidless keeps trying)"))
        case .unavailable(let reason):
            throw LidlessIntentError.deskModeUnavailable(reason)
        case .couldNotTurnOn:
            throw LidlessIntentError.deskModeFailed
        case .busy:
            throw LidlessIntentError.deskModeBusy
        }
    }
}
