import Foundation
import Testing
@testable import LidlessCore

struct WatchdogMessageTests {
    static let panel = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    @Test(arguments: [
        (WatchdogMessage.arm(displayID: 1, method: .disconnect, uuid: panel), "arm 1 disconnect 37D8832A-2D66-02CA-B9F7-8F30A301B230"),
        (.arm(displayID: 4_294_967_295, method: .blackout, uuid: nil), "arm 4294967295 blackout -"),
        (.heartbeat, "hb"),
        (.deadline(12.5), "deadline 12.5"),
        (.deadline(0), "deadline 0.0"),
        (.deadline(nil), "deadline none"),
        (.bye, "bye"),
    ])
    func `writes and reads lines`(message: WatchdogMessage, line: String) {
        #expect(message.line == line)
        #expect(WatchdogMessage(line: Substring(line)) == message)
    }

    @Test(arguments: [0.000_01, 123_456.789_012_345, 1e16, 86_400 * 365.25, Double.leastNonzeroMagnitude])
    func `deadlines round trip exactly`(seconds: TimeInterval) {
        #expect(WatchdogMessage(line: Substring(WatchdogMessage.deadline(seconds).line)) == .deadline(seconds))
    }

    @Test(arguments: ["", "-", "has space", "naïve", "\t"])
    func `an unsendable UUID goes out as none`(uuid: String) {
        let line = WatchdogMessage.arm(displayID: 2, method: .disconnect, uuid: uuid).line
        #expect(line == "arm 2 disconnect -")
        #expect(WatchdogMessage(line: Substring(line)) == .arm(displayID: 2, method: .disconnect, uuid: nil))
    }

    @Test func `any printable token is a UUID`() {
        #expect(WatchdogMessage(line: "arm 1 disconnect abc") == .arm(displayID: 1, method: .disconnect, uuid: "abc"))
    }

    @Test(arguments: ["hb\r", "bye\r", "deadline none\r", "arm 1 blackout -\r"])
    func `a trailing carriage return is tolerated`(line: String) {
        #expect(WatchdogMessage(line: Substring(line)) != nil)
    }

    @Test(arguments: [
        "",
        " ",
        "\r",
        "hb\r\r",
        "HB",
        "hb ",
        " hb",
        "hb x",
        "heartbeat",
        "bye now",
        "byebye",
        "arm",
        "arm 1 disconnect",
        "arm 1 disconnect - extra",
        "arm  1 disconnect -",
        "arm 1 disconnect  -",
        "arm 1 disconnect -\t",
        "arm x disconnect -",
        "arm -1 disconnect -",
        "arm +1 disconnect -",
        "arm 1.0 disconnect -",
        "arm 4294967296 disconnect -",
        "arm 0x1 disconnect -",
        "arm 1 gamma -",
        "arm 1 Disconnect -",
        "arm 1 disconnect naïve",
        "deadline",
        "deadline ",
        "deadline none none",
        "deadline NONE",
        "deadline -1",
        "deadline -0.5",
        "deadline abc",
        "deadline inf",
        "deadline nan",
        "deadline infinity",
        "deadline 0x10",
        "deadline 1e999",
        "deadline 1,5",
        "deadline 12.5s",
        "deadline  12",
        "deadline 12 ",
        "\u{FFFD}",
    ])
    func `rejects anything else`(line: String) {
        #expect(WatchdogMessage(line: Substring(line)) == nil)
    }

    @Test func `parses a substring slice`() {
        let text = "xx hb"
        #expect(WatchdogMessage(line: text.dropFirst(3)) == .heartbeat)
    }
}

