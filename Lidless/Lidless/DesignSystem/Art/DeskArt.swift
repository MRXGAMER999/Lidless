// Generated from the design canvas (design/canvas/*.dc.html); keep the geometry verbatim.
// Colours are the canvas's sRGB hex values.
import SwiftUI

private func artColor(_ hex: UInt32, _ opacity: Double = 1) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
}

/// A `<rect rx>` traced the way SVG does, from (x + rx, y) clockwise, so dashes
/// fall where the canvas draws them (`addRoundedRect` starts elsewhere).
private func svgRoundedRect(_ r: CGRect, radius: CGFloat) -> Path {
    Path { p in
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: radius)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: radius)
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: radius)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: radius)
        p.closeSubpath()
    }
}

/// DeskHero illustration (viewBox 380x196). Settings2-DeskMode draws it 330 wide, Onboarding-Welcome 262 wide (always Desk-on). Animate `deskModeOn` with `withAnimation` for the canvas crossfade.
struct DeskHeroArt: View {
    var deskModeOn: Bool
    var width: CGFloat = 330
    private let viewBox = CGSize(width: 380, height: 196)
    private var k: CGFloat { width / viewBox.width }

    var body: some View {
        ZStack {
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 66, y: 64)); p.addQuadCurve(to: CGPoint(x: 66, y: 44), control: CGPoint(x: 59, y: 54)); p.addQuadCurve(to: CGPoint(x: 66, y: 24), control: CGPoint(x: 73, y: 34)); p.move(to: CGPoint(x: 104, y: 58)); p.addQuadCurve(to: CGPoint(x: 104, y: 38), control: CGPoint(x: 97, y: 48)); p.addQuadCurve(to: CGPoint(x: 104, y: 18), control: CGPoint(x: 111, y: 28)); p.move(to: CGPoint(x: 142, y: 64)); p.addQuadCurve(to: CGPoint(x: 142, y: 44), control: CGPoint(x: 135, y: 54)); p.addQuadCurve(to: CGPoint(x: 142, y: 24), control: CGPoint(x: 149, y: 34)) }, viewBox: viewBox).stroke(artColor(0xFFBF00), style: StrokeStyle(lineWidth: 3 * k, lineCap: .round)).opacity(0.85)
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 170, y: 14, width: 196, height: 124), cornerSize: CGSize(width: 10, height: 10), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 178, y: 22, width: 180, height: 108), cornerSize: CGSize(width: 5, height: 5), style: .circular) }, viewBox: viewBox).fill(artColor(0xFFBF00))
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 268, y: 46)); p.addLine(to: CGPoint(x: 268, y: 53)); p.move(to: CGPoint(x: 268, y: 101)); p.addLine(to: CGPoint(x: 268, y: 108)); p.move(to: CGPoint(x: 238, y: 76)); p.addLine(to: CGPoint(x: 245, y: 76)); p.move(to: CGPoint(x: 291, y: 76)); p.addLine(to: CGPoint(x: 298, y: 76)); p.move(to: CGPoint(x: 247, y: 55)); p.addLine(to: CGPoint(x: 252, y: 60)); p.move(to: CGPoint(x: 284, y: 92)); p.addLine(to: CGPoint(x: 289, y: 97)); p.move(to: CGPoint(x: 247, y: 97)); p.addLine(to: CGPoint(x: 252, y: 92)); p.move(to: CGPoint(x: 284, y: 60)); p.addLine(to: CGPoint(x: 289, y: 55)) }, viewBox: viewBox).stroke(artColor(0xFFF8E6), style: StrokeStyle(lineWidth: 5 * k, lineCap: .round))
            ViewBoxShape(path: Path { p in p.addEllipse(in: CGRect(x: 254, y: 62, width: 28, height: 28)) }, viewBox: viewBox).fill(artColor(0xFFF8E6))
            ViewBoxShape(path: Path { p in p.addRect(CGRect(x: 258, y: 138, width: 20, height: 26)) }, viewBox: viewBox).fill(artColor(0x2A3542))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 228, y: 162, width: 80, height: 9), cornerSize: CGSize(width: 4.5, height: 4.5), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 26, y: 72, width: 160, height: 100), cornerSize: CGSize(width: 9, height: 9), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 34, y: 80, width: 144, height: 84), cornerSize: CGSize(width: 4, height: 4), style: .circular) }, viewBox: viewBox).fill(deskModeOn ? artColor(0x0D1117) : artColor(0x3B4A5E))
            ViewBoxShape(path: Path { p in p.addEllipse(in: CGRect(x: 94, y: 110, width: 24, height: 24)) }, viewBox: viewBox).stroke(artColor(0x6B7480), style: StrokeStyle(lineWidth: 4 * k)).opacity(deskModeOn ? 1 : 0)
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 88, y: 104)); p.addLine(to: CGPoint(x: 124, y: 140)) }, viewBox: viewBox).stroke(artColor(0xF4F4F2), style: StrokeStyle(lineWidth: 5 * k, lineCap: .round)).opacity(deskModeOn ? 1 : 0)
            ViewBoxShape(path: Path { p in p.addEllipse(in: CGRect(x: 95, y: 111, width: 22, height: 22)) }, viewBox: viewBox).fill(artColor(0xFFF8E6)).opacity(deskModeOn ? 0 : 1)
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 106, y: 100)); p.addLine(to: CGPoint(x: 106, y: 105)); p.move(to: CGPoint(x: 106, y: 139)); p.addLine(to: CGPoint(x: 106, y: 144)); p.move(to: CGPoint(x: 84, y: 122)); p.addLine(to: CGPoint(x: 89, y: 122)); p.move(to: CGPoint(x: 123, y: 122)); p.addLine(to: CGPoint(x: 128, y: 122)) }, viewBox: viewBox).stroke(artColor(0xFFF8E6), style: StrokeStyle(lineWidth: 4 * k, lineCap: .round)).opacity(deskModeOn ? 0 : 1)
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 12, y: 172)); p.addLine(to: CGPoint(x: 200, y: 172)); p.addLine(to: CGPoint(x: 214, y: 184)); p.addLine(to: CGPoint(x: -2, y: 184)); p.closeSubpath() }, viewBox: viewBox).fill(artColor(0xE6E7EA))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 0, y: 182, width: 214, height: 7), cornerSize: CGSize(width: 3.5, height: 3.5), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542))
        }
        .frame(width: width, height: width * viewBox.height / viewBox.width)
    }
}

