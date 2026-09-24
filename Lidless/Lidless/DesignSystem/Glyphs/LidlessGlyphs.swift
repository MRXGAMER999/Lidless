// Generated from the design canvas (design/canvas/*.dc.html); keep the geometry verbatim.
// Paths use the design's 24×24 viewBox; SVG arcs are converted to cubic Béziers.
import SwiftUI

/// Custom line glyphs from the Lidless design. Stroke with round caps and joins.
enum LidlessGlyph: CaseIterable, Sendable {
    /// Menu bar Normal; "Built-in Display" rows.
    case laptop
    /// Menu bar Desk Mode (solid screen).
    case laptopScreenFilled
    /// Menu bar Boost (sun in the screen; ring is stroked).
    case laptopBoost
    /// Desk Mode tab, HUD, onboarding tile.
    case laptopSlash
    /// Brightness slider, low end.
    case sunSmall
    /// Brightness tab, slider high end, F2 key, tiles.
    case sun
    /// External display rows, empty state.
    case monitor
    /// Popover settings button.
    case sliders
    /// "Keys & App" tab.
    case keyboard
    /// Boost callout.
    case flame
    /// Safety net (Settings2 fills it #FFBF00).
    case shield
    /// "Always" badge.
    case lock
    /// Guard rails: heat.
    case thermometer
    /// Guard rails: battery.
    case battery
    /// Guard rails: sleep/wake.
    case moon
    /// Note callout.
    case info
    /// Token menu.
    case chevronDown
    /// "Test the safety net" (filled, no stroke).
    case play

