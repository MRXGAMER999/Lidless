import Testing
@testable import LidlessCore

struct DisplayClassifierTests {
    typealias Fixtures = DisplayFixtures

    // MARK: Kind

    @Test(arguments: [UInt32(3), 4, 5])
    func `an empty framebuffer slot is a placeholder`(id: UInt32) {
        #expect(DisplayClassifier.kind(of: Fixtures.emptySlot(id)) == .placeholder)
    }

    @Test func `the unkn virt stand-in is a placeholder even when it claims to be built in`() {
        #expect(DisplayClassifier.kind(of: Fixtures.standIn) == .placeholder)
    }

    @Test(arguments: [nil, "00000000-0000-0000-0000-000000000000"] as [String?])
    func `a nil or zero UUID is a placeholder`(uuid: String?) {
        var facts = Fixtures.lg
        facts.uuid = uuid
        #expect(DisplayClassifier.kind(of: facts) == .placeholder)
    }

    @Test func `an offline display is a placeholder`() {
        var facts = Fixtures.lg
        facts.isOnline = false
        #expect(DisplayClassifier.kind(of: facts) == .placeholder)
    }

    @Test func `this Mac's built-in panel is built in`() {
        #expect(DisplayClassifier.kind(of: Fixtures.builtIn) == .builtIn)
    }

    @Test func `the LG over HDMI is a physical external`() {
        #expect(DisplayClassifier.kind(of: Fixtures.lg) == .physicalExternal)
    }

    /// M1 Pro names the framebuffer class AppleCLCD2; only the node name is stable.
    @Test func `an AppleCLCD2 framebuffer path is still physical`() {
        var facts = Fixtures.lg
        facts.ioLocation = "IOService:/AppleARMPE/arm-io@10F00000/AppleT600xIO/dispext0@A0000000/AppleCLCD2"
        #expect(DisplayClassifier.kind(of: facts) == .physicalExternal)
    }

    /// The virtual flag reads 1 on real monitors around display sleep.
    @Test func `the virtual flag on a dispext path stays physical`() {
        var facts = Fixtures.lg
        facts.isVirtualDevice = true
        #expect(DisplayClassifier.kind(of: facts) == .physicalExternal)
    }

    @Test func `AirPlay is virtual`() {
        var facts = Fixtures.lg
        facts.isAirPlay = true
        #expect(DisplayClassifier.kind(of: facts) == .virtual)
    }

    @Test(arguments: [nil, "", "IOService:/AppleARMPE/arm-io@10F00000/AppleSoCIO/disp0@88000000/IOMobileFramebufferShim"] as [String?])
    func `an external without a dispext framebuffer is virtual`(ioLocation: String?) {
        var facts = Fixtures.sidecar
        facts.ioLocation = ioLocation
        #expect(DisplayClassifier.kind(of: facts) == .virtual)
    }

    // MARK: Role

    @Test(arguments: [
        (true, UInt32(0), DisplayDescriptor.Role.main),
        (false, 0, .extended),
        (false, 1, .mirrored),
        (true, 1, .mirrored),
    ])
    func `role follows main and mirroring`(isMain: Bool, mirrorsDisplay: UInt32, expected: DisplayDescriptor.Role) {
        var facts = Fixtures.lg
        facts.isMain = isMain
        facts.mirrorsDisplay = mirrorsDisplay
        #expect(DisplayClassifier.role(of: facts) == expected)
    }

    /// The display others mirror is in the mirror set but follows nobody.
    @Test func `a mirror source keeps its role`() {
        var facts = Fixtures.lg
        facts.isInMirrorSet = true
        #expect(DisplayClassifier.role(of: facts) == .main)
    }

    // MARK: Capabilities

    @Test(arguments: [
        (DisplayKind.builtIn, 16.0, true),
        (.builtIn, 4, true),
        (.builtIn, 2, false),
        (.builtIn, 1, false),
        (.physicalExternal, 16, false),
    ])
    func `boost needs an XDR built-in panel`(kind: DisplayKind, potentialHeadroom: Double, expected: Bool) {
        var facts = Fixtures.builtIn
        facts.potentialHeadroom = potentialHeadroom
        #expect(DisplayClassifier.supportsBoost(facts, kind: kind) == expected)
    }

    @Test(arguments: [
        (DisplayKind.builtIn, true, DisplayDescriptor.BrightnessControl.native),
        (.physicalExternal, false, .ddc),
        (.virtual, false, .software),
        (.builtIn, false, .none),
        (.placeholder, false, .none),
        // An Apple-made external such as the Studio Display.
        (.physicalExternal, true, .native),
    ])
    func `brightness control depends on the kind`(kind: DisplayKind, canChange: Bool, expected: DisplayDescriptor.BrightnessControl) {
        var facts = Fixtures.lg
        facts.canChangeBrightnessNatively = canChange
        #expect(DisplayClassifier.brightnessControl(facts, kind: kind) == expected)
    }

    /// Asleep displays and mirror followers can leave the active list but still count.
    @Test(arguments: [
        (true, false, false, true),
        (false, true, false, true),
        (false, false, true, true),
        (false, false, false, false),
    ])
    func `a wired external is usable while active, asleep or mirrored`(isActive: Bool, isAsleep: Bool, isInMirrorSet: Bool, expected: Bool) {
        var facts = Fixtures.lg
        facts.isActive = isActive
        facts.isAsleep = isAsleep
        facts.isInMirrorSet = isInMirrorSet
        #expect(DisplayClassifier.isUsableExternal(facts, kind: DisplayClassifier.kind(of: facts)) == expected)
    }

    @Test(arguments: [DisplayKind.virtual, .builtIn, .placeholder])
    func `only a physical external is usable`(kind: DisplayKind) {
        #expect(!DisplayClassifier.isUsableExternal(Fixtures.lg, kind: kind))
    }
}