/// DeskMini illustration (viewBox 96x50) for the popover desk card. Main.dc.html (on/off crossfade), Popover-DeskDark (dark deck #C9CDD3), Popover-Boost (`needsDisplay`: dashed monitor, lit sun with rays, no heat waves).
struct DeskMiniArt: View {
    var deskModeOn: Bool
    var needsDisplay: Bool = false
    var darkAppearance: Bool = false
    var width: CGFloat = 96
    private let viewBox = CGSize(width: 96, height: 50)
    private var k: CGFloat { width / viewBox.width }

    var body: some View {
        ZStack {
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 19, y: 13)); p.addQuadCurve(to: CGPoint(x: 19, y: 7), control: CGPoint(x: 17, y: 10)); p.addQuadCurve(to: CGPoint(x: 19, y: 1), control: CGPoint(x: 21, y: 4)); p.move(to: CGPoint(x: 31, y: 13)); p.addQuadCurve(to: CGPoint(x: 31, y: 7), control: CGPoint(x: 29, y: 10)); p.addQuadCurve(to: CGPoint(x: 31, y: 1), control: CGPoint(x: 33, y: 4)) }, viewBox: viewBox).stroke(artColor(0xFFBF00), style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round)).opacity(needsDisplay ? 0 : 0.85)
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 44, y: 2, width: 50, height: 32), cornerSize: CGSize(width: 3, height: 3), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542)).opacity(needsDisplay ? 0 : 1)
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 47, y: 5, width: 44, height: 26), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular) }, viewBox: viewBox).fill(artColor(0xFFBF00)).opacity(needsDisplay ? 0 : 1)
            ViewBoxShape(path: Path { p in p.addEllipse(in: CGRect(x: 64, y: 13, width: 10, height: 10)) }, viewBox: viewBox).fill(artColor(0xFFF8E6)).opacity(needsDisplay ? 0 : 1)
            ViewBoxShape(path: Path { p in p.addRect(CGRect(x: 66, y: 34, width: 6, height: 8)) }, viewBox: viewBox).fill(artColor(0x2A3542)).opacity(needsDisplay ? 0 : 1)
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 58, y: 41, width: 22, height: 3), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542)).opacity(needsDisplay ? 0 : 1)
            ViewBoxShape(path: svgRoundedRect(CGRect(x: 45, y: 3, width: 48, height: 30), radius: 3), viewBox: viewBox).stroke(artColor(0x4A5563), style: StrokeStyle(lineWidth: 1.6 * k, dash: [3, 3].map { $0 * k })).opacity(needsDisplay ? 1 : 0)
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 69, y: 34)); p.addLine(to: CGPoint(x: 69, y: 41)); p.move(to: CGPoint(x: 59, y: 42.5)); p.addLine(to: CGPoint(x: 79, y: 42.5)) }, viewBox: viewBox).stroke(artColor(0x4A5563), style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, dash: [3, 3].map { $0 * k })).opacity(needsDisplay ? 1 : 0)
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 6, y: 16, width: 42, height: 28), cornerSize: CGSize(width: 3, height: 3), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 9, y: 19, width: 36, height: 22), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular) }, viewBox: viewBox).fill(deskModeOn ? artColor(0x0D1117) : artColor(0x3B4A5E))
            ViewBoxShape(path: Path { p in p.addEllipse(in: CGRect(x: 23, y: 26, width: 8, height: 8)) }, viewBox: viewBox).stroke(artColor(0x6B7480), style: StrokeStyle(lineWidth: 1.6 * k)).opacity(deskModeOn ? 1 : 0)
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 21, y: 24)); p.addLine(to: CGPoint(x: 33, y: 36)) }, viewBox: viewBox).stroke(artColor(0xF4F4F2), style: StrokeStyle(lineWidth: 2 * k, lineCap: .round)).opacity(deskModeOn ? 1 : 0)
            ViewBoxShape(path: Path { p in p.addEllipse(in: CGRect(x: 23, y: 26, width: 8, height: 8)) }, viewBox: viewBox).fill(artColor(0xFFF8E6)).opacity(deskModeOn ? 0 : 1)
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 27, y: 23.5)); p.addLine(to: CGPoint(x: 27, y: 25)); p.move(to: CGPoint(x: 27, y: 35)); p.addLine(to: CGPoint(x: 27, y: 36.5)); p.move(to: CGPoint(x: 20.5, y: 30)); p.addLine(to: CGPoint(x: 22, y: 30)); p.move(to: CGPoint(x: 32, y: 30)); p.addLine(to: CGPoint(x: 33.5, y: 30)) }, viewBox: viewBox).stroke(artColor(0xFFF8E6), style: StrokeStyle(lineWidth: 1.4 * k, lineCap: .round)).opacity(needsDisplay && !deskModeOn ? 1 : 0)
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 4, y: 44)); p.addLine(to: CGPoint(x: 50, y: 44)); p.addLine(to: CGPoint(x: 54, y: 48)); p.addLine(to: CGPoint(x: 0, y: 48)); p.closeSubpath() }, viewBox: viewBox).fill(darkAppearance ? artColor(0xC9CDD3) : artColor(0xE6E7EA))
        }
        .frame(width: width, height: width * viewBox.height / viewBox.width)
    }
}

