import AppKit
import Carbon.HIToolbox
import Combine
import LidlessCore
import SwiftUI
import Testing
@testable import Lidless

@MainActor
struct AppEnvironmentTests {
    @Test func `the unit test host is detected and shows no UI`() {
        #expect(AppEnvironment.current.isRunningTests)
        #expect(!AppEnvironment.current.showsUserInterface)
    }

    @Test func `the hosting app created no status item`() throws {
        let delegate = try #require(NSApp.delegate as? AppDelegate)
        #expect(delegate.statusItemController == nil)
    }

    @Test func `the hosting app created no system or Desk Mode controller`() throws {
        let delegate = try #require(NSApp.delegate as? AppDelegate)
        #expect(delegate.systemController == nil)
        #expect(delegate.deskModeController == nil)
        #expect(delegate.model.deskMode.requestHandler == nil)
        #expect(AppEnvironment.current.dataSource == .sample(.deskSetup))
    }

    @Test(arguments: [
        (["LIDLESS_SAFE_MODE": "1"], false),
        (["LIDLESS_SAFE_MODE": "0"], true),
        (["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"], false),
        (["XCODE_RUNNING_FOR_PREVIEWS": "1"], false),
        ([:], true),
    ])
    func `UI only outside tests, previews and safe mode`(environment: [String: String], showsUI: Bool) {
        #expect(AppEnvironment(environment: environment, arguments: []).showsUserInterface == showsUI)
    }

    @Test(arguments: [
        (["Lidless", "-LidlessSample", "onTheGo"], SampleScenario?.some(.onTheGo)),
        (["Lidless", "-LidlessSample", "deskModeOn"], .deskModeOn),
        (["Lidless", "-LidlessSample", "deskSetup"], .deskSetup),
        (["Lidless", "-LidlessSample", "nonsense"], .deskSetup),
        (["Lidless", "-LidlessSample"], .deskSetup),
        (["Lidless", "-LidlessSample", "-LidlessShowPopover", "YES"], .deskSetup),
        (["Lidless"], nil),
    ])
    func `sample comes from the launch argument`(arguments: [String], expected: SampleScenario?) {
        #expect(AppEnvironment(environment: [:], arguments: arguments).sample == expected)
    }

    @Test(arguments: [
        ([:], ["Lidless"], AppEnvironment.DataSource.live),
        (["LIDLESS_SAFE_MODE": "1"], ["Lidless"], .sample(.deskSetup)),
        (["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"], ["Lidless"], .sample(.deskSetup)),
        (["XCODE_RUNNING_FOR_PREVIEWS": "1"], ["Lidless"], .sample(.deskSetup)),
        ([:], ["Lidless", "-LidlessSample", "onTheGo"], .sample(.onTheGo)),
        ([:], ["Lidless", "-LidlessSample"], .sample(.deskSetup)),
        (["XCODE_RUNNING_FOR_PREVIEWS": "1"], ["Lidless", "-LidlessSample", "deskModeOn"], .sample(.deskModeOn)),
    ])
    func `data source is live only for a normal UI launch`(environment: [String: String], arguments: [String], expected: AppEnvironment.DataSource) {
        #expect(AppEnvironment(environment: environment, arguments: arguments).dataSource == expected)
    }

    @Test func `popover opens at launch only when asked`() {
        #expect(!AppEnvironment(environment: [:], arguments: ["Lidless"]).showsPopoverAtLaunch)
        #expect(AppEnvironment(environment: [:], arguments: ["Lidless", "-LidlessShowPopover", "YES"]).showsPopoverAtLaunch)
        #expect(!AppEnvironment(environment: [:], arguments: ["Lidless", "-LidlessShowPopover", "NO"]).showsPopoverAtLaunch)
    }
}

