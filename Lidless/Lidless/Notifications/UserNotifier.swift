import Foundation
import LidlessCore
import UserNotifications
import os

/// Posts Lidless's informational notifications. Never part of the safety path:
/// the user may have turned notifications off or be in a Focus, and nothing
/// waits for a post to land.
///
/// Create one at launch and keep it: it makes itself the notification center's
/// delegate (a weak reference) so banners also show while Lidless is frontmost,
/// for example with the popover open. Permission is asked the first time
/// something is posted, not at launch, and checked again before every post:
/// the user can allow notifications in System Settings at any time.
///
/// Swift 6: UserNotifications calls its delegate and completions on its own
/// queue. Everything here that runs there is `nonisolated` or goes through
/// the async APIs; a main-actor completion would trap at run time.
final class UserNotifier: NSObject, DeskModeNotifier, UNUserNotificationCenterDelegate {
    private nonisolated static let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Notifications")

    /// nil when the process is not a bundled app (a bare test binary), where
    /// `UNUserNotificationCenter.current()` raises.
    private let center: UNUserNotificationCenter?
    /// The permission request in flight, if any; posts made meanwhile wait for its answer.
    private var authorizationRequest: Task<Bool, Never>?

    override init() {
        let bundle = Bundle.main
        center = bundle.bundleIdentifier != nil && bundle.bundleURL.pathExtension == "app"
            ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
    }

    // MARK: - DeskModeNotifier

    func restored(_ reason: DeskModeRestoreReason) {
        guard let note = Self.note(for: reason) else { return }
        post(note)
    }

    func recoveredAfterCrash() {
        post(Note(
            id: "desk-mode.recovered",
            thread: "desk-mode",
            title: Self.restoredTitle,
            body: String(localized: "Notification.Recovered.Body", defaultValue: "Lidless quit unexpectedly. Your built-in screen was turned back on.", comment: "Notification body at launch, after Lidless restored the built-in screen that a crashed run had left off (Desk Mode turns the MacBook's own screen off). \"Built-in screen\" is the MacBook's own display."),
            sound: true
        ))
    }

    /// Once ever: turning the built-in off or on made macOS switch another
    /// display's mode, so that monitor went dark for a moment while it resynced.
    func otherDisplaySwitchedMode() {
        guard !UserDefaults.standard.bool(forKey: Self.modeSwitchTipKey) else { return }
        post(Note(
            id: "desk-mode.mode-switch",
            thread: "desk-mode",
            title: String(localized: "Notification.ModeSwitch.Title", defaultValue: "Why your other screen blinked", comment: "Notification title, shown once: when Desk Mode turned the MacBook's own screen off or on, the external monitor went dark for a moment."),
            body: String(localized: "Notification.ModeSwitch.Body", defaultValue: "macOS gives that screen different settings when the built-in screen is off, so it resyncs. Give it the same resolution in both setups to stop the blink.", comment: "Notification body, shown once. macOS remembers separate display settings for \"external screen alone\" and \"MacBook + external screen\"; when they differ, switching makes the external monitor resync (go dark briefly). \"Built-in screen\" is the MacBook's own display."),
            sound: false
        )) {
            // Only once it was really posted: notifications may be off for now.
            UserDefaults.standard.set(true, forKey: Self.modeSwitchTipKey)
        }
    }

    private static let modeSwitchTipKey = "deskMode.modeSwitchTipShown"

    // MARK: - Brightness Boost