    /// Parts drawn as a stroke, in 24x24 grid units.
    nonisolated var strokePath: Path {
        switch self {
        case .laptop:
            Path { p in
                p.addRoundedRect(in: CGRect(x: 4, y: 6, width: 16, height: 10), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular)
                p.move(to: CGPoint(x: 2, y: 19))
                p.addLine(to: CGPoint(x: 22, y: 19))
            }
        case .laptopScreenFilled:
            Path { p in
                p.addRoundedRect(in: CGRect(x: 4, y: 6, width: 16, height: 10), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular)
                p.move(to: CGPoint(x: 2, y: 19))
                p.addLine(to: CGPoint(x: 22, y: 19))
            }
        case .laptopBoost:
            Path { p in
                p.addRoundedRect(in: CGRect(x: 4, y: 6, width: 16, height: 10), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular)
                p.move(to: CGPoint(x: 2, y: 19))
                p.addLine(to: CGPoint(x: 22, y: 19))
                p.addEllipse(in: CGRect(x: 10.4, y: 9.4, width: 3.2, height: 3.2))
                p.move(to: CGPoint(x: 12, y: 7.6))
                p.addLine(to: CGPoint(x: 12, y: 8))
                p.move(to: CGPoint(x: 12, y: 14))
                p.addLine(to: CGPoint(x: 12, y: 14.4))
                p.move(to: CGPoint(x: 8.6, y: 11))
                p.addLine(to: CGPoint(x: 9, y: 11))
                p.move(to: CGPoint(x: 15, y: 11))
                p.addLine(to: CGPoint(x: 15.4, y: 11))
            }
        case .laptopSlash:
            Path { p in
                p.addRoundedRect(in: CGRect(x: 4, y: 6, width: 16, height: 10), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular)
                p.move(to: CGPoint(x: 2, y: 19))
                p.addLine(to: CGPoint(x: 22, y: 19))
                p.move(to: CGPoint(x: 3, y: 3))
                p.addLine(to: CGPoint(x: 21, y: 21))
            }
        case .sunSmall:
            Path { p in
                p.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
            }
        case .sun:
            Path { p in
                p.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
                p.move(to: CGPoint(x: 12, y: 2))
                p.addLine(to: CGPoint(x: 12, y: 4))
                p.move(to: CGPoint(x: 12, y: 20))
                p.addLine(to: CGPoint(x: 12, y: 22))
                p.move(to: CGPoint(x: 2, y: 12))
                p.addLine(to: CGPoint(x: 4, y: 12))
                p.move(to: CGPoint(x: 20, y: 12))
                p.addLine(to: CGPoint(x: 22, y: 12))
                p.move(to: CGPoint(x: 4.9, y: 4.9))
                p.addLine(to: CGPoint(x: 6.3, y: 6.3))
                p.move(to: CGPoint(x: 17.7, y: 17.7))
                p.addLine(to: CGPoint(x: 19.1, y: 19.1))
                p.move(to: CGPoint(x: 4.9, y: 19.1))
                p.addLine(to: CGPoint(x: 6.3, y: 17.7))
                p.move(to: CGPoint(x: 17.7, y: 6.3))
                p.addLine(to: CGPoint(x: 19.1, y: 4.9))
            }
        case .monitor:
            Path { p in
                p.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 12), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular)
                p.move(to: CGPoint(x: 9, y: 20))
                p.addLine(to: CGPoint(x: 15, y: 20))
                p.move(to: CGPoint(x: 12, y: 16))
                p.addLine(to: CGPoint(x: 12, y: 20))
            }
        case .sliders:
            Path { p in
                p.move(to: CGPoint(x: 4, y: 7))
                p.addLine(to: CGPoint(x: 13, y: 7))
                p.move(to: CGPoint(x: 17, y: 7))
                p.addLine(to: CGPoint(x: 20, y: 7))
                p.move(to: CGPoint(x: 4, y: 17))
                p.addLine(to: CGPoint(x: 7, y: 17))
                p.move(to: CGPoint(x: 11, y: 17))
                p.addLine(to: CGPoint(x: 20, y: 17))
                p.addEllipse(in: CGRect(x: 13, y: 5, width: 4, height: 4))
                p.addEllipse(in: CGRect(x: 7, y: 15, width: 4, height: 4))
            }
        case .keyboard:
            Path { p in
                p.addRoundedRect(in: CGRect(x: 3, y: 6, width: 18, height: 12), cornerSize: CGSize(width: 2, height: 2), style: .circular)
                p.move(to: CGPoint(x: 7, y: 10))
                p.addLine(to: CGPoint(x: 7.01, y: 10))
                p.move(to: CGPoint(x: 11, y: 10))
                p.addLine(to: CGPoint(x: 11.01, y: 10))
                p.move(to: CGPoint(x: 15, y: 10))
                p.addLine(to: CGPoint(x: 15.01, y: 10))
                p.move(to: CGPoint(x: 7, y: 14))
                p.addLine(to: CGPoint(x: 17, y: 14))
            }
        case .flame:
            Path { p in
                p.move(to: CGPoint(x: 12, y: 3))
                p.addCurve(to: CGPoint(x: 17, y: 13), control1: CGPoint(x: 13, y: 6.5), control2: CGPoint(x: 17, y: 8.5))
                p.addCurve(to: CGPoint(x: 12, y: 18), control1: CGPoint(x: 17, y: 15.7614), control2: CGPoint(x: 14.7614, y: 18))
                p.addCurve(to: CGPoint(x: 7, y: 13), control1: CGPoint(x: 9.2386, y: 18), control2: CGPoint(x: 7, y: 15.7614))
                p.addCurve(to: CGPoint(x: 9.5, y: 8), control1: CGPoint(x: 7, y: 10.5), control2: CGPoint(x: 8.5, y: 9))
                p.addCurve(to: CGPoint(x: 12, y: 11), control1: CGPoint(x: 9.8, y: 9.8), control2: CGPoint(x: 10.7, y: 10.8))
                p.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 11.5, y: 8), control2: CGPoint(x: 12, y: 5.5))
                p.closeSubpath()
            }
        case .shield:
            Path { p in
                p.move(to: CGPoint(x: 12, y: 3))
                p.addLine(to: CGPoint(x: 19, y: 6))
                p.addLine(to: CGPoint(x: 19, y: 11))
                p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 19, y: 16), control2: CGPoint(x: 15.5, y: 19.5))
                p.addCurve(to: CGPoint(x: 5, y: 11), control1: CGPoint(x: 8.5, y: 19.5), control2: CGPoint(x: 5, y: 16))
                p.addLine(to: CGPoint(x: 5, y: 6))
                p.addLine(to: CGPoint(x: 12, y: 3))
                p.closeSubpath()
            }
        case .lock:
            Path { p in
                p.addRoundedRect(in: CGRect(x: 5, y: 11, width: 14, height: 9), cornerSize: CGSize(width: 2, height: 2), style: .circular)
                p.move(to: CGPoint(x: 8, y: 11))
                p.addLine(to: CGPoint(x: 8, y: 8))
                p.addCurve(to: CGPoint(x: 12, y: 4), control1: CGPoint(x: 8, y: 5.7909), control2: CGPoint(x: 9.7909, y: 4))
                p.addCurve(to: CGPoint(x: 16, y: 8), control1: CGPoint(x: 14.2091, y: 4), control2: CGPoint(x: 16, y: 5.7909))
                p.addLine(to: CGPoint(x: 16, y: 11))
            }
        case .thermometer:
            Path { p in
                p.move(to: CGPoint(x: 14, y: 14.8))
                p.addLine(to: CGPoint(x: 14, y: 5))
                p.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 14, y: 3.8954), control2: CGPoint(x: 13.1046, y: 3))
                p.addCurve(to: CGPoint(x: 10, y: 5), control1: CGPoint(x: 10.8954, y: 3), control2: CGPoint(x: 10, y: 3.8954))
                p.addLine(to: CGPoint(x: 10, y: 14.8))
                p.addCurve(to: CGPoint(x: 8.1363, y: 19.2994), control1: CGPoint(x: 8.4321, y: 15.7052), control2: CGPoint(x: 7.6677, y: 17.5506))
                p.addCurve(to: CGPoint(x: 12, y: 22.2641), control1: CGPoint(x: 8.6049, y: 21.0481), control2: CGPoint(x: 10.1896, y: 22.2641))
                p.addCurve(to: CGPoint(x: 15.8637, y: 19.2994), control1: CGPoint(x: 13.8104, y: 22.2641), control2: CGPoint(x: 15.3951, y: 21.0481))
                p.addCurve(to: CGPoint(x: 14, y: 14.8), control1: CGPoint(x: 16.3323, y: 17.5506), control2: CGPoint(x: 15.5679, y: 15.7052))
                p.closeSubpath()
            }
        case .battery:
            Path { p in
                p.addRoundedRect(in: CGRect(x: 3, y: 8, width: 16, height: 8), cornerSize: CGSize(width: 2, height: 2), style: .circular)
                p.move(to: CGPoint(x: 21, y: 11))
                p.addLine(to: CGPoint(x: 21, y: 13))
                p.move(to: CGPoint(x: 6, y: 11))
                p.addLine(to: CGPoint(x: 6, y: 13))
            }
        case .moon:
            Path { p in
                p.move(to: CGPoint(x: 20, y: 14.5))
                p.addCurve(to: CGPoint(x: 11.1997, y: 12.8003), control1: CGPoint(x: 16.9948, y: 15.7841), control2: CGPoint(x: 13.5106, y: 15.1112))
                p.addCurve(to: CGPoint(x: 9.5, y: 4), control1: CGPoint(x: 8.8888, y: 10.4894), control2: CGPoint(x: 8.2159, y: 7.0052))
                p.addCurve(to: CGPoint(x: 4.7158, y: 12.4301), control1: CGPoint(x: 6.1906, y: 5.4141), control2: CGPoint(x: 4.2329, y: 8.8639))
                p.addCurve(to: CGPoint(x: 11.5699, y: 19.2842), control1: CGPoint(x: 5.1988, y: 15.9964), control2: CGPoint(x: 8.0036, y: 18.8012))
                p.addCurve(to: CGPoint(x: 20, y: 14.5), control1: CGPoint(x: 15.1361, y: 19.7671), control2: CGPoint(x: 18.5859, y: 17.8094))
                p.closeSubpath()
            }
        case .info:
            Path { p in
                p.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
                p.move(to: CGPoint(x: 12, y: 8))
                p.addLine(to: CGPoint(x: 12, y: 13))
                p.move(to: CGPoint(x: 12, y: 16.5))
                p.addLine(to: CGPoint(x: 12, y: 16.51))
            }
        case .chevronDown:
            Path { p in
                p.move(to: CGPoint(x: 6, y: 9))
                p.addLine(to: CGPoint(x: 12, y: 15))
                p.addLine(to: CGPoint(x: 18, y: 9))
            }
        case .play:
            Path()
        }
    }

    /// Parts filled with the foreground colour (`fill="currentColor"` in the design), in 24x24 grid units.
    nonisolated var solidPath: Path {
        switch self {
        case .laptop:
            Path()
        case .laptopScreenFilled:
            Path { p in
                p.addRoundedRect(in: CGRect(x: 4, y: 6, width: 16, height: 10), cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular)
            }
        case .laptopBoost:
            Path()
        case .laptopSlash:
            Path()
        case .sunSmall:
            Path()
        case .sun:
            Path()
        case .monitor:
            Path()
        case .sliders:
            Path()
        case .keyboard:
            Path()
        case .flame:
            Path()
        case .shield:
            Path()
        case .lock:
            Path()
        case .thermometer:
            Path()
        case .battery:
            Path()
        case .moon:
            Path()
        case .info:
            Path()
        case .chevronDown:
            Path()
        case .play:
            Path { p in
                p.move(to: CGPoint(x: 7, y: 4))
                p.addLine(to: CGPoint(x: 20, y: 12))
                p.addLine(to: CGPoint(x: 7, y: 20))
                p.closeSubpath()
            }
        }
    }
}

