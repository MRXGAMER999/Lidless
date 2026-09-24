import CoreGraphics
import Foundation
import LidlessCore

/// The interpreting half of `LiveDisplayReader`: raw getter results in,
/// `DisplayFacts` out. Kept free of OS calls so tests can feed it readings from
/// displays this Mac doesn't have.
nonisolated enum DisplayReadingHelpers {
    /// `kDisplayModeNativeFlag` (IOGraphicsTypes.h), which doesn't import into Swift.
    static let nativeModeFlag: UInt32 = 0x0200_0000

    /// Keys of the CoreDisplay info dictionary.
    enum InfoKey {
        static let productName = "DisplayProductName"
        static let pixelWidth = "kCGDisplayPixelWidth"
        static let pixelHeight = "kCGDisplayPixelHeight"
        static let isVirtualDevice = "kCGDisplayIsVirtualDevice"
        static let isAirPlay = "kCGDisplayIsAirPlay"
        static let ioLocation = "IODisplayLocation"
    }

    struct ModeSize: Equatable {
        var pixelWidth: Int
        var pixelHeight: Int
        var ioFlags: UInt32 = 0
    }

    struct PixelSize: Equatable {
        var width: Int
        var height: Int
    }

    /// What `NSScreen` knows about a display; only displays with a screen have one.
    struct ScreenReading: Equatable {
        var name: String?
        var potentialHeadroom: Double
        var referenceHeadroom: Double
        var maximumFramesPerSecond: Int
    }

    /// Everything read for one display ID, before interpretation.
    struct RawDisplay {
        var displayID: CGDirectDisplayID
        var uuid: String?
        var vendor: UInt32 = 0
        var model: UInt32 = 0
        var serial: UInt32 = 0
        var isBuiltIn: boolean_t = 0
        var isOnline: boolean_t = 0
        var isActive: boolean_t = 0
        var isAsleep: boolean_t = 0
        var isMain: boolean_t = 0
        var isInMirrorSet: boolean_t = 0
        var mirrorsDisplay: CGDirectDisplayID = 0
        var originX: Double = 0
        var info: [String: Any] = [:]
        var modes: [ModeSize] = []
        var currentMode: ModeSize?
        var currentRefreshRate: Double?
        var screen: ScreenReading?
        var canChangeBrightness = false
    }

    static func facts(_ raw: RawDisplay, preferredLanguages: [String]) -> DisplayFacts {
        let size = nativeSize(modes: raw.modes, info: raw.info, current: raw.currentMode)
        return DisplayFacts(
            displayID: raw.displayID,
            uuid: panelUUID(raw.uuid),
            vendor: raw.vendor,
            model: raw.model,
            serial: raw.serial,
            isBuiltIn: isTrue(raw.isBuiltIn),
            isOnline: isTrue(raw.isOnline),
            isActive: isTrue(raw.isActive),
            isAsleep: isTrue(raw.isAsleep),
            isMain: isTrue(raw.isMain),
            isInMirrorSet: isTrue(raw.isInMirrorSet),
            mirrorsDisplay: raw.mirrorsDisplay,
            originX: raw.originX,
            screenName: raw.screen?.name,
            productName: productName(raw.info, preferredLanguages: preferredLanguages),
            nativePixelWidth: size.width,
            nativePixelHeight: size.height,
            refreshRate: refreshRate(currentMode: raw.currentRefreshRate, screenMaximumFramesPerSecond: raw.screen?.maximumFramesPerSecond),
            isVirtualDevice: flag(raw.info, InfoKey.isVirtualDevice),
            isAirPlay: flag(raw.info, InfoKey.isAirPlay),
            ioLocation: raw.info[InfoKey.ioLocation] as? String,
            potentialHeadroom: raw.screen?.potentialHeadroom ?? 1,
            referenceHeadroom: raw.screen?.referenceHeadroom ?? 0,
            canChangeBrightnessNatively: raw.canChangeBrightness
        )
    }

    /// CG's `boolean_t` getters return -1 for an ID they don't know, so only 1 is true.
    static func isTrue(_ value: boolean_t) -> Bool {
        value == 1
    }

    /// Empty slots report an all-zero UUID (or none): no panel behind them.
    static func panelUUID(_ uuid: String?) -> String? {
        guard let uuid, uuid.contains(where: { $0 != "0" && $0 != "-" }) else { return nil }
        return uuid
    }

    /// The native mode is flagged; the current mode is usually scaled and the
    /// largest mode isn't native either (3600×2338 on a 3024×1964 panel). TVs and
    /// virtual displays may flag nothing, hence the fallbacks.
    static func nativeSize(modes: [ModeSize], info: [String: Any], current: ModeSize?) -> PixelSize {
        let native = modes
            .filter { $0.ioFlags & nativeModeFlag != 0 && $0.pixelWidth > 0 && $0.pixelHeight > 0 }
            .max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
        if let native {
            return PixelSize(width: native.pixelWidth, height: native.pixelHeight)
        }
        if let width = (info[InfoKey.pixelWidth] as? NSNumber)?.intValue,
           let height = (info[InfoKey.pixelHeight] as? NSNumber)?.intValue,
           width > 1, height > 1 {
            return PixelSize(width: width, height: height)
        }
        return PixelSize(width: current?.pixelWidth ?? 0, height: current?.pixelHeight ?? 0)
    }

    /// Some panels and variable-refresh modes report 0 for the current mode.
    static func refreshRate(currentMode: Double?, screenMaximumFramesPerSecond: Int?) -> Double? {
        if let rate = currentMode, rate.isFinite, rate > 0 { return rate }
        if let fps = screenMaximumFramesPerSecond, fps > 0 { return Double(fps) }
        return nil
    }

    /// `DisplayProductName` is usually keyed by locale ("en_US", "de_DE"), sometimes
    /// a plain string, and empty for placeholders.
    static func productName(_ info: [String: Any], preferredLanguages: [String]) -> String? {
        switch info[InfoKey.productName] {
        case let names as [String: String]:
            // Sorted so the no-match fallback doesn't depend on hash order.
            let keys = names.keys.sorted()
            let order = Bundle.preferredLocalizations(from: keys, forPreferences: preferredLanguages) + ["en_US"] + keys
            return order.lazy.compactMap { names[$0].flatMap(nonEmpty) }.first
        case let name as String:
            return nonEmpty(name)
        default:
            return nil
        }
    }

    static func flag(_ info: [String: Any], _ key: String) -> Bool {
        (info[key] as? NSNumber)?.boolValue ?? false
    }

    private static func nonEmpty(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
