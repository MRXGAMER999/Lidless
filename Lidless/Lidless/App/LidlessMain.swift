import AppKit

@main
enum LidlessMain {
    static func main() {
        // The sidecar watchdog is this same executable; it never touches AppKit.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--watchdog"), i + 1 < args.count,
           let parent = pid_t(args[i + 1]), parent > 1 {
            WatchdogProcess.run(parentPID: parent)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Info.plist already sets LSUIElement; this keeps a debugger launch identical.
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
