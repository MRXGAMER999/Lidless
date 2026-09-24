import AppKit
import LidlessCore

/// Reads every online display through getters only: CoreGraphics, `NSScreen`,
/// the CoreDisplay info dictionary and DisplayServicesCanChangeBrightness.
/// Never IOKit's display services (there are none on Apple Silicon), never DDC.
final class LiveDisplayReader: DisplayReader {
    /// Far above what a Mac can drive; only guards against a bogus count.
    private static let maxDisplays: UInt32 = 32

    init() {}

    func snapshot() -> [DisplayFacts] {
        let screens = Self.screenReadings()
        let languages = Locale.preferredLanguages
        return Self.onlineDisplayIDs().map { id in
            DisplayReadingHelpers.facts(Self.read(id, screen: screens[id]), preferredLanguages: languages)
        }
    }

    /// The online list, not the active one: asleep displays and mirror followers
    /// drop out of the active list but still count for Desk Mode.
    static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        let capacity = min(count, maxDisplays)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        guard CGGetOnlineDisplayList(capacity, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(min(count, capacity))))
    }

    private static func read(_ id: CGDirectDisplayID, screen: DisplayReadingHelpers.ScreenReading?) -> DisplayReadingHelpers.RawDisplay {
        let isOnline = CGDisplayIsOnline(id)
        // CoreDisplay and DisplayServices misbehave for IDs that went away since the list was read.
        let info = isOnline == 1 ? CoreDisplayAPI.infoDictionary?(id)?.takeRetainedValue() as? [String: Any] : nil
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
        let current = CGDisplayCopyDisplayMode(id)
        return DisplayReadingHelpers.RawDisplay(
            displayID: id,
            uuid: CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String },
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            serial: CGDisplaySerialNumber(id),
            isBuiltIn: CGDisplayIsBuiltin(id),
            isOnline: isOnline,
            isActive: CGDisplayIsActive(id),
            isAsleep: CGDisplayIsAsleep(id),
            isMain: CGDisplayIsMain(id),
            isInMirrorSet: CGDisplayIsInMirrorSet(id),
            mirrorsDisplay: CGDisplayMirrorsDisplay(id),
            originX: Double(CGDisplayBounds(id).minX),
            info: info ?? [:],
            modes: modes.map(modeSize),
            currentMode: current.map(modeSize),
            currentRefreshRate: current?.refreshRate,
            screen: screen,
            canChangeBrightness: isOnline == 1 && (DisplayServicesAPI.canChangeBrightness?(id) ?? false)
        )
    }

    private static func modeSize(_ mode: CGDisplayMode) -> DisplayReadingHelpers.ModeSize {
        DisplayReadingHelpers.ModeSize(pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight, ioFlags: mode.ioFlags)
    }

    /// Built once per snapshot: AppKit rebuilds its screens on every reconfiguration.
    private static func screenReadings() -> [CGDirectDisplayID: DisplayReadingHelpers.ScreenReading] {
        var readings: [CGDirectDisplayID: DisplayReadingHelpers.ScreenReading] = [:]
        for screen in NSScreen.screens {
            guard let id = displayID(of: screen) else { continue }
            readings[id] = DisplayReadingHelpers.ScreenReading(
                name: screen.localizedName,
                potentialHeadroom: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue),
                referenceHeadroom: Double(screen.maximumReferenceExtendedDynamicRangeColorComponentValue),
                maximumFramesPerSecond: screen.maximumFramesPerSecond
            )
        }
        return readings
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        if #available(macOS 26.0, *) {
            return screen.cgDirectDisplayID
        }
        return screenNumber(of: screen)
    }

    /// macOS 12–25's way to the ID. Its own function so tests on 26 and later,
    /// which always take the branch above, still check it.
    static func screenNumber(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
