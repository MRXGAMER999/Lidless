import Foundation
import IOKit

/// The Mac's model identifier, such as "Mac17,9".
enum MachineInfo {
    /// Read once; nil when every source is unreadable. `hw.target` is not a
    /// fallback: on macOS it names the board ("J714sAP"), not the model.
    static let modelIdentifier: String? =
        sysctlString("hw.model") ?? sysctlString("hw.product") ?? platformExpertModel()

    /// Text up to the first NUL; nil when that is empty.
    static func string(nulTerminated bytes: [UInt8]) -> String? {
        let text = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return string(nulTerminated: Array(bytes.prefix(size)))
    }

    private static func platformExpertModel() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard let data = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data
        else { return nil }
        return string(nulTerminated: [UInt8](data))
    }
}