    /// Boost stepped back by itself. `hot`: the Mac got too hot; otherwise the
    /// battery fell below the Settings threshold.
    func boostPaused(hot: Bool) {
        let body = hot
            ? String(localized: "Notification.BoostPaused.Hot.Body", defaultValue: "Your Mac is running hot. Boost comes back when it cools down.", comment: "Notification body when Brightness Boost (extra brightness beyond the normal maximum) paused itself because the Mac got too hot.")
            : String(localized: "Notification.BoostPaused.Battery.Body", defaultValue: "Your battery is running low. Boost comes back when you plug in your Mac.", comment: "Notification body when Brightness Boost (extra brightness beyond the normal maximum) paused itself because the battery fell below the level chosen in Settings.")
        post(Note(
            id: "boost.paused",
            thread: "boost",
            title: String(localized: "Notification.BoostPaused.Title", defaultValue: "Brightness Boost paused", comment: "Notification title when Brightness Boost (extra brightness beyond the normal maximum) turned itself off for now. \"Brightness Boost\" is a feature name."),
            body: body,
            sound: false
        ))
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners while Lidless is frontmost too (by default they are dropped).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // MARK: - Posting

    /// A notification's content. Plain values, so it can cross into the async posting task.
    nonisolated struct Note: Sendable, Equatable {
        /// Fixed per kind: a newer post replaces the older one instead of stacking.
        var id: String
        var thread: String
        var title: String
        var body: String
        var sound: Bool
    }

    /// `onPosted` runs after the notification center accepted the note.
    private func post(_ note: Note, onPosted: (() -> Void)? = nil) {
        guard let center else { return }
        Task {
            guard await isAllowed(center) else {
                Self.log.info("Notifications not allowed; skipped \(note.id, privacy: .public)")
                return
            }
            do {
                try await center.add(Self.request(for: note))
                onPosted?()
            } catch {
                Self.log.error("Couldn't post \(note.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reads the current setting rather than remembering an answer, so a "no"
    /// earlier in this run doesn't outlast the user changing their mind.
    private func isAllowed(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            let request = authorizationRequest ?? Task { await Self.requestAuthorization(center) }
            authorizationRequest = request
            let granted = await request.value
            authorizationRequest = nil
            return granted
        default:
            return false
        }
    }

    /// The system only shows a prompt while the user hasn't decided yet.
    private nonisolated static func requestAuthorization(_ center: UNUserNotificationCenter) async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private nonisolated static func request(for note: Note) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.threadIdentifier = note.thread
        content.interruptionLevel = .active
        if note.sound { content.sound = .default }
        return UNNotificationRequest(identifier: note.id, content: content, trigger: nil)
    }

    // MARK: - Copy

    private nonisolated static var restoredTitle: String {
        String(localized: "Notification.Restored.Title", defaultValue: "Built-in display turned back on", comment: "Notification title after Lidless switched the MacBook's own screen back on (Desk Mode had turned it off to run cooler with external displays).")
    }

    /// nil for reasons the user caused and already sees (switching Desk Mode
    /// off, "Turn Back On" in the prompt, the panic key, quitting) and for
    /// `.recovery`, which only carries on a restore that launch recovery or
    /// quitting started.
    nonisolated static func note(for reason: DeskModeRestoreReason) -> Note? {
        let body: String
        var title = restoredTitle
        switch reason {
        case .user, .declined, .panic, .terminating, .recovery:
            return nil
        case .externalLost:
            body = String(localized: "Notification.Restored.ExternalLost.Body", defaultValue: "Your last external display was unplugged, so Lidless switched your built-in screen back on.", comment: "Notification body after the last external display went away and Lidless turned the MacBook's own screen back on.")
        case .confirmationTimedOut:
            body = String(localized: "Notification.Restored.TimedOut.Body", defaultValue: "Nobody answered, so your built-in screen came back on.", comment: "Notification body after nobody answered the \"keep the built-in screen off?\" prompt in time, so the MacBook's own screen came back on by itself.")
        case .sleep:
            body = String(localized: "Notification.Restored.Sleep.Body", defaultValue: "Your Mac went to sleep, so Lidless switched your built-in screen back on.", comment: "Notification body, shown after wake: the Mac slept while Desk Mode had the MacBook's own screen off, so Lidless turned that screen back on.")
        case .sessionChanged:
            body = String(localized: "Notification.Restored.SessionChanged.Body", defaultValue: "Your Mac was locked or switched to another user, so Lidless switched your built-in screen back on.", comment: "Notification body after the screen was locked or another user account took over the Mac (fast user switching), so Lidless turned the MacBook's own screen back on.")
        case .engageFailed:
            title = String(localized: "Notification.EngageFailed.Title", defaultValue: "Desk Mode didn't turn on", comment: "Notification title when Desk Mode (turns the MacBook's own screen off while external displays are connected) failed to start.")
            body = String(localized: "Notification.EngageFailed.Body", defaultValue: "Lidless couldn't turn the built-in screen off, so it left it on.", comment: "Notification body when turning the MacBook's own screen off failed or could not be confirmed, so Lidless left it on.")
        case .timeLimit:
            body = String(localized: "Notification.Restored.TimeLimit.Body", defaultValue: "Development builds end Desk Mode after a few minutes, so Lidless switched your built-in screen back on.", comment: "Only in development (Debug) builds, never in released versions: Desk Mode ended after its test time limit and the MacBook's own screen came back on. Low priority.")
        }
        return Note(id: "desk-mode.restored", thread: "desk-mode", title: title, body: body, sound: true)
    }
}
