import SwiftUI

/// The app icon: the vector artwork in Resources/AppIcon.svg on a macOS-style squircle, so it can be
/// rendered at any size (and exported for the bundle).
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

                if let artwork = AppIcon.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 680 * s, height: 680 * s)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

enum AppIcon {
    /// Inside the .app, build_app.sh copies the SVG into Contents/Resources; under `swift run` it lives in
    /// SwiftPM's resource bundle. (Bundle.module is only touched in the latter case — it traps if missing.)
    static let artwork: NSImage? = {
        let url = Bundle.main.url(forResource: "AppIcon", withExtension: "svg")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "svg")
        guard let image = url.flatMap(NSImage.init(contentsOf:)) else { return nil }
        // The SVG's intrinsic size is 48pt; SwiftUI rasterises at that size, so enlarge it to stay crisp.
        image.size = NSSize(width: 1024, height: 1024)
        return image
    }()

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
