import SwiftUI

/// Small hand-drawn garnishes for each noodle flavour, tucked into the note's corners.
struct FlavorDecoration: View {
    let flavor: Flavor
    /// Distance of the top-right garnish from the top edge (clears the chopsticks on sticky notes).
    var topInset: CGFloat = 40
    /// Distance of the bottom-left garnishes from the bottom edge (clears the toolbar).
    var bottomInset: CGFloat = 0
    var scale: CGFloat = 1
    var showsTopGarnish = true

    var body: some View {
        Canvas { ctx, size in
            for placement in Garnish.placements(for: flavor) where showsTopGarnish || placement.corner == .bottomLeading {
                var c = ctx
                let origin: CGPoint = switch placement.corner {
                case .bottomLeading:
                    CGPoint(x: placement.offset.x * scale, y: size.height - bottomInset - placement.offset.y * scale)
                case .topTrailing:
                    CGPoint(x: size.width - placement.offset.x * scale, y: topInset + (placement.offset.y - 40) * scale)
                }
                c.translateBy(x: origin.x, y: origin.y)
                c.rotate(by: .degrees(placement.rotation))
                c.scaleBy(x: placement.scale * scale * (placement.flipped ? -1 : 1), y: placement.scale * scale)
                placement.garnish.draw(in: c, flavor: flavor)
            }
        }
        .allowsHitTesting(false)
    }
}

enum Garnish {
    case prawn, naruto, egg, scallion, tofuPuff, chili, basil, lime, mushroom, sesame, noodles, steam

    struct Placement {
        enum Corner { case bottomLeading, topTrailing }
        var garnish: Garnish
        var corner: Corner
        /// From the corner, pointing into the note.
        var offset: CGPoint
        var scale: CGFloat = 1
        var rotation: Double = 0
        var flipped = false
    }

    static func placements(for flavor: Flavor) -> [Placement] {
        typealias P = Placement
        switch flavor {
        case .prawnMee: return [
            P(garnish: .prawn, corner: .bottomLeading, offset: CGPoint(x: 26, y: 24)),
            P(garnish: .prawn, corner: .bottomLeading, offset: CGPoint(x: 56, y: 15), scale: 0.6, rotation: -18),
            P(garnish: .prawn, corner: .topTrailing, offset: CGPoint(x: 22, y: 42), scale: 0.55, rotation: 12, flipped: true),
        ]
        case .ramen: return [
            P(garnish: .naruto, corner: .bottomLeading, offset: CGPoint(x: 24, y: 24)),
            P(garnish: .egg, corner: .bottomLeading, offset: CGPoint(x: 52, y: 16), scale: 0.85, rotation: -14),
            P(garnish: .naruto, corner: .topTrailing, offset: CGPoint(x: 22, y: 42), scale: 0.6, rotation: 40),
        ]
        case .matchaSoba: return [
            P(garnish: .scallion, corner: .bottomLeading, offset: CGPoint(x: 19, y: 22)),
            P(garnish: .scallion, corner: .bottomLeading, offset: CGPoint(x: 36, y: 13), scale: 0.7),
            P(garnish: .scallion, corner: .bottomLeading, offset: CGPoint(x: 35, y: 33), scale: 0.8),
            P(garnish: .scallion, corner: .bottomLeading, offset: CGPoint(x: 53, y: 19), scale: 0.55),
            P(garnish: .scallion, corner: .topTrailing, offset: CGPoint(x: 21, y: 40), scale: 0.7),
            P(garnish: .scallion, corner: .topTrailing, offset: CGPoint(x: 35, y: 48), scale: 0.5),
        ]
        case .laksa: return [
            P(garnish: .tofuPuff, corner: .bottomLeading, offset: CGPoint(x: 23, y: 23), rotation: -10),
            P(garnish: .chili, corner: .bottomLeading, offset: CGPoint(x: 50, y: 18), scale: 0.95, rotation: 28),
            P(garnish: .tofuPuff, corner: .topTrailing, offset: CGPoint(x: 22, y: 42), scale: 0.6, rotation: 14),
        ]
        case .pho: return [
            P(garnish: .basil, corner: .bottomLeading, offset: CGPoint(x: 22, y: 25), rotation: -35),
            P(garnish: .lime, corner: .bottomLeading, offset: CGPoint(x: 50, y: 16), scale: 0.9, rotation: 8),
            P(garnish: .basil, corner: .topTrailing, offset: CGPoint(x: 22, y: 42), scale: 0.6, rotation: 50),
        ]
        case .japchae: return [
            P(garnish: .mushroom, corner: .bottomLeading, offset: CGPoint(x: 24, y: 22)),
            P(garnish: .sesame, corner: .bottomLeading, offset: CGPoint(x: 50, y: 15)),
            P(garnish: .mushroom, corner: .topTrailing, offset: CGPoint(x: 22, y: 44), scale: 0.6, rotation: 14),
            P(garnish: .sesame, corner: .topTrailing, offset: CGPoint(x: 40, y: 50), scale: 0.8, rotation: 90),
        ]
        case .udon: return [
            P(garnish: .noodles, corner: .bottomLeading, offset: CGPoint(x: 32, y: 20)),
            P(garnish: .steam, corner: .bottomLeading, offset: CGPoint(x: 22, y: 42), scale: 0.8),
            P(garnish: .steam, corner: .topTrailing, offset: CGPoint(x: 22, y: 44), scale: 0.65),
        ]
        }
    }

