import Foundation

/// Model identifiers ("Mac17,9") that decide what Lidless offers.
public enum MacModel {
    /// Entry-level M3 laptops re-route the built-in panel's display pipe to a
    /// second external display and often can't bring the panel back without a
    /// reboot (BetterDisplay #4723 and #5658; Apple Support 117373).
    /// MacBook Pro 14″ M3, MacBook Air 13″ M3, MacBook Air 15″ M3.
    public static let deskModeBlocked: Set<String> = ["Mac15,3", "Mac15,12", "Mac15,13"]

    public static func blocksDeskMode(_ identifier: String?) -> Bool {
        identifier.map(deskModeBlocked.contains) ?? false
    }
}
