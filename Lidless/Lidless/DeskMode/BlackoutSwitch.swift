import AppKit
import CoreGraphics
import LidlessCore
import os

/// "Black out": a black, click-through window over the built-in screen. The
/// panel stays in the arrangement, so windows stay put and switching back is
/// just removing the window.
///
/// Nothing here persists: no brightness, no gamma. Both would outlive a crash;
/// the window dies with the process, so the sidecar never needs to restore it.
///
/// The cover never follows the panel anywhere. If the built-in screen goes away,
/// joins a mirror set, or the window lands on another screen, the window is
/// removed at once (a black external would leave the user with no screen) and
/// comes back only on the next `disable`.
final class BlackoutSwitch: BuiltInSwitch {
    /// Called after the cover was removed on its own (the screen went away or
    /// the window moved), not after `enable`. The controller can treat it like
    /// the panel coming back by itself.
    var onCoverLost: (@MainActor () -> Void)?

    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Blackout")
    private let box = BlackoutCallbackBox()
    private var window: NSWindow?
    /// The panel the window covers; its ID can be re-issued, the UUID can't.
    private var coveredID: CGDirectDisplayID?
    private var coveredUUID: String?
    private var observations: [any NSObjectProtocol] = []
    private var callbackRegistered = false

    func disable(displayID: CGDirectDisplayID, uuid: String?, completion: @escaping @MainActor (Bool) -> Void) {
        guard let screen = Self.builtInScreen(id: displayID, uuid: uuid),
              let screenID = Self.displayID(of: screen) else {
            log.error("Black out: no built-in screen for display \(displayID)")
            removeCover()
            finish(completion, false)
            return
        }
        coveredID = screenID
        coveredUUID = uuid ?? Self.uuid(of: screenID)
        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
        startWatching(window)

        // Checked a turn later, after AppKit has placed the window.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                let ok = self?.isCovering() ?? false
                if !ok {
                    self?.log.error("Black out: the cover is not on the built-in screen")
                    self?.removeCover()
                }
                completion(ok)
            }
        }
    }

    func enable(displayID: CGDirectDisplayID?, uuid: String?, completion: @escaping @MainActor (Bool) -> Void) {
        removeCover()
        finish(completion, true)
    }

    func enableNow(displayID: CGDirectDisplayID?, uuid: String?, timeout: TimeInterval) -> Bool {
        removeCover()
        return true
    }

    // MARK: - Cover window

    private func makeWindow() -> NSWindow {
        // Borderless panels aren't constrained to the visible frame, so the menu
        // bar and notch area are covered too. Non-activating: it never takes focus.
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.ignoresMouseEvents = true
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        if #available(macOS 13.0, *) {
            behavior.insert(.canJoinAllApplications)
        }
        panel.collectionBehavior = behavior
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        // A menu bar app is often inactive; a panel that hides on deactivate
        // would uncover the screen the moment another app is clicked.
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        return panel
    }

    /// The window is up, on the built-in screen, filling it, and that screen
    /// shows only the built-in (not a mirror set with an external).
    private func isCovering() -> Bool {
        guard let window, window.isVisible, let id = coveredID,
              let screen = Self.builtInScreen(id: id, uuid: coveredUUID),
              let screenID = Self.displayID(of: screen),
              let windowScreen = window.screen,
              Self.displayID(of: windowScreen) == screenID,
              CGDisplayIsInMirrorSet(screenID) == 0 else { return false }
        return window.frame == screen.frame
    }

    private func removeCover() {
        stopWatching()
        window?.orderOut(nil)
        window = nil
        coveredID = nil
        coveredUUID = nil
    }

    /// The cover went wrong by itself: remove it now, re-cover only on request.
    private func coverLost(_ why: String) {
        guard window != nil else { return }
        log.notice("Black out: removing the cover, \(why, privacy: .public)")
        removeCover()
        onCoverLost?()
    }

    // MARK: - Watching the screen

    private func startWatching(_ window: NSWindow) {
        guard observations.isEmpty else { return }
        let center = NotificationCenter.default
        observations = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            },
            center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            },
        ]
        // CoreGraphics reports a removed or mirrored panel before AppKit has
        // rebuilt its screens, so the cover is gone before it can be moved.
        box.handler = { [weak self] id, flags in self?.displayReconfigured(id, flags) }
        callbackRegistered = CGDisplayRegisterReconfigurationCallback(
            blackoutDisplayReconfigured, Unmanaged.passUnretained(box).toOpaque()
        ) == .success
    }

    private func stopWatching() {
        for token in observations {
            NotificationCenter.default.removeObserver(token)
        }
        observations = []
        if callbackRegistered {
            CGDisplayRemoveReconfigurationCallback(blackoutDisplayReconfigured, Unmanaged.passUnretained(box).toOpaque())
            callbackRegistered = false
        }
        box.handler = nil
    }

    private func displayReconfigured(_ id: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags) {
        guard id == coveredID, !flags.isDisjoint(with: [.removeFlag, .disabledFlag, .mirrorFlag]) else { return }
        coverLost("the built-in screen was removed or mirrored")
    }

    private func screensChanged() {
        guard let window, let id = coveredID else { return }
        guard let screen = Self.builtInScreen(id: id, uuid: coveredUUID),
              let screenID = Self.displayID(of: screen),
              CGDisplayIsInMirrorSet(screenID) == 0 else {
            coverLost("the built-in screen is gone or mirrored")
            return
        }
        guard let windowScreen = window.screen, Self.displayID(of: windowScreen) == screenID else {
            coverLost("the window left the built-in screen")
            return
        }
        coveredID = screenID
        // Same screen, new size (a resolution change): follow it.
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
    }

    // MARK: - Helpers

    private func finish(_ completion: @escaping @MainActor (Bool) -> Void, _ ok: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { completion(ok) }
        }
    }

    /// The `NSScreen` for the built-in panel: by ID, else by UUID when the ID
    /// was re-issued. Never a screen that isn't built in.
    private static func builtInScreen(id: CGDirectDisplayID, uuid: String?) -> NSScreen? {
        let builtIns = NSScreen.screens.filter { screen in
            guard let screenID = displayID(of: screen) else { return false }
            return CGDisplayIsBuiltin(screenID) != 0
        }
        if let match = builtIns.first(where: { displayID(of: $0) == id }) {
            return match
        }
        guard let uuid else { return nil }
        return builtIns.first { screen in
            displayID(of: screen).flatMap(Self.uuid(of:)) == uuid
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        if #available(macOS 26.0, *) {
            return screen.cgDirectDisplayID
        }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cf) as String?
    }
}