    // MARK: Drawing (each garnish is centred on the origin, roughly 30pt across)

    func draw(in c: GraphicsContext, flavor: Flavor) {
        let accent = flavor.accent, soft = flavor.accentSoft
        let cream = Color(hex: 0xFFFDF7)
        let round = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)

        switch self {
        case .prawn:
            // Tail fan, then body segments from tail to head so the head sits on top.
            let tail = CGPoint(x: 3, y: 10)
            for angle in [125.0, 175.0] {
                var t = c
                t.translateBy(x: tail.x, y: tail.y)
                t.rotate(by: .degrees(angle))
                t.fill(Path(ellipseIn: CGRect(x: -2, y: -1, width: 8, height: 4.2)), with: .color(soft))
            }
            let segments: [(angle: Double, r: CGFloat)] = [(35, 3.4), (350, 4.2), (305, 4.9), (260, 5.5), (205, 6.6)]
            for (i, seg) in segments.enumerated() {
                let rad = seg.angle * .pi / 180
                let center = CGPoint(x: 8.5 * cos(rad), y: 8.5 * sin(rad))
                let rect = CGRect(x: center.x - seg.r, y: center.y - seg.r, width: seg.r * 2, height: seg.r * 2)
                c.fill(Path(ellipseIn: rect), with: .color(i == segments.count - 1 ? accent : accent.opacity(0.92)))
                c.stroke(Path(ellipseIn: rect), with: .color(flavor.paper), lineWidth: 1.1)
            }
            // Antennae, eye and a blush.
            var antennae = Path()
            antennae.move(to: CGPoint(x: -10, y: -6.5))
            antennae.addQuadCurve(to: CGPoint(x: -19, y: -15), control: CGPoint(x: -18, y: -6))
            antennae.move(to: CGPoint(x: -9, y: -7.5))
            antennae.addQuadCurve(to: CGPoint(x: -13, y: -18), control: CGPoint(x: -15, y: -11))
            c.stroke(antennae, with: .color(accent), style: round)
            c.fill(Path(ellipseIn: CGRect(x: -10.6, y: -6.4, width: 2.4, height: 2.4)), with: .color(Theme.ink))
            c.fill(Path(ellipseIn: CGRect(x: -9.5, y: -2.4, width: 3.6, height: 2)), with: .color(.white.opacity(0.45)))

        case .naruto:
            let rect = CGRect(x: -10, y: -10, width: 20, height: 20)
            c.fill(Path(ellipseIn: rect), with: .color(cream))
            c.stroke(Path(ellipseIn: rect), with: .color(flavor.paperDeep), lineWidth: 1.2)
            var spiral = Path()
            let turns = 2.3
            for step in 0...60 {
                let t = Double(step) / 60
                let angle = t * turns * 2 * .pi
                let r = 0.8 + 6.4 * t
                let p = CGPoint(x: r * cos(angle), y: r * sin(angle))
                step == 0 ? spiral.move(to: p) : spiral.addLine(to: p)
            }
            c.stroke(spiral, with: .color(accent), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))