/// Draws a path authored in a `viewBox` of the given size into the proposed rect (aspect-fit, centred).
struct ViewBoxShape: Shape {
    var path: Path
    var viewBox: CGSize = CGSize(width: 24, height: 24)

    nonisolated func path(in rect: CGRect) -> Path {
        let s = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let dx = rect.minX + (rect.width - viewBox.width * s) / 2
        let dy = rect.minY + (rect.height - viewBox.height * s) / 2
        return path.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: dx, ty: dy))
    }
}

/// A Lidless glyph at a design size. `lineWidth` is in 24-grid units exactly as written in the
/// canvas (1.8, 1.9, 2, 2.2, 2.4, 2.6); it scales with `size` like an SVG stroke does.
/// Colour comes from the environment's foreground style (`.foregroundStyle(...)`, macOS 12).
struct GlyphView: View {
    let glyph: LidlessGlyph
    var size: CGFloat
    var lineWidth: CGFloat = 1.8
    /// Interior fill behind the stroke, e.g. the Settings2 shield (`fill="#FFBF00"`).
    var interiorFill: Color? = nil

    var body: some View {
        ZStack {
            // Always present (clear when unused) so the view keeps one structural identity.
            ViewBoxShape(path: glyph.strokePath).fill(interiorFill ?? .clear)
            ViewBoxShape(path: glyph.solidPath).fill(.foreground)
            ViewBoxShape(path: glyph.strokePath)
                .stroke(.foreground, style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
