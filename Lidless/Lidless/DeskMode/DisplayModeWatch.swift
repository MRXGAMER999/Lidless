import CoreGraphics
import Foundation
import LidlessCore
import os

/// Notices when a Desk Mode switch makes macOS change another display's mode.
///
/// macOS keeps separate settings for "external alone" and "MacBook + external".
/// When they differ, WindowServer switches the external's mode inside the same
/// transaction, and the monitor goes dark for a moment while its signal
/// resyncs. Nothing in the transaction can prevent that (fade effects are
/// rejected on macOS 27), so this only logs it and lets the user know once.
/// Reads modes only; never changes a display.
final class DisplayModeWatch: DisplayModeWatching {
    /// The switch happens inside the transaction, but this process learns the
    /// new modes from notifications that land a moment after it returns.
    static let settleDelay: TimeInterval = 1.5

    /// Called on the main actor after a switch that changed another display's mode.
    var onModeSwitch: (() -> Void)?

    private var before: [UInt32: DisplayModeInfo] = [:]
    /// A newer switch makes an older comparison stale.
    private var generation = 0
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "DeskMode")

    func willSwitch() {
        generation += 1
        before = Self.currentModes()
    }

    func didSwitch() {
        let expected = generation
        let before = self.before
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == expected else { return }
                self.compare(before, Self.currentModes())
            }
        }
    }

    private func compare(_ before: [UInt32: DisplayModeInfo], _ after: [UInt32: DisplayModeInfo]) {
        let changes = DisplayModeChange.changed(before: before, after: after)
        guard !changes.isEmpty else { return }
        for change in changes {
            log.notice("Display \(change.id, privacy: .public) switched mode with the built-in screen: \(change.from.summary, privacy: .public) → \(change.to.summary, privacy: .public); it goes dark while it resyncs")
        }
        onModeSwitch?()
    }

    private static func currentModes() -> [UInt32: DisplayModeInfo] {
        var modes: [UInt32: DisplayModeInfo] = [:]
        for id in DisplayConfigTransaction.onlineIDs() {
            guard let mode = CGDisplayCopyDisplayMode(id) else { continue }
            modes[id] = DisplayModeInfo(
                modeID: mode.ioDisplayModeID,
                width: mode.width,
                height: mode.height,
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate
            )
        }
        return modes
    }
}
