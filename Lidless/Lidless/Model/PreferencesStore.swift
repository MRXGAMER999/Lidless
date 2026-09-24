import Combine
import Foundation
import LidlessCore
import os

/// The user's saved choices: Desk Mode's and Boost's settings, the global
/// shortcuts and the app-wide settings. Each is one JSON value in UserDefaults,
/// so a new field decodes from older saves with its default (see
/// `DeskModeSettings`, `BoostSettings`, `ShortcutSet` and `GeneralSettings`).
///
/// The Settings window and onboarding edit them; the controllers follow them.
/// A value that can't be decoded falls back to the defaults and is left on disk
/// until the next change overwrites it.
final class PreferencesStore: ObservableObject {
    static let deskModeKey = "deskMode.settings"
    static let shortcutsKey = "shortcuts"
    static let boostKey = "boost.settings"
    static let generalKey = "general.settings"

    @Published var deskMode: DeskModeSettings {
        didSet { if deskMode != oldValue { save(deskMode, forKey: Self.deskModeKey) } }
    }

    @Published var shortcuts: ShortcutSet {
        didSet { if shortcuts != oldValue { save(shortcuts, forKey: Self.shortcutsKey) } }
    }

    /// Settings › Brightness.
    @Published var boost: BoostSettings {
        didSet { if boost != oldValue { save(boost, forKey: Self.boostKey) } }
    }

    /// Settings › Keys & App (menu bar icon, auto-update) and first-run state.
    @Published var general: GeneralSettings {
        didSet { if general != oldValue { save(general, forKey: Self.generalKey) } }
    }

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Preferences")

    /// - Parameter defaults: `.standard` in the app; tests pass their own suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deskMode = Self.load(DeskModeSettings.self, forKey: Self.deskModeKey, from: defaults) ?? .defaults
        shortcuts = Self.load(ShortcutSet.self, forKey: Self.shortcutsKey, from: defaults) ?? .defaults
        boost = Self.load(BoostSettings.self, forKey: Self.boostKey, from: defaults) ?? .defaults
        general = Self.load(GeneralSettings.self, forKey: Self.generalKey, from: defaults) ?? .defaults
    }

    private static func load<Value: Decodable>(_ type: Value.Type, forKey key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save(_ value: some Encodable, forKey key: String) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            defaults.set(try encoder.encode(value), forKey: key)
        } catch {
            log.error("Couldn't save \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
