import SwiftUI

/// The app icon, drawn in code so it can be rendered at any size (and exported for the bundle).
struct AppIconView: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 1024
            ZStack {
                // macOS icon grid: 824pt squircle centred in 1024.
                RoundedRectangle(cornerRadius: 185 * s, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xFFFBF3), Color(hex: 0xF4E8D4)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 824 * s, height: 824 * s)
                    .shadow(color: .black.opacity(0.22), radius: 18 * s, y: 10 * s)

                ZStack(alignment: .top) {
                    ChopsticksView(layer: .back, lacquer: Flavor.prawnMee.accent)
                    NotePaper(flavor: .prawnMee)
                        .overlay { FlavorDecoration(flavor: .prawnMee, topInset: 40, scale: 1.25) }
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 9) {
                                Capsule().fill(Theme.ink.opacity(0.35)).frame(width: 140, height: 9)
                                Capsule().fill(Theme.ink.opacity(0.2)).frame(width: 110, height: 8)
                                Capsule().fill(Theme.ink.opacity(0.2)).frame(width: 125, height: 8)
                            }
                            .padding(.top, 40)
                            .padding(.leading, 24)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
                        .padding(StickyLayout.insets)
                    ChopsticksView(layer: .front, lacquer: Flavor.prawnMee.accent)
                }
                .frame(width: 230, height: 230)
                .scaleEffect(2.55 * s)
                .rotationEffect(.degrees(-4))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

enum AppIcon {
    @MainActor
    static func image(size: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content: AppIconView().frame(width: size, height: size))
        renderer.scale = 1
        return renderer.nsImage ?? NSImage()
    }

    /// Two chopsticks, as a template image for the menu bar.
    static func statusBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: 3, y: 2.5))
            path.line(to: NSPoint(x: 13.5, y: 16))
            path.move(to: NSPoint(x: 7, y: 2))
            path.line(to: NSPoint(x: 16, y: 14.5))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
