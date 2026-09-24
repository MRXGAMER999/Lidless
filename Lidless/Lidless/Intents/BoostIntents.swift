import AppIntents
import Foundation
import LidlessCore

/// Brightness Boost for Shortcuts and Siri. On takes the Boost key's path (the
/// last boosted level this session, or the ceiling); off is "Back to 100%".
/// Boost's guard rails still apply: a paused Boost says why.
///
/// The type name and the parameter are a contract with saved shortcuts. The
/// metadata strings (title, description, parameter, its On/Off names) are
/// `LocalizedStringResource` initializers with literal arguments only (key and
/// translator comment), so the build-time App Intents extractor and the string
/// catalog still read them. The summary stays a plain literal: `Summary` takes
/// no comment.
///
/// Unlike the Desk Mode intents this type isn't `nonisolated`: a nonisolated
/// type can't hold a property-wrapped `@Parameter` (Swift 6.2). It keeps the
/// module's main-actor default, and every requirement the framework reads off
/// the main actor (the statics and `init()`) is `nonisolated`, so the
/// conformance stays nonisolated as `AppIntent: Sendable` requires.
@available(macOS 13, *)
struct SetBrightnessBoostIntent: AppIntent {
    nonisolated static let title = LocalizedStringResource("Set Brightness Boost", comment: "Name of the Shortcuts/Siri action that turns Brightness Boost (Lidless’s extra-brightness feature for the built-in screen) on or off")
    nonisolated static var description: IntentDescription? {
        IntentDescription(LocalizedStringResource("Turns Brightness Boost on or off for the built-in screen. On goes back to your last Boost level, or the ceiling set in Lidless Settings.", comment: "Description of the “Set Brightness Boost” action in the Shortcuts app. “Brightness Boost” and “Boost” are Lidless’s feature name; the ceiling is the brightest level Boost may reach."))
    }

    nonisolated static let openAppWhenRun = false
    @available(macOS 26, *)
    nonisolated static var supportedModes: IntentModes { .background }

    @Parameter(
        title: LocalizedStringResource("Boost", comment: "Name of the on/off setting in the “Set Brightness Boost” Shortcuts action. “Boost” is Lidless’s extra-brightness feature (a noun, not the verb)."),
        default: true,
        displayName: Bool.IntentDisplayName(
            true: LocalizedStringResource("On", comment: "Value of the “Boost” setting in the “Set Brightness Boost” Shortcuts action, and the word Siri listens for in “Turn Brightness Boost on”: Boost switched on"),
            false: LocalizedStringResource("Off", comment: "Value of the “Boost” setting in the “Set Brightness Boost” Shortcuts action, and the word Siri listens for in “Turn Brightness Boost off”: Boost switched off")
        )
    )
    var isOn: Bool

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Turn Brightness Boost \(\.$isOn)")
    }

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await AppIntentBridge.forIntent().setBoost(on: isOn)
        return .result(dialog: try outcome.dialog())
    }
}

@available(macOS 13, *)
extension BoostIntentOutcome {
    /// The reply; refusals throw so a shortcut stops.
    func dialog() throws -> IntentDialog {
        switch self {
        case .turnedOn:
            IntentDialog(LocalizedStringResource("Brightness Boost is on.", comment: "Shortcuts/Siri reply after turning Brightness Boost on"))
        case .alreadyOn:
            IntentDialog(LocalizedStringResource("Brightness Boost is already on.", comment: "Shortcuts/Siri reply when Brightness Boost was already on"))
        case .turnedOff:
            IntentDialog(LocalizedStringResource("Brightness Boost is off.", comment: "Shortcuts/Siri reply after turning Brightness Boost off (the built-in screen goes to full normal brightness)"))
        case .alreadyOff:
            IntentDialog(LocalizedStringResource("Brightness Boost is already off.", comment: "Shortcuts/Siri reply when Brightness Boost was already off"))
        case .systemRefused:
            IntentDialog(LocalizedStringResource("Brightness Boost is on, but macOS isn't allowing it right now.", comment: "Shortcuts/Siri reply: Boost is set, but macOS gave the screen no extra brightness after several tries; it tries again the next time Boost is asked for"))
        case .paused(.hot):
            IntentDialog(LocalizedStringResource("Brightness Boost is on, but paused while your Mac is hot.", comment: "Shortcuts/Siri reply: Boost is set but paused at the heat level set in Settings; it comes back by itself when the Mac cools down"))
        case .paused(.lowBattery):
            IntentDialog(LocalizedStringResource("Brightness Boost is on, but paused while the battery is low.", comment: "Shortcuts/Siri reply: Boost is set but paused below the battery level set in Settings; it comes back by itself when charging"))
        case .paused(.lowPower):
            IntentDialog(LocalizedStringResource("Brightness Boost is on, but paused while Low Power Mode is on.", comment: "Shortcuts/Siri reply: Boost is set but paused while macOS Low Power Mode is on. “Low Power Mode” is the macOS feature name; use Apple’s translation."))
        case .paused(.builtInUnavailable):
            IntentDialog(LocalizedStringResource("Brightness Boost is on, but paused while the built-in screen is off.", comment: "Shortcuts/Siri reply: Boost is set but paused because the lid is closed or Desk Mode has the built-in screen off"))
        case .paused(.screenAsleepOrLocked):
            IntentDialog(LocalizedStringResource("Brightness Boost is on, but paused while the screen sleeps.", comment: "Shortcuts/Siri reply: Boost is set but paused while the displays sleep or the screen is locked"))
        case .paused(.reconfiguring):
            IntentDialog(LocalizedStringResource("Brightness Boost is on, but paused while displays change.", comment: "Shortcuts/Siri reply: Boost is set but paused for a few seconds while a display is connected, disconnected or rearranged"))
        case .paused(.hdrSuppressed):
            IntentDialog(LocalizedStringResource("Brightness Boost is on, but paused while macOS limits bright content.", comment: "Shortcuts/Siri reply: Boost is set but paused because macOS asked apps to hold back HDR (extra-bright) content for now"))
        case .notAllowed, .paused(.notAllowed):
            throw LidlessIntentError.boostNotAllowed
        case .unsupported, .paused(.unsupported):
            throw LidlessIntentError.boostUnsupported
        }
    }
}
