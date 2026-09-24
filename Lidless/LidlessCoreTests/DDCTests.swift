import Testing
@testable import LidlessCore

struct DDCTests {
    /// A reply to "get luminance" from a monitor at 50 of 100, checksum included.
    let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF2]

    /// Builds a reply with a correct checksum, so each test breaks one thing at a time.
    func reply(rc: UInt8 = 0, code: UInt8 = DDC.luminance, max: UInt16 = 100, current: UInt16 = 50) -> [UInt8] {
        let body: [UInt8] = [0x6E, 0x88, 0x02, rc, code, 0x00, UInt8(max >> 8), UInt8(max & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)]
        return body + [body.reduce(0x50, ^)]
    }

    // MARK: Requests

    /// MonitorControl `Arm64DDC.read` and m1ddc `prepareDDCRead`: seeded with 0x6E only.
    @Test func `get luminance matches MonitorControl and m1ddc`() {
        #expect(DDC.getPayload(code: 0x10) == [0x82, 0x01, 0x10, 0xFD])
    }

    /// 0x6E ^ 0x82 ^ 0x01 ^ 0x12.
    @Test func `get contrast`() {
        #expect(DDC.getPayload(code: 0x12) == [0x82, 0x01, 0x12, 0xFF])
    }

    /// 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A, the DDC/CI rule.
    @Test func `set luminance to 50 matches MonitorControl and m1ddc`() {
        #expect(DDC.setPayload(code: 0x10, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    }

    @Test(arguments: [0, 1, 100, 255, 256, 0x1234, UInt16.max])
    func `set splits the value big endian and checksums every byte`(value: UInt16) {
        let payload = DDC.setPayload(code: 0x10, value: value)
        #expect(payload.count == 6)
        #expect(Array(payload.prefix(3)) == [0x84, 0x03, 0x10])
        #expect(UInt16(payload[3]) << 8 | UInt16(payload[4]) == value)
        #expect(payload.reduce(0x6E ^ 0x51, ^) == 0)
    }

    @Test func `get checksums every byte without the source address`() {
        #expect(DDC.getPayload(code: 0x60).reduce(0x6E, ^) == 0)
    }

    /// The first byte is 0x80 | the length of the opcode and its arguments; 0x51 is never in the buffer.
    @Test func `payloads start at the length byte`() {
        #expect(DDC.getPayload(code: 0x10)[0] == 0x80 | 2)
        #expect(DDC.setPayload(code: 0x10, value: 1)[0] == 0x80 | 4)
        #expect(!DDC.getPayload(code: 0x10).dropLast().contains(0x51))
    }

    // MARK: Replies

    @Test func `parses a known reply`() {
        #expect(DDC.parseReply(reply, code: 0x10) == DDC.Reply(current: 50, maximum: 100))
    }

    @Test(arguments: [(0, 100), (100, 100), (0x0123, 0x4567), (1, 0xFFFF)] as [(UInt16, UInt16)])
    func `round trips values`(current: UInt16, max: UInt16) {
        #expect(DDC.parseReply(reply(max: max, current: current), code: 0x10) == DDC.Reply(current: current, maximum: max))
    }

    /// m1ddc reads 12 bytes; the extra byte is not part of the reply.
    @Test func `ignores bytes after the reply`() {
        #expect(DDC.parseReply(reply + [0xAB], code: 0x10) == DDC.Reply(current: 50, maximum: 100))
    }

    @Test(arguments: [0, 1, 10])
    func `rejects a short buffer`(count: Int) {
        #expect(DDC.parseReply(Array(reply.prefix(count)), code: 0x10) == nil)
    }

    @Test(arguments: 0..<11)
    func `rejects any single flipped bit`(index: Int) {
        var bytes = reply
        bytes[index] ^= 0x04
        #expect(DDC.parseReply(bytes, code: 0x10) == nil)
    }

    @Test func `rejects a bad checksum`() {
        var bytes = reply
        bytes[10] &+= 1
        #expect(DDC.parseReply(bytes, code: 0x10) == nil)
    }

    /// Result code 1: the monitor doesn't support the feature.
    @Test func `rejects an unsupported feature`() {
        #expect(DDC.parseReply(reply(rc: 1), code: 0x10) == nil)
    }

    @Test func `rejects a reply for another feature`() {
        #expect(DDC.parseReply(reply(code: 0x12), code: 0x10) == nil)
    }

    @Test func `rejects a wrong source, length or opcode even with a matching checksum`() {
        for (index, value) in [(0, UInt8(0x6F)), (1, 0x87), (2, 0x01)] {
            var bytes = Array(reply.prefix(10))
            bytes[index] = value
            bytes.append(bytes.reduce(0x50, ^))
            #expect(DDC.parseReply(bytes, code: 0x10) == nil)
        }
    }

    @Test func `rejects a zero maximum or a current above it`() {
        #expect(DDC.parseReply(reply(max: 0, current: 0), code: 0x10) == nil)
        #expect(DDC.parseReply(reply(max: 100, current: 101), code: 0x10) == nil)
    }

    @Test(arguments: [UInt8(0x00), 0xFF])
    func `rejects a blank buffer`(fill: UInt8) {
        #expect(DDC.parseReply([UInt8](repeating: fill, count: 11), code: 0x10) == nil)
    }

    /// What the M5 Pro's HDMI port returned for the LG (safety.md §8).
    @Test func `rejects the EDID the HDMI link echoes`() {
        let edid: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x1E, 0x6D, 0x19]
        #expect(DDC.parseReply(edid, code: 0x10) == nil)
        #expect(DDC.parseReply(edid + [0x77, 0x01, 0x01, 0x01], code: 0x10) == nil)
    }

    // MARK: Failures

    @Test(arguments: [
        UInt32(0xE011_4102), // the M5 Pro HDMI port (safety.md §8)
        0xE011_4000, 0xE011_7FFF, // any code in sub_iokit_audio_video
    ])
    func `audio video family errors are permanent`(code: UInt32) {
        #expect(DDC.isPermanentFailure(Int32(bitPattern: code)))
    }

    @Test(arguments: [
        UInt32(0), // kIOReturnSuccess
        0xE000_02BC, // kIOReturnError
        0xE000_02C7, // kIOReturnUnsupported: a read can still work (klart #5)
        0xE000_02D6, // kIOReturnTimeout
        0xE011_0000, 0xE011_3FFF, // err_sub(0x44)
        0xE011_8000, // sub_iokit_cec
        0xE011_C000, // sub_iokit_arc
        0x0011_4102, // the same bits outside sys_iokit
    ])
    func `other errors are not permanent`(code: UInt32) {
        #expect(!DDC.isPermanentFailure(Int32(bitPattern: code)))
    }
}

struct ShadeMathTests {
    @Test(arguments: [(1.0, 0.0), (0.7, 0.3), (0.5, 0.5), (0.15, 0.85), (0.0, 0.85), (-1.0, 0.85), (2.0, 0.0)])
    func `alpha is one minus the level, capped`(level: Double, alpha: Double) {
        #expect(ShadeMath.alpha(forLevel: level).isApproximately(alpha))
    }

    @Test func `odd levels never blacken the screen`() {
        #expect(ShadeMath.alpha(forLevel: .nan) == 0)
        #expect(ShadeMath.alpha(forLevel: .infinity) == 0)
        #expect(ShadeMath.alpha(forLevel: -.infinity) == ShadeMath.maxAlpha)
    }
}
