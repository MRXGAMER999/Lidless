import Foundation
import LidlessCore

/// Values read from the development Mac: a MacBook Pro Mac17,9 with its lid
/// open and an LG ULTRAGEAR on HDMI (design §9).
///
/// Compiled into both LidlessCoreTests and LidlessTests, so the core and the
/// controller tests always check the same hardware.
enum DisplayFixtures {
    static let builtInUUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    static let lgUUID = "3C1C2164-4D1D-42F7-A482-77705FA4713C"

    static let builtIn = DisplayFacts(
        displayID: 1, uuid: builtInUUID, vendor: 0x610, model: 0xA05E, serial: 0xFD62_6D62,
        isBuiltIn: true, originX: 1920, screenName: "Built-in Retina Display", productName: "Color LCD",
        nativePixelWidth: 3024, nativePixelHeight: 1964, refreshRate: 120,
        ioLocation: "IOService:/AppleARMPE/arm-io@10F00000/AppleSoCIO/disp0@88000000/IOMobileFramebufferShim",
        potentialHeadroom: 16, canChangeBrightnessNatively: true
    )

    static let lg = DisplayFacts(
        displayID: 2, uuid: lgUUID, vendor: 0x1E6D, model: 0x5C19, serial: 0x478B1,
        isMain: true, originX: 0, screenName: "LG ULTRAGEAR", productName: "LG ULTRAGEAR",
        nativePixelWidth: 1920, nativePixelHeight: 1080, refreshRate: 144,
        ioLocation: "IOService:/AppleARMPE/arm-io@10F00000/AppleSoCIO/dispext0@B0000000/IOMobileFramebufferShim"
    )

    /// This Mac's online list, which puts the LG first.
    static let thisMac = [lg, builtIn]

    /// An unused external pipe (IDs 3–5), reachable only through SkyLight.
    static func emptySlot(_ id: UInt32) -> DisplayFacts {
        DisplayFacts(
            displayID: id, isOnline: false, isActive: false, nativePixelWidth: 1, nativePixelHeight: 1,
            ioLocation: "IOService:/AppleARMPE/arm-io@10F00000/AppleSoCIO/dispext\(id)@4000000/IOMobileFramebufferShim"
        )
    }

    /// WindowServer's headless stand-in: vendor 'unkn', model 'virt'. It can claim to be built in.
    static let standIn = DisplayFacts(
        displayID: 0x5B81_C5C0, uuid: "E4A5B1C2-0000-4000-8000-000000000001", vendor: 0x756E_6B6E, model: 0x7669_7274,
        isBuiltIn: true, nativePixelWidth: 1920, nativePixelHeight: 1080
    )

    /// An iPad over Sidecar: no DCP framebuffer of its own.
    static let sidecar = DisplayFacts(
        displayID: 9, uuid: "5F3B7A10-1111-4222-8333-444455556666", vendor: 0x610, model: 0xA0B1,
        originX: 3840, screenName: "Sidecar Display (AirPlay)", nativePixelWidth: 2388, nativePixelHeight: 1668,
        refreshRate: 60, isVirtualDevice: true
    )

    static let names = DisplayNames(builtIn: "Built-in Display", unknownExternal: "Display")

    /// `backlight-marketing-table`: 17 little-endian 16.16 values.
    static let marketingTableHex =
        "00000000 00000100 98060200 8e1a0400 2f500800 34d71000 801d2200 0e1c4500 00008c00 "
        + "58eea700 3d6fc900 449ff100 d4d32101 7aa65b01 4e02a101 a034f401 00005802"

    /// The curve's stops in nits, rounded to two decimals.
    static let marketingTableNits = [
        0, 1, 2.03, 4.1, 8.31, 16.84, 34.12, 69.11, 140,
        167.93, 201.43, 241.62, 289.83, 347.65, 417.01, 500.21, 600,
    ]

    /// The raw `IODeviceTree:/backlight` properties Lidless reads.
    static let backlightProperties: [String: Data] = [
        PanelBrightnessInfo.Key.userMaxNits: data(hex: "00005802"),
        PanelBrightnessInfo.Key.outdoorMaxNits: data(hex: "00007a44"),
        PanelBrightnessInfo.Key.peakNits: data(hex: "00004006"),
        PanelBrightnessInfo.Key.curve: data(hex: marketingTableHex),
    ]

    static let panel = PanelBrightnessInfo(backlightProperties: backlightProperties)

    /// Bytes from a hex string; spaces are ignored.
    static func data(hex: String) -> Data {
        let digits = Array(hex.filter { !$0.isWhitespace })
        return Data(stride(from: 0, to: digits.count - 1, by: 2).compactMap { UInt8(String(digits[$0...$0 + 1]), radix: 16) })
    }
}