/// "How it switches off" card art: Disconnect (viewBox 112x46, Settings2-DeskMode).
struct MethodDisconnectArt: View {
    var width: CGFloat = 112
    private let viewBox = CGSize(width: 112, height: 46)
    private var k: CGFloat { width / viewBox.width }

    var body: some View {
        ZStack {
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 4, y: 6, width: 40, height: 26), cornerSize: CGSize(width: 3, height: 3), style: .circular) }, viewBox: viewBox).stroke(artColor(0x8A93A0), style: StrokeStyle(lineWidth: 2 * k, dash: [4, 3].map { $0 * k }))
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 4, y: 36)); p.addLine(to: CGPoint(x: 44, y: 36)); p.addLine(to: CGPoint(x: 48, y: 41)); p.addLine(to: CGPoint(x: 0, y: 41)); p.closeSubpath() }, viewBox: viewBox).fill(artColor(0xC9CDD3))
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 53, y: 20)); p.addLine(to: CGPoint(x: 67, y: 20)); p.move(to: CGPoint(x: 63, y: 15)); p.addLine(to: CGPoint(x: 68, y: 20)); p.addLine(to: CGPoint(x: 63, y: 25)) }, viewBox: viewBox).stroke(artColor(0xB07A00), style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round, lineJoin: .round))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 74, y: 2, width: 36, height: 26), cornerSize: CGSize(width: 3, height: 3), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 77, y: 5, width: 30, height: 20), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular) }, viewBox: viewBox).fill(artColor(0xFFBF00))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 80, y: 8, width: 12, height: 8), cornerSize: CGSize(width: 1, height: 1), style: .circular) }, viewBox: viewBox).fill(artColor(0xFFF8E6))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 90, y: 13, width: 13, height: 9), cornerSize: CGSize(width: 1, height: 1), style: .circular) }, viewBox: viewBox).fill(artColor(0xFFF8E6)).opacity(0.8)
            ViewBoxShape(path: Path { p in p.addRect(CGRect(x: 89, y: 28, width: 6, height: 8)) }, viewBox: viewBox).fill(artColor(0x2A3542))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 82, y: 36, width: 20, height: 3), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542))
        }
        .frame(width: width, height: width * viewBox.height / viewBox.width)
    }
}

