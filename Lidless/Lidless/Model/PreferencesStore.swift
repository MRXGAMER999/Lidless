import Combine
import Foundation
import LidlessCore
import os

/// The user's saved choices: Desk Mode's settings and the global shortcuts.
/// Each is one JSON value in UserDefaults, so a new field decodes from older
/// saves with its default (see `DeskModeSettings` and `ShortcutSet`).
///
/// Phase 3 only reads and writes them; the Settings window (Phase 5) edits them.
/// A value that can't be decoded falls back to the defaults and is left on disk
/// until the next change overwrites it.
final class PreferencesStore: ObservableObject {
    static let deskModeKey = "deskMode.settings"
    static let shortcutsKey = "shortcuts"

    @Published var deskMode: DeskModeSettings {
        didSet { if deskMode != oldValue { save(deskMode, forKey: Self.deskModeKey) } }
    }

    @Published var shortcuts: ShortcutSet {
        didSet { if shortcuts != oldValue { save(shortcuts, forKey: Self.shortcutsKey) } }
    }

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Preferences")

    /// - Parameter defaults: `.standard` in the app; tests pass their own suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deskMode = Self.load(DeskModeSettings.self, forKey: Self.deskModeKey, from: defaults) ?? .defaults
        shortcuts = Self.load(ShortcutSet.self, forKey: Self.shortcutsKey, from: defaults) ?? .defaults
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
