import Foundation
import LidlessCore

/// Lid, power, heat and model, read on demand. Every read is well under 1 ms,
/// so nothing is cached except the constants.
final class LiveSystemReader: SystemReader {
    func lid() -> LidState { LidReader.read() }
    func power() -> PowerSource { PowerReader.read() }
    func thermal() -> ThermalLevel { ThermalLevel(ProcessInfo.processInfo.thermalState) }
    var modelIdentifier: String? { MachineInfo.modelIdentifier }
    /// Presence only: Phase 2 never calls SkyLight.
    var deskModeCallsPresent: Bool { SkyLightAPI.deskModeCallsPresent }
}
