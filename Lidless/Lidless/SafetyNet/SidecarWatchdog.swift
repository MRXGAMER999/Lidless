import CoreGraphics
import Darwin
import Foundation
import LidlessCore
import os

/// Layer 7 of the safety net: the app's own executable, re-launched as
/// `--watchdog <pid>` in its own session, restores the built-in screen when
/// this process dies, hangs or stops (SIGSTOP, a debugger) with Desk Mode on.
///
/// The link is a pipe to the sidecar's stdin. Its write end is non-blocking,
/// so a sidecar that stops reading can never stall the main thread, and
/// SIGPIPE is ignored, so a sidecar that died can't take the app with it.
final class SidecarWatchdog: WatchdogLink {
    private var child: pid_t?
    private var pipeFD: Int32 = -1
    private var heartbeat: Timer?
    /// What the running sidecar guards, so a sidecar that died can be replaced.
    private var armed: WatchdogMessage?
    /// The running sidecar has received `armed`.
    private var delivered = false
    private var deadline: TimeInterval?
    /// Replacements for sidecars that died while armed; bounded so a sidecar
    /// that dies on start can't turn every heartbeat into a spawn.
    private var respawns = 0
    /// Exited or exiting sidecars not yet reaped.
    private var unreaped: Set<pid_t> = []
    private let heartbeatInterval: TimeInterval = 0.5
    private let maxRespawns = 3
    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Watchdog")

    /// A sidecar is running and has received the current arm line.
    var isArmed: Bool { armed != nil && delivered && pipeFD >= 0 }

    /// False when the sidecar couldn't be spawned or the arm line couldn't be
    /// written. The heartbeat then keeps retrying, a bounded number of times.
    @discardableResult
    func arm(displayID: CGDirectDisplayID, method: DeskModeMethod, uuid: String?) -> Bool {
        let message = WatchdogMessage.arm(displayID: displayID, method: method, uuid: uuid)
        armed = message
        delivered = false
        respawns = 0
        reap()
        if isRunning || spawn() {
            delivered = send(message)
            if delivered { send(.heartbeat) }
        }
        // Also after a failed spawn: each beat then retries it.
        startHeartbeat()
        if !delivered { log.error("The watchdog could not be armed") }
        return delivered
    }

    func setDeadline(_ deadline: TimeInterval?) {
        self.deadline = deadline
        send(.deadline(deadline))
    }

    func disarm() {
        armed = nil
        deadline = nil
        stopHeartbeat()
        send(.bye)
        closePipe()
        reap()
        // The sidecar exits within a tick of "bye" (or of EOF); collect it then.
        for delay in [0.5, 3.0] where !unreaped.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.reap() }
            }
        }
    }

    // MARK: - Process

    /// A pipe is open to a sidecar that hasn't been seen to exit.
    private var isRunning: Bool {
        guard pipeFD >= 0, let child else { return false }
        let r = waitpid(child, nil, WNOHANG)
        guard r == 0 else {
            log.error("Watchdog \(child) exited")
            unreaped.remove(child)
            closePipe()
            return false
        }
        return true
    }

    private func spawn() -> Bool {
        _ = Self.ignoreSIGPIPE
        guard let path = Bundle.main.executablePath else {
            log.fault("No executable path; the watchdog can't start")
            return false
        }
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            log.fault("pipe failed: \(errno)")
            return false
        }
        let (readFD, writeFD) = (fds[0], fds[1])
        // Nothing else this process spawns may inherit either end; the child
        // gets the read end through the dup2 below, which clears the flag.
        _ = fcntl(readFD, F_SETFD, FD_CLOEXEC)
        _ = fcntl(writeFD, F_SETFD, FD_CLOEXEC)
        _ = fcntl(writeFD, F_SETFL, fcntl(writeFD, F_GETFL) | O_NONBLOCK)
        _ = fcntl(writeFD, F_SETNOSIGPIPE, 1)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, readFD, STDIN_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addinherit_np(&actions, STDERR_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Own session: launchd kills the app's process group when the app goes,
        // and the sidecar must outlive it. CLOEXEC_DEFAULT: only fds 0–2 cross.
        let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        // The app ignores SIGPIPE here and SIGTERM/SIGINT/SIGHUP in its signal
        // restorer; ignored signals survive exec, so give the sidecar defaults.
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for sig in [SIGHUP, SIGINT, SIGQUIT, SIGPIPE, SIGALRM, SIGTERM, SIGUSR1, SIGUSR2] {
            sigaddset(&defaults, sig)
        }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)

        let args = [path, "--watchdog", "\(getpid())"]
        let argv = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let error = posix_spawn(&pid, path, &actions, &attributes, argv, environ)
        close(readFD)
        guard error == 0 else {
            close(writeFD)
            log.fault("posix_spawn failed: \(error)")
            return false
        }
        child = pid
        unreaped.insert(pid)
        pipeFD = writeFD
        log.info("Watchdog \(pid) started")
        return true
    }

    private func closePipe() {
        if pipeFD >= 0 { close(pipeFD) }
        pipeFD = -1
        child = nil
        delivered = false
    }

    /// Collects exited sidecars so none stays a zombie.
    private func reap() {
        for pid in unreaped where waitpid(pid, nil, WNOHANG) != 0 {
            // pid on exit; -1 (ECHILD) when someone else already reaped it.
            unreaped.remove(pid)
        }
    }

    /// Ignored for the whole process: a write to a dead sidecar's pipe then
    /// fails with EPIPE instead of killing the app.
    private static let ignoreSIGPIPE: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    // MARK: - Messages

    private func startHeartbeat() {
        guard heartbeat == nil else { return }
        // On the main run loop in common modes, because the heartbeat's whole
        // point is proving the main thread still turns (menus and drags included).
        let timer = Timer(timeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        timer.tolerance = heartbeatInterval / 5
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    private func stopHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = nil
    }

    private func beat() {
        if pipeFD >= 0, delivered {
            send(.heartbeat)
            return
        }
        // Running but the arm line was dropped (pipe full): resend it.
        if pipeFD >= 0, let armed {
            delivered = send(armed)
            if delivered { resendState() }
            return
        }
        // The sidecar died (or never started) while Desk Mode is on: replace it.
        guard let armed, respawns < maxRespawns else { return }
        respawns += 1
        reap()
        log.error("Replacing the watchdog (\(self.respawns) of \(self.maxRespawns))")
        guard spawn() else { return }
        delivered = send(armed)
        if delivered { resendState() }
    }

    private func resendState() {
        if let deadline { send(.deadline(deadline)) }
        send(.heartbeat)
    }

    /// One non-blocking write. Lines are far below PIPE_BUF, so each write is
    /// all or nothing: a full pipe drops the line (the sidecar isn't reading).
    /// True when the whole line was written.
    @discardableResult
    private func send(_ message: WatchdogMessage) -> Bool {
        guard pipeFD >= 0 else { return false }
        let bytes = Array((message.line + "\n").utf8)
        while true {
            let n = bytes.withUnsafeBytes { write(pipeFD, $0.baseAddress, $0.count) }
            if n == bytes.count { return true }
            let code = errno
            if n < 0, code == EINTR { continue }
            if n < 0, code == EAGAIN {
                log.error("Watchdog pipe full; dropped \(message.line, privacy: .public)")
                return false
            }
            log.error("Watchdog pipe write failed (\(code)); marking it dead")
            closePipe()
            reap()
            return false
        }
    }
}