@MainActor
struct SampleDataTests {
    @Test(arguments: SampleScenario.allCases)
    func `displays are consistent`(scenario: SampleScenario) throws {
        let model = scenario.makeModel()
        let builtIn = try #require(model.system.builtIn)
        #expect(builtIn.isBuiltIn)
        #expect(model.system.externals.allSatisfy { !$0.isBuiltIn && !$0.isVirtual })
        let ids = model.system.externals.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(model.externalBrightness.levels.keys).isSubset(of: Set(ids)))
        let mains = ([builtIn] + model.system.externals).filter { $0.role == .main }
        #expect(mains.count <= 1)
    }

    @Test(arguments: SampleScenario.allCases)
    func `desk mode needs an external display`(scenario: SampleScenario) {
        let model = scenario.makeModel()
        if model.system.externals.isEmpty {
            #expect(model.deskMode.state == .unavailable(.needsDisplay))
        } else {
            #expect(model.deskMode.state.isAvailable)
        }
    }

    @Test func `desk mode on names a connected display as its trigger`() {
        let model = SampleData.deskModeOn()
        guard case .on(_, .automatic(let name)) = model.deskMode.state else {
            Issue.record("Expected Desk Mode turned on by the plug-in rule")
            return
        }
        #expect(model.system.externals.contains { $0.name == name })
    }

    /// The status lines printed on the three popover boards.
    @Test(arguments: [
        (SampleScenario.deskSetup, [StatusSegment.lidOpen, .displayCount(3), .onPower]),
        (.onTheGo, [.builtInOnly, .onBattery(percent: 64)]),
        (.deskModeOn, [.lidOpen, .builtInOff, .displayCount(2)]),
    ])
    func `status line matches the design board`(scenario: SampleScenario, expected: [StatusSegment]) {
        let model = scenario.makeModel()
        let segments = StatusLine.segments(
            lid: model.system.lid,
            externalCount: model.system.externals.count,
            builtInLit: !model.deskMode.state.isOn,
            power: model.system.power
        )
        #expect(segments == expected)
    }
}

@MainActor
struct MenuBarIconTests {
    private func states(for model: AppModel, showsState: CurrentValueSubject<Bool, Never> = .init(true)) -> (AnyCancellable, () -> [MenuBarIconState]) {
        var received: [MenuBarIconState] = []
        let cancellable = StatusItemController.iconStates(model: model, iconShowsState: showsState.eraseToAnyPublisher())
            .sink { received.append($0) }
        return (cancellable, { received })
    }

    @Test(arguments: [
        (SampleScenario.deskSetup, MenuBarIconState.normal),
        (.onTheGo, .boost),
        (.deskModeOn, .deskMode),
    ])
    func `each sample starts with the glyph its board shows`(scenario: SampleScenario, expected: MenuBarIconState) {
        let (cancellable, received) = states(for: scenario.makeModel())
        #expect(received() == [expected])
        cancellable.cancel()
    }

    @Test func `icon follows boost, desk mode and the setting`() {
        let model = SampleData.deskSetup()
        let showsState = CurrentValueSubject<Bool, Never>(true)
        let (cancellable, received) = states(for: model, showsState: showsState)

        model.brightness.position = 130
        model.brightness.position = 140
        model.deskMode.setOn(true)
        showsState.send(false)
        showsState.send(true)
        model.deskMode.setOn(false)
        model.brightness.boostAllowed = false

        #expect(received() == [.normal, .boost, .deskMode, .normal, .deskMode, .boost, .normal])
        cancellable.cancel()
    }

    @Test(arguments: MenuBarIconState.allCases)
    func `glyphs are 18 point template images`(state: MenuBarIconState) {
        let image = NSImage(resource: state.imageResource)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(!state.accessibilityLabel.isEmpty)
    }
}

/// The seam between the panel and the popover UI: the window is sized from
/// `PopoverRoot`'s ideal size, which must include the shadow margin.
@MainActor
struct StatusPanelHostingTests {
    private func makeHostingView(sink: PanelSizeSink) -> StatusPanelHostingView {
        StatusPanelHostingView(rootView: StatusPanelRoot(model: SampleData.deskSetup(), actions: PopoverActions(), sizeSink: sink))
    }

