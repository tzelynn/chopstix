import SwiftUI

/// One tapered chopstick from its thick end `a` to its tip `b`, with a lacquered band.
struct Chopstick {
    var a: CGPoint
    var b: CGPoint
    var thick: CGFloat = 6.5
    var thin: CGFloat = 3.2
    var lacquer: Color

    private func outline(from a: CGPoint, to b: CGPoint, wa: CGFloat, wb: CGFloat, roundTip: Bool) -> Path {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(hypot(dx, dy), 0.001)
        let ux = dx / len, uy = dy / len
        let nx = -uy, ny = ux
        var p = Path()
        p.move(to: CGPoint(x: a.x + nx * wa / 2, y: a.y + ny * wa / 2))
        p.addLine(to: CGPoint(x: b.x + nx * wb / 2, y: b.y + ny * wb / 2))
        if roundTip {
            p.addQuadCurve(
                to: CGPoint(x: b.x - nx * wb / 2, y: b.y - ny * wb / 2),
                control: CGPoint(x: b.x + ux * wb * 0.9, y: b.y + uy * wb * 0.9)
            )
        } else {
            p.addLine(to: CGPoint(x: b.x - nx * wb / 2, y: b.y - ny * wb / 2))
        }
        p.addLine(to: CGPoint(x: a.x - nx * wa / 2, y: a.y - ny * wa / 2))
        p.addQuadCurve(
            to: CGPoint(x: a.x + nx * wa / 2, y: a.y + ny * wa / 2),
            control: CGPoint(x: a.x - ux * wa * 0.35, y: a.y - uy * wa * 0.35)
        )
        p.closeSubpath()
        return p
    }

    private func point(at t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func width(at t: CGFloat) -> CGFloat { thick + (thin - thick) * t }

    func draw(in ctx: GraphicsContext) {
        let body = outline(from: a, to: b, wa: thick, wb: thin, roundTip: true)

        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.18), radius: 1.6, x: 0, y: 1.2))
        shadowed.fill(body, with: .color(Theme.wood))

        // Soft highlight along the upper edge for a rounded, wooden feel.
        let top = outline(from: a, to: b, wa: thick * 0.35, wb: thin * 0.3, roundTip: true)
            .offsetBy(dx: 0, dy: -thick * 0.18)
        ctx.fill(top, with: .color(Theme.woodLight.opacity(0.9)))

        // Lacquered band at the thick end, finished with a thin dark ring.
        let bandEnd: CGFloat = 0.2
        let band = outline(from: a, to: point(at: bandEnd), wa: thick, wb: width(at: bandEnd), roundTip: false)
        ctx.fill(band, with: .color(lacquer))
        ctx.fill(
            outline(from: a, to: point(at: bandEnd), wa: thick * 0.3, wb: width(at: bandEnd) * 0.3, roundTip: false)
                .offsetBy(dx: 0, dy: -thick * 0.18),
            with: .color(.white.opacity(0.35))
        )
        let ring = outline(from: point(at: bandEnd), to: point(at: bandEnd + 0.012),
                           wa: width(at: bandEnd), wb: width(at: bandEnd + 0.012), roundTip: false)
        ctx.fill(ring, with: .color(Theme.woodDark.opacity(0.8)))
    }
}

/// The pair of chopsticks pinching a sticky note's top edge. Thick ends on the left,
/// converging toward the tips on the right. `layer` picks the stick behind or in front of the note.
struct ChopsticksView: View {
    enum Layer { case back, front }

    let layer: Layer
    let lacquer: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            switch layer {
            case .back:
                Chopstick(a: CGPoint(x: 3, y: 9), b: CGPoint(x: w - 5, y: 15.5), lacquer: lacquer).draw(in: ctx)
            case .front:
                Chopstick(a: CGPoint(x: 5, y: 27), b: CGPoint(x: w - 5, y: 20.5), lacquer: lacquer).draw(in: ctx)
            }
        }
        .frame(height: StickyLayout.dragStripHeight)
        .allowsHitTesting(false)
    }
}

/// A tiny crossed-chopsticks glyph used for "on screen" badges.
struct ChopsticksGlyph: View {
    var color: Color = Theme.inkSoft

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var p = Path()
            p.move(to: CGPoint(x: w * 0.12, y: h * 0.9))
            p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.08))
            p.move(to: CGPoint(x: w * 0.36, y: h * 0.94))
            p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.16))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: max(1.2, w * 0.11), lineCap: .round))
        }
    }
}
