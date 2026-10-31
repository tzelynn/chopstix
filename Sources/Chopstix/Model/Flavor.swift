import SwiftUI

/// A sticky note design. Each flavour is a different Asian noodle.
enum Flavor: String, Codable, CaseIterable, Identifiable {
    case prawnMee, ramen, matchaSoba, laksa, pho, japchae, udon

    var id: String { rawValue }

    var name: String {
        switch self {
        case .prawnMee: "Prawn Mee"
        case .ramen: "Ramen"
        case .matchaSoba: "Matcha Soba"
        case .laksa: "Laksa"
        case .pho: "Pho"
        case .japchae: "Japchae"
        case .udon: "Udon"
        }
    }

    var nativeName: String {
        switch self {
        case .prawnMee: "虾面"
        case .ramen: "ラーメン"
        case .matchaSoba: "茶そば"
        case .laksa: "叻沙"
        case .pho: "phở"
        case .japchae: "잡채"
        case .udon: "うどん"
        }
    }

    /// Default one-line menu description shown on the board (users can rewrite it).
    var blurb: String {
        switch self {
        case .prawnMee: "rich prawn broth, a few curly friends"
        case .ramen: "naruto swirls & a jammy egg"
        case .matchaSoba: "cool green tea noodles, scallions on top"
        case .laksa: "coconut curry, tofu puffs, a little heat"
        case .pho: "clear broth, thai basil & lime"
        case .japchae: "glass noodles, shiitake & sesame"
        case .udon: "thick, chewy, gently steaming"
        }
    }

    /// Note background.
    var paper: Color { Color(hex: palette.paper) }
    /// Slightly deeper paper, for the folded corner and outlines.
    var paperDeep: Color { Color(hex: palette.deep) }
    /// Main illustration colour.
    var accent: Color { Color(hex: palette.accent) }
    /// Secondary illustration colour.
    var accentSoft: Color { Color(hex: palette.soft) }

    /// Band on the chopsticks. Udon's noodle colour is too close to the wood, so it borrows the steam blue.
    var lacquer: Color { self == .udon ? Color(hex: 0xA9BCCD) : accent }

    var nsAccent: NSColor { NSColor(hex: palette.accent) }
    var nsAccentSoft: NSColor { NSColor(hex: palette.soft) }
    var nsPaper: NSColor { NSColor(hex: palette.paper) }
    var nsPaperDeep: NSColor { NSColor(hex: palette.deep) }
    var nsLacquer: NSColor { self == .udon ? NSColor(hex: 0xA9BCCD) : nsAccent }

    private var palette: (paper: UInt32, deep: UInt32, accent: UInt32, soft: UInt32) {
        switch self {
        case .prawnMee: (0xFDE4DA, 0xF5CBBC, 0xF0896B, 0xF8B8A2)
        case .ramen: (0xFCF1D3, 0xF1DFB0, 0xEE9AAA, 0xF6BD52)
        case .matchaSoba: (0xE4EFD9, 0xCDDEBF, 0x86B26F, 0xC7DDB4)
        case .laksa: (0xFCE7CF, 0xF3D1AA, 0xE9AE4F, 0xE8705A)
        case .pho: (0xDFF1EA, 0xC3E2D6, 0x6EB48F, 0xBCD873)
        case .japchae: (0xECE5F5, 0xD9CDEB, 0xB7A0D8, 0xC9A78E)
        case .udon: (0xF7F2E8, 0xE8DECB, 0xE0C99C, 0xBCCAD6)
        }
    }

    /// The flavour that follows this one, used to vary new notes.
    var next: Flavor {
        let all = Flavor.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
