import AppKit

/// The house typography for note text.
enum NoteTextStyle {
    static let fontSize: CGFloat = 14
    static let ink = NSColor(hex: 0x4B3A33)
    static let inkChecked = NSColor(hex: 0x4B3A33, alpha: 0.42)
    /// Slant for fonts with no true italic (SF Rounded, SF Mono).
    static let obliqueness: CGFloat = 0.16
}