    @Test func `ideal size is the panel width plus the shadow margin`() {
        let view = makeHostingView(sink: PanelSizeSink())
        let size = view.intrinsicContentSize
        let insets = PopoverMetrics.placementInsets
        #expect(size.width == PopoverMetrics.width + insets.horizontal)
        #expect(size.height > insets.vertical)
    }

    @Test func `content reports its size once laid out`() async throws {
        let sink = PanelSizeSink()
        var reported: [CGSize] = []
        sink.onChange = { reported.append($0) }
        let view = makeHostingView(sink: sink)
        let window = offscreenWindow(for: view)
        try await settle(view) { !reported.isEmpty }
        #expect(reported.last == view.intrinsicContentSize)
        #expect(window.frame.size == PopoverMetrics.defaultWindowSize)
    }

    /// Controls such as Button, Toggle and Slider stopped `onPreferenceChange`
    /// from ever reporting a real size; the reporter must keep working with them.
    @Test func `size reports follow content with controls`() async throws {
        let content = ResizingContent()
        let sink = PanelSizeSink()
        var reported: [CGSize] = []
        sink.onChange = { reported.append($0) }
        let view = NSHostingView(rootView: ResizingContentView(content: content).fixedSize().reportingSize(to: sink))
        let window = offscreenWindow(for: view)
        try await settle(view) { !reported.isEmpty }
        content.height = 500
        try await settle(view) { reported.count > 1 }
        let insets = PopoverMetrics.placementInsets
        #expect(reported == [
            CGSize(width: 360 + insets.horizontal, height: 640 + insets.vertical),
            CGSize(width: 360 + insets.horizontal, height: 500 + insets.vertical),
        ])
        withExtendedLifetime(window) {}
    }

    /// Short screens: the controller passes the room there is, and the content
    /// fits it instead of running past the panel's bottom edge.
    @Test func `the popover fits the height the screen has room for`() async throws {
        let model = SampleData.deskSetup()
        let sink = PanelSizeSink()
        var reported: [CGSize] = []
        sink.onChange = { reported.append($0) }
        let view = StatusPanelHostingView(rootView: StatusPanelRoot(model: model, actions: PopoverActions(), sizeSink: sink, maxPanelHeight: 859))
        let window = offscreenWindow(for: view)
        let insets = PopoverMetrics.placementInsets
        func settles(atPanelHeight height: CGFloat) async throws -> Bool {
            try await settle(view) { reported.last?.height == height + insets.vertical }
            return reported.last?.height == height + insets.vertical
        }

        #expect(try await settles(atPanelHeight: 640))
        // Room for the content but not the design's height: footer pinned at the bottom.
        view.rootView.maxPanelHeight = 530
        #expect(try await settles(atPanelHeight: 530))
        // Less room than the content needs: the displays list scrolls.
        view.rootView.maxPanelHeight = 440
        #expect(try await settles(atPanelHeight: 440))

        // Four more monitors outgrow the design's height on a tall screen, then scroll on a shorter one.
        view.rootView.maxPanelHeight = 859
        let extras = (4...7).map(extraMonitor)
        for extra in extras {
            model.externalBrightness.levels[extra.id] = 0.5
        }
        model.system.externals += extras
        try await settle(view) { (reported.last?.height ?? 0) > 640 + insets.vertical }
        let grown = try #require(reported.last?.height) - insets.vertical
        #expect(grown > 640 && grown < 859)
        view.rootView.maxPanelHeight = 660
        #expect(try await settles(atPanelHeight: 660))
        // Unplugging them lets every row show again, back at the design's height.
        model.system.externals.removeLast(4)
        #expect(try await settles(atPanelHeight: 640))
        withExtendedLifetime(window) {}
    }

    private func extraMonitor(_ number: Int) -> DisplayDescriptor {
        DisplayDescriptor(
            id: "extra-\(number)", displayID: UInt32(number), name: "Monitor \(number)", isBuiltIn: false,
            pixelWidth: 2560, pixelHeight: 1440, role: .extended, brightnessControl: .ddc
        )
    }

    /// A window that is never ordered on screen.
    private func offscreenWindow(for view: NSView) -> NSPanel {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: PopoverMetrics.defaultWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.contentView = view
        return window
    }

    private func settle(_ view: NSView, until done: () -> Bool) async throws {
        view.layoutSubtreeIfNeeded()
        for _ in 0..<40 where !done() {
            try await Task.sleep(nanoseconds: 25_000_000)
            view.layoutSubtreeIfNeeded()
        }
    }

    @Test func `backdrop sits exactly on the panel rect`() {
        let insets = PopoverMetrics.placementInsets
        let rect = PanelPlacement.visualRect(inWindowOf: PopoverMetrics.defaultWindowSize, insets: insets)
        #expect(rect == CGRect(x: insets.left, y: insets.bottom, width: PopoverMetrics.width, height: PopoverMetrics.designHeight))
    }
}