        case .egg:
            c.fill(Path(ellipseIn: CGRect(x: -11, y: -8, width: 22, height: 16)), with: .color(cream))
            c.stroke(Path(ellipseIn: CGRect(x: -11, y: -8, width: 22, height: 16)), with: .color(flavor.paperDeep), lineWidth: 1)
            c.fill(Path(ellipseIn: CGRect(x: -5.5, y: -5, width: 11, height: 10)), with: .color(soft))
            c.fill(Path(ellipseIn: CGRect(x: -3, y: -3.4, width: 3, height: 2.2)), with: .color(.white.opacity(0.6)))

        case .scallion:
            let outer = CGRect(x: -5, y: -5, width: 10, height: 10)
            c.fill(Path(ellipseIn: outer), with: .color(soft.opacity(0.7)))
            c.stroke(Path(ellipseIn: outer), with: .color(accent), lineWidth: 2.2)
            c.stroke(Path(ellipseIn: outer.insetBy(dx: 2.8, dy: 2.8)), with: .color(accent.opacity(0.5)), lineWidth: 0.9)

        case .tofuPuff:
            let rect = CGRect(x: -7.5, y: -7, width: 15, height: 14)
            c.fill(Path(roundedRect: rect, cornerRadius: 4.5), with: .color(accent))
            c.fill(Path(roundedRect: CGRect(x: -5.5, y: -5, width: 6, height: 3.4), cornerRadius: 1.7), with: .color(.white.opacity(0.35)))
            for dot in [CGPoint(x: 2.5, y: 1), CGPoint(x: -2, y: 3), CGPoint(x: 4, y: 4.5), CGPoint(x: -4, y: 0)] {
                c.fill(Path(ellipseIn: CGRect(x: dot.x - 0.7, y: dot.y - 0.7, width: 1.4, height: 1.4)), with: .color(.black.opacity(0.12)))
            }

