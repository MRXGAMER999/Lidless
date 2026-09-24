import Foundation
import Testing
@testable import LidlessCore

/// `GeneralSettings` as saved in UserDefaults ("general.settings"): older or
/// partial saves decode with the defaults for what they lack.
struct GeneralSettingsTests {
    private static func decode(_ json: String) throws -> GeneralSettings {
        try JSONDecoder().decode(GeneralSettings.self, from: Data(json.utf8))
    }

    @Test func `the defaults show state in the icon, update automatically and haven't onboarded`() {
        let settings = GeneralSettings.defaults
        #expect(settings.iconShowsState)
        #expect(settings.autoUpdate)
        #expect(!settings.onboardingCompleted)
    }

    @Test func `an empty save decodes to the defaults`() throws {
        #expect(try Self.decode("{}") == .defaults)
    }

    @Test(arguments: [
        (#"{"onboardingCompleted":true}"#, GeneralSettings(iconShowsState: true, onboardingCompleted: true, autoUpdate: true)),
        (#"{"iconShowsState":false}"#, GeneralSettings(iconShowsState: false, onboardingCompleted: false, autoUpdate: true)),
        (#"{"autoUpdate":false}"#, GeneralSettings(iconShowsState: true, onboardingCompleted: false, autoUpdate: false)),
        (#"{"autoUpdate":false,"onboardingCompleted":true}"#, GeneralSettings(iconShowsState: true, onboardingCompleted: true, autoUpdate: false)),
    ])
    func `missing keys take their defaults`(json: String, expected: GeneralSettings) throws {
        #expect(try Self.decode(json) == expected)
    }

    @Test func `keys this version doesn't know are ignored`() throws {
        let settings = try Self.decode(#"{"onboardingCompleted":true,"somethingNewer":42}"#)
        #expect(settings == GeneralSettings(iconShowsState: true, onboardingCompleted: true, autoUpdate: true))
    }

    @Test func `a value of the wrong type is an error, not a silent default`() {
        #expect(throws: DecodingError.self) { try Self.decode(#"{"onboardingCompleted":"yes"}"#) }
    }

    @Test func `a round trip keeps every field`() throws {
        let settings = GeneralSettings(iconShowsState: false, onboardingCompleted: true, autoUpdate: false)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(GeneralSettings.self, from: data) == settings)
    }
}
