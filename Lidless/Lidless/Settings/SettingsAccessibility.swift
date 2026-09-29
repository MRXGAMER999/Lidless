import AppKit
import Combine
import SwiftUI

/// Increase Contrast and Reduce Transparency as macOS has them now, kept live.
///
/// The Settings and onboarding windows force the plain light appearance, so
/// SwiftUI can't learn about Increase Contrast from the window's appearance.
/// This reads `NSWorkspace` and follows its change notification instead;
/// `settingsAccessibilityOptions()` hands the result to the views.
final class AccessibilityDisplayOptions: ObservableObject {
    nonisolated struct Snapshot: Equatable, Sendable {
        var increaseContrast = false
        var reduceTransparency = false
    }

    static let shared = AccessibilityDisplayOptions()

    @Published private(set) var current: Snapshot

    private let read: () -> Snapshot
    private var subscription: AnyCancellable?

    /// - Parameters:
    ///   - read: The system settings (tests pass a fake).
    ///   - notificationCenter: Where `accessibilityDisplayOptionsDidChangeNotification` arrives.
    init(
        read: @escaping () -> Snapshot = AccessibilityDisplayOptions.system,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.read = read
        current = read()
        // NSWorkspace posts it on the main thread.
        subscription = notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let snapshot = read()
        // @Published fires on every set; only a real change should redraw the windows.
        if snapshot != current { current = snapshot }
    }

    nonisolated static func system() -> Snapshot {
        let workspace = NSWorkspace.shared
        return Snapshot(
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency
        )
    }
}

extension View {
    /// Gives the Settings and onboarding views the live Increase Contrast and
    /// Reduce Transparency settings through SwiftUI's own environment values
    /// (`colorSchemeContrast`, `accessibilityReduceTransparency`), so views read
    /// them the usual way. Changing either redraws the window, so the tokens'
    /// high-contrast variants apply without reopening it.
    func settingsAccessibilityOptions(_ options: AccessibilityDisplayOptions = .shared) -> some View {
        modifier(AccessibilityDisplayEnvironment(options: options))
    }
}

private struct AccessibilityDisplayEnvironment: ViewModifier {
    @ObservedObject var options: AccessibilityDisplayOptions

    func body(content: Content) -> some View {
        content
            .environment(\._colorSchemeContrast, options.current.increaseContrast ? .increased : .standard)
            .environment(\._accessibilityReduceTransparency, options.current.reduceTransparency)
    }
}

/// The Settings and onboarding window background. With Reduce Transparency,
/// an opaque paper (the design's wash over white) instead of the blur, so
/// nothing behind the window shows through.
struct SettingsBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            ZStack {
                Palette.white
                Palette.settingsWindowBg
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else {
            SettingsWindowBackground()
        }
    }
}

/// Increase Contrast for a light surface in Settings and onboarding that the
/// shared tokens don't cover: a 1 pt ring in the method cards' high-contrast
/// border colour. Draws nothing at standard contrast, so the default look is
/// the boards'.
struct IncreasedContrastRing<S: InsettableShape>: View {
    let shape: S

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if contrast == .increased {
            shape
                .strokeBorder(Palette.methodCardBorder, lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Increase Contrast on the dark heroes: a 1 pt light ring around a capsule
/// (the onboarding status pill). Nothing at standard contrast.
struct IncreasedContrastRingOnDark<S: InsettableShape>: View {
    let shape: S

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if contrast == .increased {
            shape
                .strokeBorder(Palette.onDarkGhostBorder, lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