        case .chili:
            var pod = Path()
            pod.move(to: CGPoint(x: -2.6, y: -6))
            pod.addQuadCurve(to: CGPoint(x: 2.5, y: 12), control: CGPoint(x: -7.5, y: 5))
            pod.addQuadCurve(to: CGPoint(x: 2.8, y: -6), control: CGPoint(x: 1.2, y: 2))
            pod.closeSubpath()
            c.fill(pod, with: .color(soft))
            c.fill(Path(ellipseIn: CGRect(x: -3.2, y: -7.6, width: 6.4, height: 3)), with: .color(Color(hex: 0x8DB678)))
            var stem = Path()
            stem.move(to: CGPoint(x: 0, y: -7))
            stem.addQuadCurve(to: CGPoint(x: 2.8, y: -11.5), control: CGPoint(x: -0.5, y: -10.5))
            c.stroke(stem, with: .color(Color(hex: 0x7EA866)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            c.fill(Path(ellipseIn: CGRect(x: -3.5, y: -2, width: 1.6, height: 4)), with: .color(.white.opacity(0.4)))

        case .basil:
            var leaf = Path()
            leaf.move(to: CGPoint(x: 0, y: -11))
            leaf.addQuadCurve(to: CGPoint(x: 0, y: 10), control: CGPoint(x: 11, y: -1))
            leaf.addQuadCurve(to: CGPoint(x: 0, y: -11), control: CGPoint(x: -11, y: -1))
            c.fill(leaf, with: .color(accent))
            var veins = Path()
            veins.move(to: CGPoint(x: 0, y: -8))
            veins.addLine(to: CGPoint(x: 0, y: 12))
            for y in [-3.0, 2.0] {
                veins.move(to: CGPoint(x: 0, y: y + 2))
                veins.addLine(to: CGPoint(x: 3.5, y: y - 1))
                veins.move(to: CGPoint(x: 0, y: y + 2))
                veins.addLine(to: CGPoint(x: -3.5, y: y - 1))
            }
            c.stroke(veins, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))

        case .lime:
            var rind = Path()
            rind.addArc(center: CGPoint(x: 0, y: 3), radius: 10, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            rind.closeSubpath()
            c.fill(rind, with: .color(soft))
            var flesh = Path()
            flesh.addArc(center: CGPoint(x: 0, y: 3), radius: 8, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            flesh.closeSubpath()
            c.fill(flesh, with: .color(Color(hex: 0xEEF5C8)))
            var segments = Path()
            for angle in [216.0, 252.0, 288.0, 324.0] {
                let rad = angle * .pi / 180
                segments.move(to: CGPoint(x: 0, y: 3))
                segments.addLine(to: CGPoint(x: 7 * cos(rad), y: 3 + 7 * sin(rad)))
            }
            c.stroke(segments, with: .color(soft.opacity(0.8)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))

        case .mushroom:
            c.fill(Path(roundedRect: CGRect(x: -3.2, y: -1, width: 6.4, height: 10), cornerRadius: 2.8), with: .color(cream))
            c.stroke(Path(roundedRect: CGRect(x: -3.2, y: -1, width: 6.4, height: 10), cornerRadius: 2.8), with: .color(flavor.paperDeep), lineWidth: 0.9)
            var cap = Path()
            cap.move(to: CGPoint(x: -11, y: 1))
            cap.addCurve(to: CGPoint(x: 11, y: 1), control1: CGPoint(x: -11, y: -12), control2: CGPoint(x: 11, y: -12))
            cap.addQuadCurve(to: CGPoint(x: -11, y: 1), control: CGPoint(x: 0, y: 3.5))
            cap.closeSubpath()
            c.fill(cap, with: .color(soft))
            var star = Path()
            star.move(to: CGPoint(x: -2.8, y: -6.5)); star.addLine(to: CGPoint(x: 2.8, y: -2.5))
            star.move(to: CGPoint(x: 2.8, y: -6.5)); star.addLine(to: CGPoint(x: -2.8, y: -2.5))
            c.stroke(star, with: .color(cream.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        case .sesame:
            let seeds: [(CGPoint, Double)] = [(CGPoint(x: -6, y: -2), 20), (CGPoint(x: 0, y: 3), -30), (CGPoint(x: 5, y: -3), 60), (CGPoint(x: 9, y: 4), 10), (CGPoint(x: -2, y: -7), -60)]
            for (point, angle) in seeds {
                var s = c
                s.translateBy(x: point.x, y: point.y)
                s.rotate(by: .degrees(angle))
                let seed = Path(ellipseIn: CGRect(x: -1.9, y: -1.1, width: 3.8, height: 2.2))
                s.fill(seed, with: .color(cream))
                s.stroke(seed, with: .color(soft.opacity(0.8)), lineWidth: 0.6)
            }

        case .noodles:
            for row in 0..<3 {
                var wave = Path()
                let y0 = CGFloat(row - 1) * 5.5
                for step in 0...40 {
                    let t = CGFloat(step) / 40
                    let p = CGPoint(x: -15 + 30 * t, y: y0 + 2.4 * sin(t * .pi * 3 + CGFloat(row) * 0.9))
                    step == 0 ? wave.move(to: p) : wave.addLine(to: p)
                }
                c.stroke(wave, with: .color(accent), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
            }

        case .steam:
            for (dx, height) in [(-4.0, 1.0), (4.0, 0.75)] {
                var curl = Path()
                curl.move(to: CGPoint(x: dx, y: 9 * height))
                curl.addCurve(to: CGPoint(x: dx, y: -9 * height),
                              control1: CGPoint(x: dx + 6, y: 3 * height),
                              control2: CGPoint(x: dx - 6, y: -3 * height))
                c.stroke(curl, with: .color(soft), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            }
        }
    }
}