/// ⌘W and Window › Close reach the borderless panel as performClose(_:).
@MainActor
struct StatusPanelCloseTests {
    private let closeItem = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    @Test func `close is enabled and goes to the controller`() {
        let panel = StatusPanel()
        var closes = 0
        panel.closeRequest = { closes += 1 }
        #expect(panel.validateMenuItem(closeItem))
        #expect(NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: panel, from: closeItem))
        #expect(closes == 1)
    }

    @Test func `without a controller close stays disabled`() {
        #expect(!StatusPanel().validateMenuItem(closeItem))
    }
}

@MainActor
struct KeyboardLayoutTests {
    private func layout(_ id: String) throws -> TISInputSource {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        return try #require(sources?.first, "\(id) is not installed")
    }

    @Test(arguments: [
        ("com.apple.keylayout.US", false, "B"),
        ("com.apple.keylayout.Dvorak", false, "X"),
        ("com.apple.keylayout.Dvorak", true, "X"),
        ("com.apple.keylayout.DVORAK-QWERTYCMD", false, "X"),
        ("com.apple.keylayout.DVORAK-QWERTYCMD", true, "B"),
    ])
    func `the panic key is named by the layout`(layoutID: String, commandHeld: Bool, expected: String) throws {
        let source = try layout(layoutID)
        #expect(KeyboardLayout.label(forKeyCode: KeyShortcut.defaultPanic.keyCode, commandHeld: commandHeld, in: source) == expected)
    }

    @Test(arguments: [("com.apple.keylayout.US", "="), ("com.apple.keylayout.German", "´"), ("com.apple.keylayout.French", "-")])
    func `the boost key is named by the layout`(layoutID: String, expected: String) throws {
        let source = try layout(layoutID)
        #expect(KeyboardLayout.label(forKeyCode: KeyShortcut.defaultBoost.keyCode, commandHeld: true, in: source) == expected)
    }

    /// Space, Return and F1 type nothing a keycap could show; the recorded label stays.
    @Test(arguments: [UInt16(0x31), 0x24, 0x7A])
    func `non-printing keys have no layout label`(keyCode: UInt16) throws {
        #expect(KeyboardLayout.label(forKeyCode: keyCode, commandHeld: false, in: try layout("com.apple.keylayout.US")) == nil)
    }
}

private final class ResizingContent: ObservableObject {
    @Published var height: CGFloat = 640
    @Published var isOn = false
    @Published var level = 0.5
}

private struct ResizingContentView: View {
    @ObservedObject var content: ResizingContent

    var body: some View {
        VStack {
            Button("Quit") {}
            Toggle("Desk Mode", isOn: $content.isOn)
            Slider(value: $content.level)
        }
        .frame(width: PopoverMetrics.width, height: content.height)
        .padding(PopoverMetrics.shadowPadding)
    }
}