/// "How it switches off" card art: Black out (viewBox 112x46, Settings2-DeskMode).
struct MethodBlackOutArt: View {
    var width: CGFloat = 112
    private let viewBox = CGSize(width: 112, height: 46)
    private var k: CGFloat { width / viewBox.width }

    var body: some View {
        ZStack {
            ZStack { ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 4, y: 6, width: 40, height: 26), cornerSize: CGSize(width: 3, height: 3), style: .circular) }, viewBox: viewBox).fill(artColor(0x0D1117)); ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 4, y: 6, width: 40, height: 26), cornerSize: CGSize(width: 3, height: 3), style: .circular) }, viewBox: viewBox).stroke(artColor(0x2A3542), style: StrokeStyle(lineWidth: 2 * k)) }
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 9, y: 11, width: 14, height: 9), cornerSize: CGSize(width: 1, height: 1), style: .circular) }, viewBox: viewBox).stroke(artColor(0x3A4452), style: StrokeStyle(lineWidth: 1.5 * k))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 20, y: 18, width: 17, height: 10), cornerSize: CGSize(width: 1, height: 1), style: .circular) }, viewBox: viewBox).stroke(artColor(0x3A4452), style: StrokeStyle(lineWidth: 1.5 * k))
            ViewBoxShape(path: Path { p in p.move(to: CGPoint(x: 4, y: 36)); p.addLine(to: CGPoint(x: 44, y: 36)); p.addLine(to: CGPoint(x: 48, y: 41)); p.addLine(to: CGPoint(x: 0, y: 41)); p.closeSubpath() }, viewBox: viewBox).fill(artColor(0xC9CDD3))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 74, y: 2, width: 36, height: 26), cornerSize: CGSize(width: 3, height: 3), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 77, y: 5, width: 30, height: 20), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular) }, viewBox: viewBox).fill(artColor(0xFFBF00))
            ViewBoxShape(path: Path { p in p.addRect(CGRect(x: 89, y: 28, width: 6, height: 8)) }, viewBox: viewBox).fill(artColor(0x2A3542))
            ViewBoxShape(path: Path { p in p.addRoundedRect(in: CGRect(x: 82, y: 36, width: 20, height: 3), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular) }, viewBox: viewBox).fill(artColor(0x2A3542))
        }
        .frame(width: width, height: width * viewBox.height / viewBox.width)
    }
}
