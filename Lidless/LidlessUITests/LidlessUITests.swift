import XCTest

final class LidlessUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesWithSampleData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LidlessSample", "deskSetup"]
        // Without safe mode the app puts its item in the menu bar, as it does for people.
        app.launchEnvironment["LIDLESS_SAFE_MODE"] = nil
        app.launch()

        // A menu bar app stays in the background, so either running state counts.
        XCTAssertTrue([.runningForeground, .runningBackground].contains(app.state), "state: \(app.state.rawValue)")

        app.terminate()
    }
}
