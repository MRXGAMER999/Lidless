import Foundation

/// How this process was launched, read once from the environment and arguments.
nonisolated struct AppEnvironment: Equatable, Sendable {
    /// Hosted unit tests load the app as their test host.
    var isRunningTests: Bool
    /// Xcode previews run the app itself as the preview host.
    var isRunningForPreviews: Bool
    /// `LIDLESS_SAFE_MODE=1`: start without any UI.
    var isSafeMode: Bool
    /// `-LidlessSample deskSetup|onTheGo|deskModeOn`; nil when absent. A present
    /// flag with an unknown or missing value means deskSetup.
    var sample: SampleScenario?
    /// `-LidlessShowPopover YES`: open the popover right after launch, for screenshots.
    var showsPopoverAtLaunch: Bool

    /// When false the app creates no status item and no windows, so a test
    /// host, preview host or safe-mode launch has no visible side effects.
    var showsUserInterface: Bool { !isRunningTests && !isRunningForPreviews && !isSafeMode }

    /// Where the stores get their data. Only a normal launch with UI reads the
    /// system; tests (both test targets are hosted in the app), previews and
    /// safe mode read nothing from it.
    var dataSource: DataSource {
        sample.map(DataSource.sample) ?? (showsUserInterface ? .live : .sample(.deskSetup))
    }

    nonisolated enum DataSource: Equatable, Sendable {
        case live
        case sample(SampleScenario)
    }

    init(environment: [String: String], arguments: [String]) {
        isRunningTests = environment["XCTestConfigurationFilePath"] != nil
        isRunningForPreviews = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        isSafeMode = environment["LIDLESS_SAFE_MODE"] == "1"
        sample = arguments.contains("-LidlessSample")
            ? Self.value(after: "-LidlessSample", in: arguments).flatMap(SampleScenario.init(rawValue:)) ?? .deskSetup
            : nil
        showsPopoverAtLaunch = Self.value(after: "-LidlessShowPopover", in: arguments).map(Self.isTrue) ?? false
    }

    static let current = AppEnvironment(
        environment: ProcessInfo.processInfo.environment,
        arguments: ProcessInfo.processInfo.arguments
    )

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func isTrue(_ value: String) -> Bool {
        ["1", "yes", "true"].contains(value.lowercased())
    }
}

/// The design canvas states the app can start in instead of live data.
nonisolated enum SampleScenario: String, CaseIterable, Sendable {
    case deskSetup
    case onTheGo
    case deskModeOn

    @MainActor
    func makeModel() -> AppModel {
        switch self {
        case .deskSetup: SampleData.deskSetup()
        case .onTheGo: SampleData.onTheGo()
        case .deskModeOn: SampleData.deskModeOn()
        }
    }
}
