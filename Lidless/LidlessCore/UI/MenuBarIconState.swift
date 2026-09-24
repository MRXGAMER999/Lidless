import Foundation

/// Which glyph the menu bar icon shows.
public enum MenuBarIconState: Sendable, Equatable, CaseIterable {
    /// Outline laptop.
    case normal
    /// Laptop with a filled screen: the built-in screen is off.
    case deskMode
    /// Laptop with a small sun in the screen: brightness is above normal.
    case boost

    /// Picks the glyph. Desk Mode wins over Boost, because a boosted screen
    /// that is switched off shows nothing.
    ///
    /// - Parameters:
    ///   - desk: Desk Mode is on, or switching on.
    ///   - boosted: The built-in slider is in the Boost range.
    ///   - iconShowsState: Settings › "Icon shows what's on". When off, the
    ///     icon always shows the normal glyph.
    public static func state(desk: Bool, boosted: Bool, iconShowsState: Bool) -> MenuBarIconState {
        guard iconShowsState else { return .normal }
        if desk { return .deskMode }
        if boosted { return .boost }
        return .normal
    }
}
