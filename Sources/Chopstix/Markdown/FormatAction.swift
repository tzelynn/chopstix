import AppKit

/// Inline and list formatting commands, for the Format menu and the note toolbars.
/// Answered by `MarkdownTextView`.
enum FormatAction: CaseIterable, Identifiable {
    case bold, italic, strikethrough, bulletList, checklist

    var id: Self { self }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .bulletList: "Bulleted List"
        case .checklist: "Checklist"
        }
    }

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .bulletList: "list.bullet"
        case .checklist: "checklist"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .strikethrough: "x"
        case .bulletList: "7"
        case .checklist: "l"
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .bold, .italic: [.command]
        case .strikethrough, .bulletList, .checklist: [.command, .shift]
        }
    }

    var shortcutHint: String {
        let shift = modifiers.contains(.shift) ? "⇧" : ""
        return "\(title)  \(shift)⌘\(keyEquivalent.uppercased())"
    }

    /// Selector sent down the responder chain by the Format menu.
    var selector: Selector {
        switch self {
        case .bold: #selector(MarkdownTextView.cxToggleBold(_:))
        case .italic: #selector(MarkdownTextView.cxToggleItalic(_:))
        case .strikethrough: #selector(MarkdownTextView.cxToggleStrikethrough(_:))
        case .bulletList: #selector(MarkdownTextView.cxToggleBulletList(_:))
        case .checklist: #selector(MarkdownTextView.cxToggleChecklist(_:))
        }
    }
}
