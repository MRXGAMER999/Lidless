import AppKit
import Carbon.HIToolbox
import LidlessCore
import os

/// The app's global shortcuts, one Carbon hot key each.
nonisolated enum HotKeyID: UInt32, CaseIterable, Sendable {
    case panic = 1, toggleDeskMode, toggleBoost
}

/// Global shortcuts through Carbon `RegisterEventHotKey`, which needs no
/// Accessibility or Input Monitoring permission (safety.md §4).
///
/// Main thread only: Carbon's hot key calls are not thread safe. Carbon allows
/// one registration per key combination in an app, so a combination held by
/// another ID fails here, except that the panic key takes it over.
///
/// Carbon delivers nothing while this app tracks a menu, so the panic key is
/// also matched by a local key monitor while one is open (safety.md A7).
final class HotKeyCenter {
    nonisolated enum Registration: Equatable, Sendable {
        /// No other app receives this combination while we hold it.
        case exclusive
        /// Registered, but an app holding it exclusively silently gets every
        /// press. Carbon can't tell us when that happens.
        case shared
        /// Held back while `isPaused`; registered when the pause ends.
        case deferred
        case failed(OSStatus)

        var isRegistered: Bool {
            switch self {
            case .exclusive, .shared: true
            case .deferred, .failed: false
            }
        }
    }

    /// The outcome for each ID asked for; `.deferred` for those held back by `isPaused`.
    private(set) var registrations: [HotKeyID: Registration] = [:]

    /// While true (the shortcut recorder is listening), only the panic key
    /// stays registered, so the recorder receives the other combinations.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for id in HotKeyID.allCases where id != .panic {
                if isPaused {
                    release(id)
                    registrations[id] = bindings[id] == nil ? nil : .deferred
                } else if let binding = bindings[id] {
                    registrations[id] = attach(binding.shortcut, for: id)
                }
            }
        }
    }

    private struct Binding {
        let shortcut: KeyShortcut
        let handler: @MainActor () -> Void
    }

    /// Watches key downs while a menu is open: `NSEvent`'s local monitor, or a fake in tests.
    struct KeyDownMonitor {
        var add: (@escaping (NSEvent) -> NSEvent?) -> Any?
        var remove: (Any) -> Void

        static let local = KeyDownMonitor(
            add: { NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: $0) },
            remove: { NSEvent.removeMonitor($0) }
        )
    }

    private let registrar: HotKeyRegistrar
    private let keyDownMonitor: KeyDownMonitor
    private var bindings: [HotKeyID: Binding] = [:]
    /// IDs whose hot key Carbon currently holds.
    private var attached: Set<HotKeyID> = []
    private var openMenus = 0
    private var keyMonitorToken: Any?

    /// - Parameters:
    ///   - registrar: Carbon, or a fake in tests.
    ///   - notificationCenter: Where `NSMenu` posts its tracking notifications.
    init(
        registrar: HotKeyRegistrar = CarbonHotKeyRegistrar(),
        notificationCenter: NotificationCenter = .default,
        keyDownMonitor: KeyDownMonitor = .local
    ) {
        self.registrar = registrar
        self.keyDownMonitor = keyDownMonitor
        registrar.onPress = { [weak self] rawID in
            guard let self, let id = HotKeyID(rawValue: rawID) else { return false }
            return fire(id)
        }
        observeMenuTracking(in: notificationCenter)
    }

    /// Binds `shortcut` to `id`, replacing what `id` had.
    ///
    /// The panic key asks for exclusive use first and settles for shared use
    /// when another app already holds the combination exclusively; show a
    /// warning then, since that app may get the presses instead.
    ///
    /// While `isPaused`, other IDs are only remembered, registered on resume,
    /// and the result is `.deferred`.
    @discardableResult
    func register(_ shortcut: KeyShortcut, for id: HotKeyID, handler: @escaping @MainActor () -> Void) -> Registration {
        let previous = bindings[id]
        bindings[id] = Binding(shortcut: shortcut, handler: handler)
        if isPaused, id != .panic {
            registrations[id] = .deferred
            return .deferred
        }
        if previous?.shortcut == shortcut, let current = registrations[id], current.isRegistered {
            return current
        }
        release(id)
        let result = attach(shortcut, for: id)
        registrations[id] = result
        return result
    }

    func unregister(_ id: HotKeyID) {
        release(id)
        bindings[id] = nil
        registrations[id] = nil
    }

    func unregisterAll() {
        for id in HotKeyID.allCases { unregister(id) }
    }

    // MARK: - Carbon

    private func attach(_ shortcut: KeyShortcut, for id: HotKeyID) -> Registration {
        if let holder = attached.first(where: { $0 != id && bindings[$0]?.shortcut == shortcut }) {
            guard id == .panic else { return .failed(OSStatus(eventHotKeyExistsErr)) }
            // Nothing may keep the panic key from working.
            release(holder)
            registrations[holder] = .failed(OSStatus(eventHotKeyExistsErr))
        }
        let keyCode = UInt32(shortcut.keyCode)
        let modifiers = Self.carbonModifiers(shortcut.modifiers)
        if id == .panic {
            let status = registrar.register(keyCode: keyCode, modifiers: modifiers, id: id.rawValue, exclusive: true)
            if status == noErr {
                attached.insert(id)
                return .exclusive
            }
            guard status == OSStatus(eventHotKeyExistsErr) else { return .failed(status) }
        }
        let status = registrar.register(keyCode: keyCode, modifiers: modifiers, id: id.rawValue, exclusive: false)
        guard status == noErr else { return .failed(status) }
        attached.insert(id)
        return .shared
    }

    private func release(_ id: HotKeyID) {
        guard attached.remove(id) != nil else { return }
        registrar.unregister(id: id.rawValue)
    }

    private func fire(_ id: HotKeyID) -> Bool {
        guard attached.contains(id), let binding = bindings[id] else { return false }
        binding.handler()
        return true
    }

    /// Carbon's modifier mask (`cmdKey`, `optionKey` …) for `modifiers`.
    nonisolated static func carbonModifiers(_ modifiers: KeyShortcut.Modifiers) -> UInt32 {
        var mask = 0
        if modifiers.contains(.control) { mask |= controlKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        if modifiers.contains(.command) { mask |= cmdKey }
        return UInt32(mask)
    }

    // MARK: - Menu tracking

    /// Our modifiers in `flags`, ignoring Caps Lock, Fn and the keypad flag.
    nonisolated static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyShortcut.Modifiers {
        var modifiers: KeyShortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    private func observeMenuTracking(in center: NotificationCenter) {
        for (name, delta) in [(NSMenu.didBeginTrackingNotification, 1), (NSMenu.didEndTrackingNotification, -1)] {
            // AppKit posts these on the main thread, and the key monitor must be
            // in place before the menu's tracking loop reads the next key, so
            // run inline. The block holds self weakly, so it needs no removal.
            _ = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTrackingChanged(by: delta) }
            }
        }
    }

    private func menuTrackingChanged(by delta: Int) {
        openMenus = max(0, openMenus + delta)
        if openMenus > 0, keyMonitorToken == nil {
            keyMonitorToken = keyDownMonitor.add { [weak self] event in
                guard let self, handleKeyDownInMenu(keyCode: event.keyCode, flags: event.modifierFlags) else { return event }
                return nil
            }
        } else if openMenus == 0, let token = keyMonitorToken {
            keyDownMonitor.remove(token)
            keyMonitorToken = nil
        }
    }

    /// Fires the panic key if a key down seen while a menu is open matches it.
    /// Returns true when the key down was the panic key and should be swallowed.
    func handleKeyDownInMenu(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard openMenus > 0, let panic = bindings[.panic], attached.contains(.panic),
              panic.shortcut.keyCode == keyCode, panic.shortcut.modifiers == Self.modifiers(flags) else { return false }
        panic.handler()
        return true
    }
}

