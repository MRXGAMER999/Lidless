import Foundation
import Testing
@testable import LidlessCore

struct DeskModeStateTests {
    @Test(arguments: [
        (DeskModeState.off, false, true, false),
        (.on(since: .distantPast, trigger: .manual), true, true, false),
        (.on(since: .distantPast, trigger: .automatic(displayName: "Studio Display")), true, true, false),
        (.switching(toOn: true), true, true, true),
        (.switching(toOn: false), false, true, true),
        (.unavailable(.needsDisplay), false, false, false),
        (.unavailable(.lidClosed), false, false, false),
        (.unavailable(.unsupportedMac), false, false, false),
        (.unavailable(.unsupportedSystem), false, false, false),
    ])
    func `flags follow the state`(state: DeskModeState, isOn: Bool, isAvailable: Bool, isSwitching: Bool) {
        #expect(state.isOn == isOn)
        #expect(state.isAvailable == isAvailable)
        #expect(state.isSwitching == isSwitching)
    }
}
