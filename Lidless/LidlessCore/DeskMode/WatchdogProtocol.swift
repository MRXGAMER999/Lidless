import Foundation

/// Lines the app writes to the sidecar watchdog's stdin. One message per line,
/// ASCII, fields separated by one space.
public enum WatchdogMessage: Sendable, Equatable {
    /// "arm <displayID> <method> <uuid|->": what to restore if the app dies or hangs.
    case arm(displayID: UInt32, method: DeskModeMethod, uuid: String?)
    /// "hb": the app's main thread is alive. Sent every 0.5 s from a main-run-loop timer.
    case heartbeat
    /// "deadline <seconds>|none": the prompt's deadline in `ProcessInfo.systemUptime`
    /// seconds (the sidecar shares the clock), or none once kept.
    case deadline(TimeInterval?)
    /// "bye": the panel is back; exit without doing anything.
    case bye

    /// The line without its newline. A UUID that could not survive the trip
    /// (empty, "-", spaces, non-ASCII) goes out as "-": the sidecar then finds the
    /// built-in by ID alone rather than rejecting the whole arm. A deadline must be
    /// finite and not negative (it is an uptime) to parse back.
    public var line: String {
        switch self {
        case let .arm(displayID, method, uuid):
            let token = uuid.flatMap { Self.isToken($0) && $0 != "-" ? $0 : nil } ?? "-"
            return "arm \(displayID) \(method.rawValue) \(token)"
        case .heartbeat:
            return "hb"
        case let .deadline(seconds?):
            return "deadline \(seconds)"
        case .deadline(nil):
            return "deadline none"
        case .bye:
            return "bye"
        }
    }

    /// Parses one line without its newline; nil for anything else. Strict about
    /// the shape (field count, single spaces, digits only in the ID), so a torn or
    /// foreign line never arms or disarms anything. One trailing "\r" is allowed.
    public init?(line: Substring) {
        var line = line
        if line.hasSuffix("\r") { line = line.dropLast() }
        let fields = line.split(separator: " ", omittingEmptySubsequences: false)
        switch (fields.first, fields.count) {
        case ("arm", 4):
            guard let id = Self.displayID(fields[1]),
                  let method = DeskModeMethod(rawValue: String(fields[2])),
                  Self.isToken(fields[3]) else { return nil }
            self = .arm(displayID: id, method: method, uuid: fields[3] == "-" ? nil : String(fields[3]))
        case ("hb", 1):
            self = .heartbeat
        case ("deadline", 2):
            if fields[1] == "none" {
                self = .deadline(nil)
            } else {
                guard let seconds = Self.uptime(fields[1]) else { return nil }
                self = .deadline(seconds)
            }
        case ("bye", 1):
            self = .bye
        default:
            return nil
        }
    }

    /// Printable ASCII without spaces, at least one character.
    private static func isToken<S: StringProtocol>(_ s: S) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { (0x21...0x7E).contains($0) }
    }

    /// Plain decimal digits only: `UInt32("+5")` would accept a sign.
    private static func displayID(_ s: Substring) -> UInt32? {
        guard !s.isEmpty, s.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return UInt32(s)
    }

    /// Decimal or exponent notation as `Double.description` writes it; no hex,
    /// inf or nan, and never negative.
    private static func uptime(_ s: Substring) -> TimeInterval? {
        guard s.utf8.allSatisfy({ (0x30...0x39).contains($0) || $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "e") || $0 == UInt8(ascii: "E") || $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: "-") }),
              let value = Double(s), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// Splits a byte stream into complete lines, keeping a partial tail for the next chunk.
public struct WatchdogLineBuffer: Sendable, Equatable {
    /// The longest line kept. Real lines are under 80 bytes; anything longer is
    /// garbage, and dropping it bounds memory if the writer never sends "\n".
    static let maxLineLength = 1024

    private var pending: [UInt8] = []
    /// Inside an over-long line: skip to its newline so its tail is never parsed
    /// as a line of its own.
    private var discarding = false

    public init() {}

