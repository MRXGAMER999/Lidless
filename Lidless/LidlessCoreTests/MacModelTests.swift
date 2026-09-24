import Testing
@testable import LidlessCore

struct MacModelTests {
    @Test(arguments: ["Mac15,3", "Mac15,12", "Mac15,13"])
    func `entry M3 laptops block Desk Mode`(identifier: String) {
        #expect(MacModel.blocksDeskMode(identifier))
    }

    @Test(arguments: ["Mac15,6", "Mac16,12", "Mac17,2", "Mac17,5", "Mac17,9", "MacBookPro18,3", "VirtualMac2,1", nil] as [String?])
    func `other Macs allow Desk Mode`(identifier: String?) {
        #expect(!MacModel.blocksDeskMode(identifier))
    }
}
