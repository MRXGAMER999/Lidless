import Foundation

/// What CoreGraphics, NSScreen, CoreDisplay and DisplayServices report about
/// one display ID. The app's reader fills it in; tests build it by hand.
public struct DisplayFacts: Sendable, Equatable {
    public var displayID: UInt32
    /// Display UUID (ColorSync). Nil for empty framebuffer slots.
    public var uuid: String?
    /// EDID vendor, product and serial numbers.
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    /// CoreGraphics flags, compared with `== 1`: unknown IDs return -1.
    public var isBuiltIn: Bool
    public var isOnline: Bool
    public var isActive: Bool
    public var isAsleep: Bool
    public var isMain: Bool
    public var isInMirrorSet: Bool
    /// The display this one mirrors, or 0 when it isn't a mirror follower.
    public var mirrorsDisplay: UInt32
    /// Left edge in global display coordinates, for left-to-right ordering.
    public var originX: Double
    /// `NSScreen.localizedName`; nil when the display has no screen (a mirror
    /// follower, or the built-in while the lid is closed).
    public var screenName: String?
    /// CoreDisplay's product name in the user's language; nil when missing or empty.
    public var productName: String?
    /// Resolution of the mode macOS flags as native, in pixels.
    public var nativePixelWidth: Int
    public var nativePixelHeight: Int
    /// Refresh rate of the current mode in Hz; nil when unknown.
    public var refreshRate: Double?
    /// CoreDisplay's `kCGDisplayIsVirtualDevice` and `kCGDisplayIsAirPlay`.
    public var isVirtualDevice: Bool
    public var isAirPlay: Bool
    /// CoreDisplay's `IODisplayLocation`: the framebuffer's IORegistry path.
    public var ioLocation: String?
    /// EDR headroom the display can reach: 16 on XDR panels, 1 on SDR monitors.
    public var potentialHeadroom: Double
    /// Above 0 while a reference preset is active.
    public var referenceHeadroom: Double
    /// `DisplayServicesCanChangeBrightness`: macOS dims this display itself.
    public var canChangeBrightnessNatively: Bool

    public init(
        displayID: UInt32,
        uuid: String? = nil,
        vendor: UInt32 = 0,
        model: UInt32 = 0,
        serial: UInt32 = 0,
        isBuiltIn: Bool = false,
        isOnline: Bool = true,
        isActive: Bool = true,
        isAsleep: Bool = false,
        isMain: Bool = false,
        isInMirrorSet: Bool = false,
        mirrorsDisplay: UInt32 = 0,
        originX: Double = 0,
        screenName: String? = nil,
        productName: String? = nil,
        nativePixelWidth: Int = 0,
        nativePixelHeight: Int = 0,
        refreshRate: Double? = nil,
        isVirtualDevice: Bool = false,
        isAirPlay: Bool = false,
        ioLocation: String? = nil,
        potentialHeadroom: Double = 1,
        referenceHeadroom: Double = 0,
        canChangeBrightnessNatively: Bool = false
    ) {
        self.displayID = displayID
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.isBuiltIn = isBuiltIn
        self.isOnline = isOnline
        self.isActive = isActive
        self.isAsleep = isAsleep
        self.isMain = isMain
        self.isInMirrorSet = isInMirrorSet
        self.mirrorsDisplay = mirrorsDisplay
        self.originX = originX
        self.screenName = screenName
        self.productName = productName
        self.nativePixelWidth = nativePixelWidth
        self.nativePixelHeight = nativePixelHeight
        self.refreshRate = refreshRate
        self.isVirtualDevice = isVirtualDevice
        self.isAirPlay = isAirPlay
        self.ioLocation = ioLocation
        self.potentialHeadroom = potentialHeadroom
        self.referenceHeadroom = referenceHeadroom
        self.canChangeBrightnessNatively = canChangeBrightnessNatively
    }
}
