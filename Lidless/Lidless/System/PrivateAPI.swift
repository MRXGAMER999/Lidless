import CoreGraphics
import CoreFoundation
import Darwin

// Private framework entry points, resolved at run time: a symbol Apple removes
// turns a feature off instead of crashing at launch. Phase 2 declared getters
// only; Phase 3 adds SkyLight's display enable bit for Desk Mode. Brightness
// setters wait for Phase 4, and no DDC entry point belongs in this file.

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

/// DisplayServices getters and change notifications. Not loaded by default,
/// hence the dlopen. Setters are deliberately absent until Phase 4.
nonisolated enum DisplayServicesAPI {
    typealias GetFloatFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias GetBoolFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32
    typealias BoolFn = @convention(c) (CGDirectDisplayID) -> Bool
    /// The observer is pointer-sized (many projects wrongly declare it 32-bit).
    typealias RegisterFn = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32
    typealias UnregisterFn = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?) -> Int32

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
