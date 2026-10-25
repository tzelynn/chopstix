import SwiftUI

enum Theme {
    static let ink = Color(hex: 0x4B3A33)
    static let inkSoft = Color(hex: 0x8C7B70)
    static let inkFaint = Color(hex: 0xB9AA9C)

    static let menuPaper = Color(hex: 0xFBF6EC)
    static let menuPaperDeep = Color(hex: 0xF3EADA)
    static let menuRule = Color(hex: 0xD9C9AE)
    static let menuStamp = Color(hex: 0xC9644E)

    static let wood = Color(hex: 0xE2C29A)
    static let woodLight = Color(hex: 0xF1DDBF)
    static let woodDark = Color(hex: 0xBF9670)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Sticky note window geometry. The window is larger than the note so the chopsticks
/// can overhang it and the shadow isn't clipped.
enum StickyLayout {
    static let insets = EdgeInsets(top: 16, leading: 12, bottom: 18, trailing: 12)
    /// Height of the drag strip at the top of the window (chopsticks + top edge of the note).
    static let dragStripHeight: CGFloat = 34
    /// Space above the text inside the note, clear of the front chopstick.
    static let textTopPadding: CGFloat = 20
    static let defaultSize = CGSize(width: 260, height: 264)
    static let minSize = CGSize(width: 230, height: 160)
    static let foldSize: CGFloat = 18
    static let cornerRadius: CGFloat = 5
}

/// A note's paper: a rounded rectangle with the bottom-right corner folded away.
struct NoteShape: Shape {
    var fold: CGFloat = StickyLayout.foldSize
    var radius: CGFloat = StickyLayout.cornerRadius

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = radius
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The little flap that makes the folded corner.
struct FoldFlap: View {
    let flavor: Flavor
    var size: CGFloat = StickyLayout.foldSize

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: size, y: 0))
            p.addLine(to: CGPoint(x: 0, y: size))
            p.closeSubpath()
        }
        .fill(flavor.paperDeep)
        .shadow(color: .black.opacity(0.12), radius: 1.5, x: -0.5, y: -0.5)
        .frame(width: size, height: size)
    }
}

/// Paper fill with a faint top highlight, shared by sticky notes and board cards.
struct NotePaper: View {
    let flavor: Flavor
    var fold: CGFloat = StickyLayout.foldSize

    var body: some View {
        NoteShape(fold: fold)
            .fill(flavor.paper)
            .overlay(
                NoteShape(fold: fold).fill(
                    LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0)], startPoint: .top, endPoint: .center)
                )
            )
            .overlay(alignment: .bottomTrailing) { FoldFlap(flavor: flavor, size: fold) }
    }
}