// MARK: - Carbon seam

/// The Carbon calls, behind a seam so tests never register real global keys.
protocol HotKeyRegistrar: AnyObject {
    /// Called with the hot key ID when one is pressed. Returns whether it was ours.
    var onPress: (@MainActor (UInt32) -> Bool)? { get set }
    /// `RegisterEventHotKey`'s status.
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, exclusive: Bool) -> OSStatus
    func unregister(id: UInt32)
}

/// `RegisterEventHotKey` with one handler on the application event target.
final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    /// "LDLS", so presses of other code's hot keys are passed on.
    nonisolated static let signature: OSType = 0x4C44_4C53
    fileprivate nonisolated static let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "HotKeys")

    var onPress: (@MainActor (UInt32) -> Bool)?
    // nonisolated(unsafe) only so deinit can release them; everything else
    // touches them on the main actor.
    private nonisolated(unsafe) var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private nonisolated(unsafe) var handler: EventHandlerRef?

    deinit {
        for ref in hotKeys.values { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, exclusive: Bool) -> OSStatus {
        let installed = installHandler()
        guard installed == noErr else { return installed }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            exclusive ? OptionBits(kEventHotKeyExclusive) : OptionBits(kEventHotKeyNoOptions),
            &ref
        )
        guard status == noErr, let ref else { return status == noErr ? OSStatus(eventInternalErr) : status }
        hotKeys[id] = ref
        return noErr
    }

    func unregister(id: UInt32) {
        guard let ref = hotKeys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(ref)
    }

    private func installHandler() -> OSStatus {
        guard handler == nil else { return noErr }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Unretained: deinit removes the handler.
        return InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    fileprivate func pressed(_ id: UInt32) -> Bool {
        onPress?(id) ?? false
    }
}

/// Carbon's hot key callback. Carbon dispatches application-target events on
/// the main event loop, so this runs on the main thread, but the C function
/// carries no isolation of its own: check, then enter the main actor.
///
/// Off the main thread it only logs. `userData` is an unretained pointer that
/// is valid only for this call, so it must never be carried across a hop.
private nonisolated func carbonHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == CarbonHotKeyRegistrar.signature else { return OSStatus(eventNotHandledErr) }
    let id = hotKeyID.id
    guard Thread.isMainThread else {
        CarbonHotKeyRegistrar.log.fault("Hot key \(id, privacy: .public) pressed off the main thread; ignored")
        return OSStatus(eventNotHandledErr)
    }
    let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
    let handled = MainActor.assumeIsolated { registrar.pressed(id) }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}
