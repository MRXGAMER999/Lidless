import AppKit
import CoreGraphics
import IOKit.hidsystem
import LidlessCore
import os

/// The brightness keys, seen through a listen-only `CGEventTap` on
/// `NX_SYSDEFINED` events (phase4-research §1).
///
/// A press that finds the panel already at 100 % changes nothing, so
/// DisplayServices reports nothing; only the key event itself shows it. The tap
/// needs Input Monitoring, never Accessibility, and `.listenOnly` means it can
/// never delay, change or swallow a key: macOS always handles the key as well.
/// Without the grant the tap is created but receives nothing (Isleta, macOS 27),
/// so `start` checks the grant, not the port.
///
/// Held keys auto-repeat at about 10 Hz and every repeat is delivered as a
/// press, so holding brightness-up at 100 % keeps stepping into Boost; the
/// Boost ramp smooths the steps.
///
/// While running, the tap retains this object (the C callback's `userInfo`):
/// call `stop()` to release it.
final class BrightnessKeyTap: BrightnessKeySource {
    /// Remembers that Lidless asked for, or once held, Input Monitoring. An
    /// ad-hoc signed update is a new app to TCC (its designated requirement is
    /// the cdhash), so System Settings can show Lidless as allowed while this
    /// build has no grant: that is reported as `.denied`, not `.notDetermined`,
    /// so the UI explains the fix instead of offering a prompt that never shows.
    nonisolated static let historyKey = "inputMonitoring.askedOrGranted"

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "BrightnessKeys")
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: (@MainActor (BrightnessKeyPolicy.Key) -> Void)?
    /// The tap's hold on `self` while it runs.
    private var retained: Unmanaged<BrightnessKeyTap>?
    private var requested = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Permission

    var permission: InputMonitoringPermission {
        let granted = CGPreflightListenEventAccess()
        if granted { defaults.set(true, forKey: Self.historyKey) }
        return Self.permission(
            listenAccess: granted,
            // Same TCC service (ListenEvent), but tri-state: tells "switched
            // off in Settings" apart from "never asked". Never prompts.
            hidDenied: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeDenied,
            askedOrGranted: defaults.bool(forKey: Self.historyKey)
        )
    }

    /// Shows the system prompt, at most once per launch. macOS itself shows it
    /// only once per signature; afterwards only System Settings › Privacy &
    /// Security › Input Monitoring grants it, and the app may need a relaunch.
    func requestPermission() {
        guard !requested else { return }
        requested = true
        defaults.set(true, forKey: Self.historyKey)
        let granted = CGRequestListenEventAccess()
        log.info("Input Monitoring requested; granted: \(granted, privacy: .public)")
    }

    /// The status from `CGPreflightListenEventAccess` (`listenAccess`),
    /// `IOHIDCheckAccess` (`hidDenied`) and whether Lidless asked for or held
    /// the grant before.
    nonisolated static func permission(listenAccess: Bool, hidDenied: Bool, askedOrGranted: Bool) -> InputMonitoringPermission {
        if listenAccess { return .granted }
        if hidDenied || askedOrGranted { return .denied }
        return .notDetermined
    }

    // MARK: - Tap

    /// Starts the tap, or replaces the handler when it already runs. False
    /// without Input Monitoring or when the tap can't be created.
    @discardableResult
    func start(handler: @escaping @MainActor (BrightnessKeyPolicy.Key) -> Void) -> Bool {
        if port != nil {
            self.handler = handler
            return true
        }
        guard permission == .granted else { return false }
        let context = Unmanaged.passRetained(self)
        // Head of the session tap: see the keys before another app's consuming
        // tap (MonitorControl, Lunar) can swallow them. `.cghidEventTap` would
        // need root by the header's rules.
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventMask(NX_SYSDEFINED),
            callback: brightnessKeyTapCallback,
            userInfo: context.toOpaque()
        ) else {
            context.release()
            log.error("Brightness key tap not created")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        // The main run loop, so the callback runs on the main thread and can
        // enter the main actor directly. Common modes: keys still arrive while
        // a menu tracks or the slider drags (the policy decides what to ignore).
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        self.handler = handler
        retained = context
        log.info("Brightness key tap started")
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
        handler = nil
        log.info("Brightness key tap stopped")
        // Last: this may free self. The callback runs on this same (main)
        // thread, so none is in flight.
        let context = retained
        retained = nil
        context?.release()
    }

    /// A brightness key down (a first press or an auto-repeat).
    nonisolated struct Press: Equatable, Sendable {
        let key: BrightnessKeyPolicy.Key
        let isRepeat: Bool
    }

    /// Decodes an `NX_SYSDEFINED` event's `subtype` and `data1`: subtype 8
    /// (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`), key type in bits 16–31, key state in
    /// bits 8–15 (0x0A down, 0x0B up), repeat flag in bit 0. Nil for key ups
    /// and every other key.
    nonisolated static func press(subtype: Int16, data1: Int) -> Press? {
        guard subtype == Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS) else { return nil }
        let keyType = Int32((data1 >> 16) & 0xFFFF)
        let keyState = (data1 >> 8) & 0xFF
        guard keyState == 0x0A else { return nil }
        let isRepeat = data1 & 0x1 != 0
        switch keyType {
        case NX_KEYTYPE_BRIGHTNESS_UP: return Press(key: .up, isRepeat: isRepeat)
        case NX_KEYTYPE_BRIGHTNESS_DOWN: return Press(key: .down, isRepeat: isRepeat)
        default: return nil
        }
    }

    // MARK: - Callback (main thread)

    fileprivate func tapDisabled(byTimeout: Bool) {
        guard let port else { return }
        log.notice("Brightness key tap disabled (\(byTimeout ? "timeout" : "user input", privacy: .public)); re-enabling")
        CGEvent.tapEnable(tap: port, enable: true)
    }

    fileprivate func received(_ press: Press) {
        guard handler != nil else { return }
        log.debug("Brightness \(press.key == .up ? "up" : "down", privacy: .public)\(press.isRepeat ? " (repeat)" : "", privacy: .public)")
        handler?(press.key)
    }
}

