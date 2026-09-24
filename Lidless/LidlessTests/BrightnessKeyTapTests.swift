import LidlessCore
import Testing
@testable import Lidless

// Only the pure parts: a real tap needs Input Monitoring and real key presses.

@MainActor
struct BrightnessKeyTapTests {
    /// `data1` as macOS builds it for an aux control button.
    private static func data1(keyType: Int, state: Int, isRepeat: Bool = false) -> Int {
        keyType << 16 | state << 8 | (isRepeat ? 1 : 0)
    }

    private static let down = 0x0A, up = 0x0B, auxButtons: Int16 = 8

    @Test func `brightness up and down key downs are presses`() {
        #expect(BrightnessKeyTap.press(subtype: Self.auxButtons, data1: Self.data1(keyType: 2, state: Self.down)) == .init(key: .up, isRepeat: false))
        #expect(BrightnessKeyTap.press(subtype: Self.auxButtons, data1: Self.data1(keyType: 3, state: Self.down)) == .init(key: .down, isRepeat: false))
    }

    @Test func `auto repeats are presses too`() {
        #expect(BrightnessKeyTap.press(subtype: Self.auxButtons, data1: Self.data1(keyType: 2, state: Self.down, isRepeat: true)) == .init(key: .up, isRepeat: true))
        #expect(BrightnessKeyTap.press(subtype: Self.auxButtons, data1: Self.data1(keyType: 3, state: Self.down, isRepeat: true)) == .init(key: .down, isRepeat: true))
    }

    @Test(arguments: [2, 3])
    func `key ups are ignored`(keyType: Int) {
        #expect(BrightnessKeyTap.press(subtype: Self.auxButtons, data1: Self.data1(keyType: keyType, state: Self.up)) == nil)
    }

    /// Sound up/down, mute, play, next, previous, keyboard illumination up.
    @Test(arguments: [0, 1, 7, 16, 17, 18, 21])
    func `other aux keys are ignored`(keyType: Int) {
        #expect(BrightnessKeyTap.press(subtype: Self.auxButtons, data1: Self.data1(keyType: keyType, state: Self.down)) == nil)
    }

    /// Subtype 0 is `NX_SUBTYPE_DEFAULT`, 1 the power key, 7 mouse buttons.
    @Test(arguments: [Int16(0), 1, 7])
    func `other subtypes are ignored`(subtype: Int16) {
        #expect(BrightnessKeyTap.press(subtype: subtype, data1: Self.data1(keyType: 2, state: Self.down)) == nil)
    }

    @Test func `bits above the key type are ignored`() {
        let data1 = 0x7FFF << 32 | Self.data1(keyType: 2, state: Self.down)
        #expect(BrightnessKeyTap.press(subtype: Self.auxButtons, data1: data1) == .init(key: .up, isRepeat: false))
    }

    @Test func `a grant is granted whatever came before`() {
        for hidDenied in [false, true] {
            for history in [false, true] {
                #expect(BrightnessKeyTap.permission(listenAccess: true, hidDenied: hidDenied, askedOrGranted: history) == .granted)
            }
        }
    }

    @Test func `never asked is not determined`() {
        #expect(BrightnessKeyTap.permission(listenAccess: false, hidDenied: false, askedOrGranted: false) == .notDetermined)
    }

    @Test func `switched off in Settings is denied`() {
        #expect(BrightnessKeyTap.permission(listenAccess: false, hidDenied: true, askedOrGranted: false) == .denied)
    }

    /// An ad-hoc signed update is a new app to TCC: the old grant is gone while
    /// Settings may still show Lidless as allowed.
    @Test func `a grant lost after asking or holding it is denied`() {
        #expect(BrightnessKeyTap.permission(listenAccess: false, hidDenied: false, askedOrGranted: true) == .denied)
    }
}
