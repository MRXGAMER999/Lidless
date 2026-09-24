import CoreGraphics
import CoreFoundation
import Darwin

// Private framework entry points, resolved at run time: a symbol Apple removes
// turns a feature off instead of crashing at launch. Phase 2 declares getters
// only. No setter, configuration or DDC entry point belongs in this file
// before Phase 3.

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

/// SkyLight, for Desk Mode. Phase 2 only checks the calls exist, so no callable
/// type is declared here.
nonisolated enum SkyLightAPI {
    static let deskModeCallsPresent: Bool =
        PrivateFramework.exports(PrivateFramework.skyLight, ["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"])
        && PrivateFramework.exports(PrivateFramework.skyLight, ["SLSGetDisplayList", "CGSGetDisplayList"])
}