/// The tap's C callback. The run-loop source is on the main run loop, so this
/// runs on the main thread, but the C function carries no isolation: check,
/// then enter the main actor. `userInfo` is only read inside this call.
private nonisolated func brightnessKeyTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passThrough = Unmanaged.passUnretained(event)
    guard let userInfo, Thread.isMainThread else { return passThrough }
    let tap = Unmanaged<BrightnessKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        let byTimeout = type == .tapDisabledByTimeout
        MainActor.assumeIsolated { tap.tapDisabled(byTimeout: byTimeout) }
    default:
        // Decode here: only the Sendable result crosses into the main actor.
        guard type.rawValue == UInt32(NX_SYSDEFINED), let nsEvent = NSEvent(cgEvent: event),
              let press = BrightnessKeyTap.press(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1) else { break }
        MainActor.assumeIsolated { tap.received(press) }
    }
    return passThrough
}

#if DEBUG
/// UNVERIFIED SPIKE, not wired into the app (phase4-research §1.1, §6).
///
/// Apple keyboards send the brightness keys as key codes 144 (up) and 145
/// (down) unless "Use F1, F2… as standard function keys" is on. If a Carbon hot
/// key on them fires with no modifiers *and* macOS still changes the
/// brightness, "Keep pressing to boost" could work with no permission at all.
/// Nobody has shown either half: the hot key may never fire, or it may take
/// the key away from macOS. Try it from the debugger
/// (`expr CarbonBrightnessKeyExperiment.start()`), press the keys at and below
/// 100 %, and read the "BrightnessKeys" log; `stop()` undoes it.
enum CarbonBrightnessKeyExperiment {
    static let upKeyCode: UInt32 = 144
    static let downKeyCode: UInt32 = 145

    private static var registrar: CarbonHotKeyRegistrar?
    private static let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "BrightnessKeys")

    /// Registers both key codes, non-exclusive and without modifiers. The IDs
    /// are the key codes, which never collide with `HotKeyID`, so each
    /// registrar passes the other's presses on.
    static func start() {
        guard registrar == nil else { return }
        let registrar = CarbonHotKeyRegistrar()
        registrar.onPress = { id in
            guard id == upKeyCode || id == downKeyCode else { return false }
            log.notice("Carbon brightness spike: key code \(id, privacy: .public) fired; check that the native brightness still changed")
            return true
        }
        for code in [upKeyCode, downKeyCode] {
            let status = registrar.register(keyCode: code, modifiers: 0, id: code, exclusive: false)
            log.notice("Carbon brightness spike: key code \(code, privacy: .public) registered, status \(status, privacy: .public)")
        }
        self.registrar = registrar
    }

    static func stop() {
        guard registrar != nil else { return }
        registrar = nil  // Its deinit unregisters both keys.
        log.notice("Carbon brightness spike stopped")
    }
}
#endif
