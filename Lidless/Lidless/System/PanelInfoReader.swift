import Foundation
import IOKit
import LidlessCore

/// Reads the built-in panel's brightness constants from the device tree.
/// About 3 ms, so callers read it once and cache it.
enum PanelInfoReader {
    static func read() -> PanelBrightnessInfo {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/backlight")
        // No node (a desktop Mac, or a model that names it differently): every field stays nil.
        guard entry != IO_OBJECT_NULL else { return PanelBrightnessInfo() }
        defer { IOObjectRelease(entry) }

        var properties: [String: Data] = [:]
        for key in PanelBrightnessInfo.Key.all {
            let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            if let data = value as? Data {
                properties[key] = data
            }
        }
        return PanelBrightnessInfo(backlightProperties: properties)
    }
}