    /// Appends bytes and returns every complete message; unparseable lines are skipped.
    public mutating func append(_ bytes: [UInt8]) -> [WatchdogMessage] {
        var messages: [WatchdogMessage] = []
        for byte in bytes {
            if byte == UInt8(ascii: "\n") {
                // Invalid UTF-8 decodes to U+FFFD, which no field accepts.
                if !discarding, let message = WatchdogMessage(line: Substring(String(decoding: pending, as: UTF8.self))) {
                    messages.append(message)
                }
                pending.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                pending.append(byte)
                if pending.count > Self.maxLineLength {
                    pending.removeAll()
                    discarding = true
                }
            }
        }
        return messages
    }
}

/// The sidecar's decisions. Pure: the sidecar feeds it what it observed.
public struct WatchdogPolicy: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case none
        /// The app is alive but stopped or hung: SIGKILL it, so WindowServer drops
        /// its app-only configuration, then restore.
        case killParent
        /// Enable the armed panel now (session scope), and keep checking.
        case restore
        /// Nothing left to guard: exit.
        case exit
    }

    /// No heartbeat for this long means hung.
    public var hangTimeout: TimeInterval
    /// After the parent died, give WindowServer this long to revert by itself.
    public var revertGrace: TimeInterval
    /// Past the prompt deadline by this much, restore even if the app lives.
    public var deadlineGrace: TimeInterval

    public init(hangTimeout: TimeInterval = 10, revertGrace: TimeInterval = 1.5, deadlineGrace: TimeInterval = 2) {
        self.hangTimeout = hangTimeout
        self.revertGrace = revertGrace
        self.deadlineGrace = deadlineGrace
    }

    public struct Observation: Sendable, Equatable {
        public var now: TimeInterval
        /// Armed with a display; false before "arm" or after "bye".
        public var armed: Bool
        public var saidBye: Bool
        public var lastHeartbeat: TimeInterval?
        public var deadline: TimeInterval?
        /// Pipe EOF or process-exit event seen, and when.
        public var parentDiedAt: TimeInterval?
        /// SIGKILL already sent.
        public var killedParent: Bool
        /// The armed panel is in the online list (disconnect) or the parent is gone (black out).
        public var builtInBack: Bool

        public init(now: TimeInterval, armed: Bool, saidBye: Bool, lastHeartbeat: TimeInterval?, deadline: TimeInterval?, parentDiedAt: TimeInterval?, killedParent: Bool, builtInBack: Bool) {
            self.now = now
            self.armed = armed
            self.saidBye = saidBye
            self.lastHeartbeat = lastHeartbeat
            self.deadline = deadline
            self.parentDiedAt = parentDiedAt
            self.killedParent = killedParent
            self.builtInBack = builtInBack
        }
    }

    /// Every time limit fires at "at or past" (`>=`), so a tick landing exactly on
    /// it acts rather than waiting a whole tick more.
    ///
    /// `lastHeartbeat` nil means no hang verdict yet: the observation carries no
    /// arm time, so the sidecar should count "arm" itself as a heartbeat (it
    /// proves the main thread was alive). Guessing instead would either kill a
    /// healthy app at once or never catch one that hangs before its first "hb".
    ///
    /// A hang kills even when the panel reads back: an armed, hung app may be mid
    /// engage and about to turn it off. The deadline kill needs the panel off,
    /// since a prompt that ends with the panel on has nothing left to revert.
    public func action(for observation: Observation) -> Action {
        let o = observation
        guard o.armed, !o.saidBye else { return o.parentDiedAt == nil ? .none : .exit }
        if let died = o.parentDiedAt {
            if o.builtInBack { return .exit }
            return o.now - died >= revertGrace ? .restore : .none
        }
        // The parent lives. When did it first deserve a SIGKILL?
        let hungAt = o.lastHeartbeat.map { $0 + hangTimeout }
        let overdueAt = o.builtInBack ? nil : o.deadline.map { $0 + deadlineGrace }
        guard let killAt = [hungAt, overdueAt].compactMap({ $0 }).min(), o.now >= killAt else { return .none }
        if !o.killedParent { return .killParent }
        // SIGKILL can't be caught, but the kill can fail or its exit event can
        // go missing. Don't wait on it forever: restore over the live app.
        return !o.builtInBack && o.now >= killAt + hangTimeout ? .restore : .none
    }
}