struct WatchdogLineBufferTests {
    static func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    static let stream = "arm 1 disconnect 37D8832A-2D66-02CA-B9F7-8F30A301B230\nhb\ndeadline 812.25\nhb\ndeadline none\nbye\n"
    static let messages: [WatchdogMessage] = [
        .arm(displayID: 1, method: .disconnect, uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230"),
        .heartbeat, .deadline(812.25), .heartbeat, .deadline(nil), .bye,
    ]

    @Test func `one chunk`() {
        var buffer = WatchdogLineBuffer()
        #expect(buffer.append(Self.bytes(Self.stream)) == Self.messages)
        #expect(buffer == WatchdogLineBuffer())
    }

    @Test(arguments: [1, 2, 3, 5, 7, 13, 64])
    func `chunks split anywhere`(size: Int) {
        var buffer = WatchdogLineBuffer()
        let all = Self.bytes(Self.stream)
        var out: [WatchdogMessage] = []
        for start in stride(from: 0, to: all.count, by: size) {
            out += buffer.append(Array(all[start..<min(start + size, all.count)]))
        }
        #expect(out == Self.messages)
    }

    @Test func `every split point of a line`() {
        let line = Self.bytes("deadline 99.5\n")
        for cut in 0...line.count {
            var buffer = WatchdogLineBuffer()
            let first = buffer.append(Array(line[..<cut]))
            let second = buffer.append(Array(line[cut...]))
            #expect(first + second == [.deadline(99.5)])
            #expect(first.isEmpty == (cut < line.count))
        }
    }

    @Test func `a partial line waits for its newline`() {
        var buffer = WatchdogLineBuffer()
        #expect(buffer.append(Self.bytes("hb\nby")) == [.heartbeat])
        #expect(buffer.append(Self.bytes("e")) == [])
        #expect(buffer.append(Self.bytes("\n")) == [.bye])
    }

    @Test func `empty input and empty lines`() {
        var buffer = WatchdogLineBuffer()
        #expect(buffer.append([]) == [])
        #expect(buffer.append(Self.bytes("\n\n\nhb\n\n")) == [.heartbeat])
    }

    @Test func `CRLF line endings`() {
        var buffer = WatchdogLineBuffer()
        #expect(buffer.append(Self.bytes("hb\r\nbye\r")) == [.heartbeat])
        #expect(buffer.append(Self.bytes("\n")) == [.bye])
    }

    @Test func `bad lines are skipped, good ones kept`() {
        var buffer = WatchdogLineBuffer()
        let out = buffer.append(Self.bytes("hello\nhb\narm x y z\n\u{1}\nbye\n"))
        #expect(out == [.heartbeat, .bye])
    }

    @Test func `invalid UTF-8 is skipped`() {
        var buffer = WatchdogLineBuffer()
        #expect(buffer.append([0x68, 0x62, 0xFF, 0x0A, 0xC3, 0x0A]) == [])
        #expect(buffer.append(Self.bytes("hb\n")) == [.heartbeat])
    }

    @Test func `a line at the cap is kept`() {
        var buffer = WatchdogLineBuffer()
        let padded = "arm 1 disconnect " + String(repeating: "A", count: WatchdogLineBuffer.maxLineLength - 17)
        #expect(padded.utf8.count == WatchdogLineBuffer.maxLineLength)
        #expect(buffer.append(Self.bytes(padded + "\n")) == [.arm(displayID: 1, method: .disconnect, uuid: String(repeating: "A", count: WatchdogLineBuffer.maxLineLength - 17))])
    }

    @Test func `a runaway line is dropped, tail and all`() {
        var buffer = WatchdogLineBuffer()
        // Exactly at the cap, one byte over, then a tail that would parse by itself.
        let junk = [UInt8](repeating: UInt8(ascii: "x"), count: WatchdogLineBuffer.maxLineLength)
        #expect(buffer.append(junk) == [])
        #expect(buffer.append(Self.bytes("x")) == [])
        #expect(buffer.append(Self.bytes("hb")) == [])
        #expect(buffer.append(Self.bytes("\nbye\n")) == [.bye])
    }

    @Test func `a runaway line never grows the buffer`() {
        var buffer = WatchdogLineBuffer()
        let chunk = [UInt8](repeating: UInt8(ascii: "a"), count: 4096)
        for _ in 0..<64 { #expect(buffer.append(chunk) == []) }
        #expect(buffer.append(Self.bytes("\nhb\n")) == [.heartbeat])
        #expect(buffer == WatchdogLineBuffer())
    }

    @Test func `an over-long line in one chunk is dropped too`() {
        var buffer = WatchdogLineBuffer()
        let long = "arm 1 disconnect " + String(repeating: "A", count: 2000)
        #expect(buffer.append(Self.bytes("hb\n" + long + "\nbye\n")) == [.heartbeat, .bye])
    }
}

struct WatchdogPolicyTests {
    static let policy = WatchdogPolicy(hangTimeout: 10, revertGrace: 1.5, deadlineGrace: 2)

    /// Armed at t = 100 with a fresh heartbeat, parent alive, panel off.
    static func armed(now: TimeInterval = 100, heartbeat: TimeInterval? = 100, deadline: TimeInterval? = nil, diedAt: TimeInterval? = nil, killed: Bool = false, back: Bool = false) -> WatchdogPolicy.Observation {
        .init(now: now, armed: true, saidBye: false, lastHeartbeat: heartbeat, deadline: deadline, parentDiedAt: diedAt, killedParent: killed, builtInBack: back)
    }

    static func action(_ o: WatchdogPolicy.Observation) -> WatchdogPolicy.Action { policy.action(for: o) }

    @Test func `defaults`() {
        let p = WatchdogPolicy()
        #expect(p.hangTimeout == 10)
        #expect(p.revertGrace == 1.5)
        #expect(p.deadlineGrace == 2)
    }

    // MARK: Not armed

    @Test(arguments: [(false, false), (false, true), (true, true)])
    func `unarmed or disarmed waits while the parent lives`(armed: Bool, bye: Bool) {
        let o = WatchdogPolicy.Observation(now: 500, armed: armed, saidBye: bye, lastHeartbeat: nil, deadline: 1, parentDiedAt: nil, killedParent: false, builtInBack: false)
        #expect(Self.action(o) == .none)
    }

    @Test(arguments: [(false, false), (false, true), (true, true)])
    func `unarmed or disarmed exits once the parent dies`(armed: Bool, bye: Bool) {
        let o = WatchdogPolicy.Observation(now: 500, armed: armed, saidBye: bye, lastHeartbeat: 1, deadline: 1, parentDiedAt: 500, killedParent: false, builtInBack: false)
        #expect(Self.action(o) == .exit)
    }

    @Test func `bye wins over a stale heartbeat and deadline`() {
        var o = Self.armed(now: 1000, heartbeat: 0, deadline: 0)
        o.saidBye = true
        #expect(Self.action(o) == .none)
    }

    // MARK: Parent died

    @Test func `panel back after death exits`() {
        #expect(Self.action(Self.armed(now: 100, diedAt: 100, back: true)) == .exit)
        #expect(Self.action(Self.armed(now: 200, diedAt: 100, killed: true, back: true)) == .exit)
    }

    @Test(arguments: [
        (100.0, WatchdogPolicy.Action.none),
        (101.4, .none),
        (101.5, .restore),
        (102, .restore),
        (500, .restore),
    ])
    func `after death, WindowServer gets the grace first`(now: TimeInterval, expected: WatchdogPolicy.Action) {
        #expect(Self.action(Self.armed(now: now, diedAt: 100)) == expected)
    }

    @Test func `death after a kill restores the same way`() {
        #expect(Self.action(Self.armed(now: 111, heartbeat: 90, diedAt: 110.5, killed: true)) == .none)
        #expect(Self.action(Self.armed(now: 112, heartbeat: 90, diedAt: 110.5, killed: true)) == .restore)
    }

    @Test func `death ignores heartbeat and deadline`() {
        #expect(Self.action(Self.armed(now: 100, heartbeat: 0, deadline: 0, diedAt: 100)) == .none)
    }

    // MARK: Parent alive: hang

    @Test(arguments: [
        (105.0, WatchdogPolicy.Action.none),
        (109.99, .none),
        (110, .killParent),
        (130, .killParent),
    ])
    func `a stale heartbeat kills the parent`(now: TimeInterval, expected: WatchdogPolicy.Action) {
        #expect(Self.action(Self.armed(now: now, heartbeat: 100)) == expected)
    }

    @Test func `a hang kills even with the panel back`() {
        #expect(Self.action(Self.armed(now: 110, heartbeat: 100, back: true)) == .killParent)
    }

    @Test func `no heartbeat yet is no hang`() {
        #expect(Self.action(Self.armed(now: 10_000, heartbeat: nil)) == .none)
    }

    @Test func `a heartbeat from the future is not a hang`() {
        #expect(Self.action(Self.armed(now: 100, heartbeat: 150)) == .none)
    }

    // MARK: Parent alive: prompt deadline

    @Test(arguments: [
        (100.0, WatchdogPolicy.Action.none),
        (120, .none),
        (121.99, .none),
        (122, .killParent),
    ])
    func `an overdue prompt kills a stopped parent`(now: TimeInterval, expected: WatchdogPolicy.Action) {
        // Heartbeats keep coming so only the deadline can fire.
        #expect(Self.action(Self.armed(now: now, heartbeat: now, deadline: 120)) == expected)
    }

    @Test func `an overdue prompt with the panel back is fine`() {
        #expect(Self.action(Self.armed(now: 200, heartbeat: 200, deadline: 120, back: true)) == .none)
    }

    @Test func `a kept prompt has no deadline`() {
        #expect(Self.action(Self.armed(now: 10_000, heartbeat: 10_000, deadline: nil)) == .none)
    }

    @Test func `SIGSTOP during the prompt: the deadline fires before the hang`() {
        // Stopped at 100 with the deadline at 105: kill at 107, not 110.
        #expect(Self.action(Self.armed(now: 106.9, heartbeat: 100, deadline: 105)) == .none)
        #expect(Self.action(Self.armed(now: 107, heartbeat: 100, deadline: 105)) == .killParent)
    }

    // MARK: Parent alive after SIGKILL

    @Test(arguments: [
        (110.0, WatchdogPolicy.Action.none),
        (115, .none),
        (119.99, .none),
        (120, .restore),
        (200, .restore),
    ])
    func `a kill that never lands restores after another hang timeout`(now: TimeInterval, expected: WatchdogPolicy.Action) {
        #expect(Self.action(Self.armed(now: now, heartbeat: 100, killed: true)) == expected)
    }

    @Test func `a deadline kill that never lands restores too`() {
        // Kill due at 122 (deadline 120 + 2); restore from 132.
        #expect(Self.action(Self.armed(now: 131.9, heartbeat: 131.9, deadline: 120, killed: true)) == .none)
        #expect(Self.action(Self.armed(now: 132, heartbeat: 132, deadline: 120, killed: true)) == .restore)
    }

    @Test func `after a kill, a panel that is back needs nothing`() {
        #expect(Self.action(Self.armed(now: 500, heartbeat: 100, killed: true, back: true)) == .none)
    }

    @Test func `after a kill, a live healthy parent is left alone`() {
        #expect(Self.action(Self.armed(now: 500, heartbeat: 499, killed: true)) == .none)
    }

    // MARK: Healthy

    @Test func `healthy and armed does nothing`() {
        #expect(Self.action(Self.armed(now: 100, heartbeat: 99.5, deadline: 115)) == .none)
        #expect(Self.action(Self.armed(now: 100, heartbeat: 99.5, back: true)) == .none)
    }

    @Test func `custom timings are honoured`() {
        let p = WatchdogPolicy(hangTimeout: 3, revertGrace: 0, deadlineGrace: 0)
        #expect(p.action(for: Self.armed(now: 103, heartbeat: 100)) == .killParent)
        #expect(p.action(for: Self.armed(now: 100, diedAt: 100)) == .restore)
        #expect(p.action(for: Self.armed(now: 100, heartbeat: 100, deadline: 100)) == .killParent)
    }
}
