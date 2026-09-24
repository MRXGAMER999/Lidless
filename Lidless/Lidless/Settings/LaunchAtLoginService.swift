import Foundation
import os
import ServiceManagement

/// "Start Lidless when I log in", backed by `SMAppService.mainApp` (macOS 13+).
///
/// Every read asks ServiceManagement for the live status, so a change the user
/// makes in System Settings › General › Login Items shows up next time the
/// Settings window draws; nothing is cached or stored in preferences.
///
/// Notes on signing and location (researched 2026-09; H = header or Apple,
/// M = several independent reports, L = one report):
/// - **Ad-hoc signing works for `mainApp`** [M]. The header only says apps
///   using SMAppService "must be code signed" (unsigned or linker-signed only
///   bundles fail with `kSMErrorInvalidSignature`). Community tests of an
///   ad-hoc ("Sign to Run Locally") bundle went notFound → enabled with no
///   error, and the registration survived a rebuild that changed the cdhash:
///   Background Task Management keys login items on the bundle identifier,
///   not the cdhash as TCC does. DTS's warning that ad-hoc signing "will see
///   problems" (forums thread 799910) is about agents/daemons embedded in the
///   app, which Lidless does not use.
/// - **One record per bundle identifier, pointing at a path** [M]. `register()`
///   records the running copy's path, so enabling it from a build in Xcode's
///   DerivedData makes the login item launch that build. One report [L] says
///   even reading `status` from another copy moves the record to that copy.
///   So a dev build can take over the user's installed registration; after
///   testing from Xcode, switch the toggle off (or on again from the copy in
///   /Applications). Registration is not blocked by path, so dev builds stay
///   testable.
/// - **App Translocation**: a quarantined app opened from ~/Downloads runs
///   from a random read-only path; registering from there points the login
///   item at a path that disappears. `setEnabled(true)` logs a warning; the
///   README should tell users to move Lidless to /Applications first.
/// - **Status meanings** (header): `.requiresApproval` means registered but the
///   user switched it off in Login Items (or hasn't approved it yet); only
///   they can switch it back on there. On some macOS versions a revoked main
///   app reads `.notRegistered` instead [M]; both read as "off" here. A fresh
///   install can read `.notFound` rather than `.notRegistered` [M], which is
///   also "off" and still registers normally.
/// - `register()` on an already-registered service fails with
///   `kSMErrorAlreadyRegistered` and `unregister()` on an unregistered one with
///   `kSMErrorJobNotFound`, so both are skipped when the live status already
///   matches, and every outcome is judged by the status read afterwards.
final class LaunchAtLoginService: LaunchAtLogin {
    private let backend: any LoginItemBackend
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "LaunchAtLogin")

    convenience init() {
        self.init(backend: MainAppLoginItem())
    }

    /// - Parameter backend: tests pass a fake.
    init(backend: any LoginItemBackend) {
        self.backend = backend
    }

    var isAvailable: Bool { backend.isAvailable }

    var isEnabled: Bool { backend.isAvailable && backend.status == .enabled }

    var needsApproval: Bool { backend.isAvailable && backend.status == .requiresApproval }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard backend.isAvailable else {
            log.error("Launch at login needs macOS 13 or later")
            return false
        }
        let before = backend.status
        if enabled {
            if before == .enabled { return true }
            let path = Bundle.main.bundlePath
            if path.contains("/AppTranslocation/") {
                log.warning("Registering a translocated copy at \(path, privacy: .public); move Lidless to /Applications")
            }
            do {
                try backend.register()
                log.info("Registered \(path, privacy: .public) (was \(before.logName, privacy: .public))")
            } catch {
                log.error("Couldn't register (was \(before.logName, privacy: .public)): \(error.localizedDescription, privacy: .public) [\(Self.describe(error), privacy: .public)]")
            }
        } else {
            if before == .notRegistered || before == .notFound { return true }
            do {
                try backend.unregister()
                log.info("Unregistered (was \(before.logName, privacy: .public))")
            } catch {
                log.error("Couldn't unregister (was \(before.logName, privacy: .public)): \(error.localizedDescription, privacy: .public) [\(Self.describe(error), privacy: .public)]")
            }
        }
        // Judge by what the system now says: an "already registered" error still
        // leaves it on, and a register that needs approval leaves it off.
        let after = backend.status
        let succeeded = enabled ? after == .enabled : after != .enabled
        if !succeeded {
            log.error("Launch at login is \(after.logName, privacy: .public) after asking for \(enabled ? "on" : "off", privacy: .public)")
        }
        return succeeded
    }

    func openLoginItemsSettings() {
        guard backend.isAvailable else {
            log.error("Login Items settings need macOS 13 or later")
            return
        }
        backend.openSettings()
    }

    private static func describe(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}

// MARK: - Backend

/// `SMAppService.Status`, usable below macOS 13.
enum LoginItemStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var logName: String {
        switch self {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        }
    }
}

/// The ServiceManagement calls `LaunchAtLoginService` makes; tests fake it.
protocol LoginItemBackend {
    var isAvailable: Bool { get }
    /// A live read every time.
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

/// `SMAppService.mainApp` on macOS 13+; unavailable (and inert) below.
struct MainAppLoginItem: LoginItemBackend {
    var isAvailable: Bool {
        if #available(macOS 13, *) { return true }
        return false
    }

    var status: LoginItemStatus {
        guard #available(macOS 13, *) else { return .notRegistered }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .notRegistered
        @unknown default: return .notFound
        }
    }

    func register() throws {
        guard #available(macOS 13, *) else { return }
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        guard #available(macOS 13, *) else { return }
        try SMAppService.mainApp.unregister()
    }

    func openSettings() {
        guard #available(macOS 13, *) else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
