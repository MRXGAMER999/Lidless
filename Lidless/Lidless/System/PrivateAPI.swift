import CoreGraphics
import CoreFoundation
import Darwin

// Private framework entry points, resolved at run time: a symbol Apple removes
// turns a feature off instead of crashing at launch. Phase 2 declared getters
// only; Phase 3 adds SkyLight's display enable bit for Desk Mode; Phase 4 adds
// the one built-in brightness setter (absolute) and IOAVService for DDC.

nonisolated enum PrivateFramework {
    static let coreDisplay = "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
    static let displayServices = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    /// The first of `names` that `framework` exports, cast to a C function type.
    static func symbol<T>(_ framework: String, _ names: [String], as _: T.Type = T.self) -> T? {
        address(framework, names).map { unsafeBitCast($0, to: T.self) }
    }

    /// Whether `framework` exports any of `names`.
    static func exports(_ framework: String, _ names: [String]) -> Bool {
        address(framework, names) != nil
    }

    private static func address(_ framework: String, _ names: [String]) -> UnsafeMutableRawPointer? {
        // Never closed: these frameworks stay loaded for the life of the process.
        guard let handle = dlopen(framework, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(framework, RTLD_LAZY) else { return nil }
        return names.lazy.compactMap { dlsym(handle, $0) }.first
    }
}

/// CoreDisplay (public framework, no header).
nonisolated enum CoreDisplayAPI {
    typealias InfoDictionaryFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    /// `CoreDisplay_DisplayCreateInfoDictionary` (Create rule): product names,
    /// `IODisplayLocation`, virtual and AirPlay flags, pixel size. Call it only
    /// for IDs in the online list.
    static let infoDictionary: InfoDictionaryFn? =
        PrivateFramework.symbol(PrivateFramework.coreDisplay, ["CoreDisplay_DisplayCreateInfoDictionary"])
}

/// DisplayServices getters, change notifications and the absolute brightness
/// setter. Not loaded by default, hence the dlopen.
nonisolated enum DisplayServicesAPI {
    typealias GetFloatFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias GetBoolFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32
    typealias BoolFn = @convention(c) (CGDirectDisplayID) -> Bool
    /// The observer is pointer-sized (many projects wrongly declare it 32-bit).
    typealias RegisterFn = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32
    typealias UnregisterFn = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?) -> Int32
    typealias SetFloatFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    /// Slider level 0...1. Returns 0 on success, 1000 for displays macOS doesn't dim.
    static let getBrightness: GetFloatFn? = load("DisplayServicesGetBrightness")
    /// SDR white as a fraction of the panel's normal maximum. Same return codes.
    static let getLinearBrightness: GetFloatFn? = load("DisplayServicesGetLinearBrightness")
    static let canChangeBrightness: BoolFn? = load("DisplayServicesCanChangeBrightness")
    /// "Automatically adjust brightness". Returns 0 on success.
    static let autoBrightnessEnabled: GetBoolFn? = load("DisplayServicesAmbientLightCompensationEnabled")
    /// Both always return 0, even when nothing was registered.
    static let registerForBrightnessChanges: RegisterFn? = load("DisplayServicesRegisterForBrightnessChangeNotifications")
    static let unregisterForBrightnessChanges: UnregisterFn? = load("DisplayServicesUnregisterForBrightnessChangeNotifications")
    /// Absolute slider level 0...1, the Control Center slider; it persists after
    /// Lidless quits. Returns 0 either way, so read back with `getBrightness`.
    /// Deliberately not declared: `SetBrightnessSmooth` (it adds a delta),
    /// `SetLinearBrightness` and `SetBrightnessWithType` (unverified).
    static let setBrightness: SetFloatFn? = load("DisplayServicesSetBrightness")

    private static func load<T>(_ name: String) -> T? {
        PrivateFramework.symbol(PrivateFramework.displayServices, [name])
    }
}

/// SkyLight's display list and enable bit, for Desk Mode. Every call goes
/// through `DisplayConfigTransaction`, which owns the safety rules.
nonisolated enum SkyLightAPI {
    /// Must run on a `CGBeginDisplayConfiguration` transaction. The flag is a C `bool`.
    typealias ConfigureDisplayEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    /// Every display WindowServer knows, disabled ones included, plus phantom
    /// IDs (vendor 0, 1×1 px) that must never be sent an enable.
    typealias GetDisplayListFn = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError

    static let configureDisplayEnabled: ConfigureDisplayEnabledFn? =
        resolve(["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"], coreGraphicsAlias: "CGSConfigureDisplayEnabled")
    static let getDisplayList: GetDisplayListFn? =
        resolve(["SLSGetDisplayList", "CGSGetDisplayList"], coreGraphicsAlias: "CGSGetDisplayList")

    static let deskModeCallsPresent: Bool = configureDisplayEnabled != nil && getDisplayList != nil

    /// SkyLight first; then the CGS alias public CoreGraphics exports, which is
    /// always loaded, in case SkyLight's path or names move.
    private static func resolve<T>(_ names: [String], coreGraphicsAlias: String) -> T? {
        if let fn: T = PrivateFramework.symbol(PrivateFramework.skyLight, names) { return fn }
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), coreGraphicsAlias).map { unsafeBitCast($0, to: T.self) }  // RTLD_DEFAULT
    }
}

/// IOAVService: I2C to an external display through the display coprocessor,
/// for DDC/CI on Apple Silicon. Exported by public IOKit without a header
/// (declarations as in MonitorControl and m1ddc, MIT). Only `DDCLink` calls
/// these, on a display's serial queue: each call blocks.
nonisolated enum IOAVServiceAPI {
    static let ioKit = "/System/Library/Frameworks/IOKit.framework/IOKit"

    /// Create rule (+1). Takes a `DCPAVServiceProxy` registry entry
    /// (`io_service_t`, a `mach_port_t`; spelt so this file needs no IOKit import).
    typealias CreateWithServiceFn = @convention(c) (CFAllocator?, mach_port_t) -> Unmanaged<CFTypeRef>?
    /// (service, chip address, offset or data address, buffer, size) → `IOReturn`.
    /// Returns 0xE011xxxx when the coprocessor rejects the link outright.
    typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> kern_return_t

    static let createWithService: CreateWithServiceFn? = PrivateFramework.symbol(ioKit, ["IOAVServiceCreateWithService"])
    static let readI2C: I2CFn? = PrivateFramework.symbol(ioKit, ["IOAVServiceReadI2C"])
    static let writeI2C: I2CFn? = PrivateFramework.symbol(ioKit, ["IOAVServiceWriteI2C"])

    static let isAvailable: Bool = createWithService != nil && readI2C != nil && writeI2C != nil
}
