import AppKit
import Darwin

/// Finds other running copies of Lidless. Two copies would hold separate
/// app-only display configurations and confuse launch recovery, so a second
/// copy exits at launch.
///
/// Our own sidecar watchdog runs the same executable (`Lidless --watchdog <pid>`),
/// and once it talks to WindowServer LaunchServices may list it with our bundle
/// ID and, from Info.plist, the same accessory policy. So neither bundle ID nor
/// `activationPolicy` tells it apart; its arguments do.
enum SingleInstance {
    /// The sidecar's first argument, set by the `--watchdog` branch in `LidlessMain`.
    nonisolated static let sidecarFlag = "--watchdog"

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "io.github.mrxgamer999.Lidless" }

    /// Another live Lidless app (not us, not a sidecar), if any.
    static func otherInstance() -> NSRunningApplication? {
        let me = getpid()
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { app in
            app.processIdentifier != me && !app.isTerminated && !isSidecar(pid: app.processIdentifier)
        }
    }

    /// Whether `pid` is another live Lidless app, for `LaunchRecovery.decide`'s
    /// `otherInstanceRunning`. A reused PID now owned by some other process reads false.
    static func isLive(pid: pid_t) -> Bool {
        guard pid > 0, pid != getpid(), kill(pid, 0) == 0 else { return false }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleIdentifier == bundleID else { return false }
        return !isSidecar(pid: pid)
    }

    /// Whether the process was started with `--watchdog`, read from its
    /// arguments (`KERN_PROCARGS2`, readable for the same user's processes).
    /// Unreadable arguments count as not a sidecar.
    nonisolated static func isSidecar(pid: pid_t) -> Bool {
        arguments(of: pid)?.dropFirst().first == sidecarFlag
    }

    /// argv of `pid`. The buffer holds argc (Int32), the executable path, NUL
    /// padding, then argv's NUL-terminated strings, then the environment.
    nonisolated static func arguments(of pid: pid_t) -> [String]? {
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var argMaxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argMaxMIB, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: Int(argMax))
        size = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        let read = buffer.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) }
        guard read == 0, size > MemoryLayout<Int32>.size else { return nil }

        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 }   // executable path
        while i < size, buffer[i] == 0 { i += 1 }   // padding
        var args: [String] = []
        while args.count < argc, i < size {
            let start = i
            while i < size, buffer[i] != 0 { i += 1 }
            args.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }
}
