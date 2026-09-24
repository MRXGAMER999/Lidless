import Foundation

/// DDC/CI packets for VCP feature codes (0x10 luminance), as sent over
/// IOAVService on Apple Silicon. Pure encoding and strict reply checks.
///
/// Framing follows MonitorControl's `Arm64DDC` and m1ddc (both MIT), which
/// have shipped it for years (phase4-research.md §3.3). The monitor's 7-bit
/// I2C address 0x37 is the `chipAddress` (0x6E/0x6F on the wire), and the host
/// source address 0x51 is not in the buffer: it goes in as `dataAddress`, so
/// every payload starts at the length byte (0x80 | the length of the opcode
/// and its arguments):
///
///     IOAVServiceWriteI2C(service, 0x37, 0x51, payload, payload.count)
///
/// (0xB7 instead of 0x37 behind an MCDP29xx HDMI converter; the payloads are the same.)
public enum DDC {
    /// VCP code for luminance (brightness). Timings live with the link
    /// (phase4-research.md §3.4).
    public static let luminance: UInt8 = 0x10

    /// Destination address the checksums are seeded with (0x37 << 1).
    static let displayAddress: UInt8 = 0x6E
    /// Host source address, sent as `dataAddress`.
    static let hostAddress: UInt8 = 0x51
    /// Virtual host address a reply's checksum is seeded with.
    static let replySeed: UInt8 = 0x50

    /// Payload for `IOAVServiceWriteI2C(service, 0x37, 0x51, payload)` to set `value` (0...max).
    /// Layout: [0x84, 0x03, code, hi, lo, checksum], checksum = 0x6E ^ 0x51 ^ bytes,
    /// the DDC/CI rule (destination ^ source ^ every byte).
    public static func setPayload(code: UInt8, value: UInt16) -> [UInt8] {
        let body: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)]
        return body + [xor(body, seed: displayAddress ^ hostAddress)]
    }

    /// Payload for a "get VCP feature" request: [0x82, 0x01, code, checksum],
    /// checksum = 0x6E ^ bytes. MonitorControl, AppleSiliconDDC and m1ddc all
    /// leave 0x51 out of this one (so 0x10 gives 0xFD, where the DDC/CI rule
    /// would give 0xAC); that is what works on real monitors, so we send the same.
    public static func getPayload(code: UInt8) -> [UInt8] {
        let body: [UInt8] = [0x82, 0x01, code]
        return body + [xor(body, seed: displayAddress)]
    }

    public struct Reply: Sendable, Equatable {
        public var current: UInt16
        public var maximum: UInt16
    }

    /// Length of a VCP feature reply.
    static let replyLength = 11
    /// Start of an EDID block, which some links (the M5 Pro HDMI port) return instead of a reply.
    static let edidHeader: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]

    /// Parses a "VCP feature reply", read after a get request with
    /// `IOAVServiceReadI2C(service, 0x37, 0, buffer, 11)` (MonitorControl; m1ddc
    /// reads 12, so bytes past the 11th are ignored). Layout:
    /// [0x6E, 0x88, 0x02, result, code, type, maxHi, maxLo, curHi, curLo, checksum].
    ///
    /// nil for anything else: fewer than 11 bytes, a wrong source (0x6E),
    /// length (0x88) or opcode (0x02), a result code other than 0 (1 means the
    /// monitor doesn't support the feature), another feature code, a bad
    /// checksum (0x50 ^ the first 10 bytes, as monitors send it), a maximum of
    /// 0 or a current value above it, an all-zero or all-0xFF buffer, or EDID
    /// bytes (00 FF FF FF FF FF FF 00) that some links echo instead of a reply.
    public static func parseReply(_ bytes: [UInt8], code: UInt8) -> Reply? {
        guard bytes.count >= replyLength else { return nil }
        let r = Array(bytes.prefix(replyLength))
        guard !r.allSatisfy({ $0 == 0x00 }), !r.allSatisfy({ $0 == 0xFF }),
              !r.starts(with: edidHeader),
              r[0] == displayAddress, r[1] == 0x88, r[2] == 0x02, r[3] == 0x00, r[4] == code,
              xor(r[0..<10], seed: replySeed) == r[10]
        else { return nil }
        let maximum = UInt16(r[6]) << 8 | UInt16(r[7])
        let current = UInt16(r[8]) << 8 | UInt16(r[9])
        guard maximum > 0, current <= maximum else { return nil }
        return Reply(current: current, maximum: maximum)
    }

    /// `sys_iokit | sub_iokit_audio_video` (IOReturn.h: `err_system(0x38)`, `err_sub(0x45)`).
    static let audioVideoFamily: UInt32 = 0xE011_4000
    /// The system (6 bits) and subsystem (12 bits) of an IOReturn; the low 14 bits are the code.
    static let familyMask: UInt32 = 0xFFFF_C000

    /// Whether an IOReturn from IOAVService means the link can never work: stop trying.
    ///
    /// True for any error in the IOKit audio/video family (0xE0114000...0xE0117FFF),
    /// where the display coprocessor turns the transfer down before it reaches
    /// the monitor. The M5 Pro HDMI port answers 0xE0114102 (family 0x45,
    /// code 0x102). A looser 0xE011xxxx test would also catch the CEC (0x46)
    /// and ARC (0x47) families, which say nothing about the DDC link.
    public static func isPermanentFailure(_ ioReturn: Int32) -> Bool {
        UInt32(bitPattern: ioReturn) & familyMask == audioVideoFamily
    }

    private static func xor<S: Sequence>(_ bytes: S, seed: UInt8) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(seed, ^)
    }
}

/// Software dimming for externals without DDC: a black overlay's opacity.
public enum ShadeMath {
    /// Never darker than this, so a screen can't go fully black.
    public static let maxAlpha = 0.85
    /// Opacity for a brightness level 0...1: `(1 - level)` capped at `maxAlpha`.
    /// A NaN level gives 0 (no shade).
    public static func alpha(forLevel level: Double) -> Double {
        guard !level.isNaN else { return 0 }
        return min(max(1 - level, 0), maxAlpha)
    }
}