/// Picks the disconnect or black out switch by the chosen method for each
/// `disable`, and sends every enable to both, so changing the method while
/// Desk Mode is on (or a half-done disable of either kind) can't leave the
/// panel off. Both enables are safe when nothing is off: removing a cover that
/// isn't there is instant, and the disconnect switch reports a panel that is
/// already online as a success without a transaction.
final class CompositeBuiltInSwitch: BuiltInSwitch {
    /// The method the next `disable` uses.
    var method: DeskModeMethod
    private let disconnect: any BuiltInSwitch
    private let blackout: any BuiltInSwitch

    init(method: DeskModeMethod, disconnect: any BuiltInSwitch, blackout: any BuiltInSwitch) {
        self.method = method
        self.disconnect = disconnect
        self.blackout = blackout
    }

    func disable(displayID: CGDirectDisplayID, uuid: String?, completion: @escaping @MainActor (Bool) -> Void) {
        target(method).disable(displayID: displayID, uuid: uuid, completion: completion)
    }

    /// Succeeds once both have succeeded; reports once, after both answered.
    func enable(displayID: CGDirectDisplayID?, uuid: String?, completion: @escaping @MainActor (Bool) -> Void) {
        let join = EnableJoin(waiting: 2, completion: completion)
        blackout.enable(displayID: displayID, uuid: uuid) { join.answer($0) }
        disconnect.enable(displayID: displayID, uuid: uuid) { join.answer($0) }
    }

    /// Quit, signal and launch-recovery paths: true only if both succeed. The
    /// cover goes first; it is instant, and the disconnect may block.
    func enableNow(displayID: CGDirectDisplayID?, uuid: String?, timeout: TimeInterval) -> Bool {
        let covered = blackout.enableNow(displayID: displayID, uuid: uuid, timeout: timeout)
        let connected = disconnect.enableNow(displayID: displayID, uuid: uuid, timeout: timeout)
        return covered && connected
    }

    private func target(_ method: DeskModeMethod) -> any BuiltInSwitch {
        switch method {
        case .disconnect: disconnect
        case .blackout: blackout
        }
    }
}

/// Collects the answers of the composite's two enables on the main actor.
private final class EnableJoin {
    private var waiting: Int
    private var allSucceeded = true
    private let completion: @MainActor (Bool) -> Void

    init(waiting: Int, completion: @escaping @MainActor (Bool) -> Void) {
        self.waiting = waiting
        self.completion = completion
    }

    func answer(_ ok: Bool) {
        allSucceeded = allSucceeded && ok
        waiting -= 1
        if waiting == 0 { completion(allSucceeded) }
    }
}

/// Carries the switch's handler through the C callback's `userInfo`. The
/// handler is written and called on the main thread only.
private nonisolated final class BlackoutCallbackBox: @unchecked Sendable {
    var handler: (@MainActor (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void)?
}

/// Captures nothing, as a C callback must, and may run off the main thread
/// (inside another agent's configuration transaction), so it only hops to main.
private nonisolated func blackoutDisplayReconfigured(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    // The begin pass carries no detail; the end pass follows.
    guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
    let box = Unmanaged<BlackoutCallbackBox>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated { box.handler?(display, flags) }
    }
}
