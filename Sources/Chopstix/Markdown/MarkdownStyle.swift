import AppKit

extension NSAttributedString.Key {
    /// Markdown syntax that `MarkdownLayoutManager` hides away from the line being edited.
    static let cxHidden = NSAttributedString.Key("chopstix.hidden")
    /// Something `MarkdownLayoutManager` draws behind the text (a `MarkdownDecoration` raw value).
    static let cxDecoration = NSAttributedString.Key("chopstix.decoration")
    /// A link's URL. Not `.link`, which NSTextView would follow on any click while editing.
    static let cxLink = NSAttributedString.Key("chopstix.link")
}

/// Shapes drawn in place of (or behind) markdown syntax.
enum MarkdownDecoration: Int {
    case bullet, nestedBullet, task, taskDone, quote, codeBlock, rule
}

/// Typography and colours for markdown in one setting: a sticky note, a page or a PDF.
struct MarkdownTheme: Equatable {
    var flavor: Flavor
    var baseSize: CGFloat
    /// Pages and PDFs set headings in the menu board's serif; sticky notes keep the rounded face.
    var serifHeadings: Bool

    static func sticky(_ flavor: Flavor) -> MarkdownTheme {
        MarkdownTheme(flavor: flavor, baseSize: NoteTextStyle.fontSize, serifHeadings: false)
    }

    static func page(_ flavor: Flavor) -> MarkdownTheme {
        MarkdownTheme(flavor: flavor, baseSize: 16, serifHeadings: true)
    }

    static func print(_ flavor: Flavor) -> MarkdownTheme {
        MarkdownTheme(flavor: flavor, baseSize: 11.5, serifHeadings: true)
    }

    // MARK: Colours

    var ink: NSColor { NoteTextStyle.ink }
    var softInk: NSColor { ink.withAlphaComponent(0.7) }
    var fadedInk: NSColor { NoteTextStyle.inkChecked }
    var syntaxColor: NSColor { ink.withAlphaComponent(0.3) }
    /// Bullets, numbers, checkboxes and quote bars: the flavour's lacquer, deepened to read on paper.
    var markerColor: NSColor { flavor.nsLacquer.blended(withFraction: 0.2, of: ink) ?? ink }
    var linkColor: NSColor { flavor.nsLacquer.blended(withFraction: 0.5, of: ink) ?? ink }
    var codeBackground: NSColor { ink.withAlphaComponent(0.055) }
    var highlightColor: NSColor { flavor.nsAccentSoft.withAlphaComponent(0.6) }
    var ruleColor: NSColor { ink.withAlphaComponent(0.18) }

    // MARK: Type

    var bodyFont: NSFont { Self.rounded(baseSize, .regular) }
    var monoFont: NSFont { .monospacedSystemFont(ofSize: (baseSize * 0.88).rounded(), weight: .regular) }

    func headingFont(_ level: Int) -> NSFont {
        let scale: CGFloat = switch level {
        case 1: 1.5
        case 2: 1.28
        case 3: 1.12
        default: 1
        }
        let size = (baseSize * scale).rounded()
        guard serifHeadings else { return Self.rounded(size, .semibold) }
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        return NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size) ?? base
    }

    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
    }

    /// Side of a drawn to-do checkbox for text in `font`.
    func checkboxSide(for font: NSFont) -> CGFloat {
        (font.capHeight + baseSize * 0.32).rounded()
    }

    var bodyParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = (baseSize * 0.18).rounded()
        p.paragraphSpacing = (baseSize * 0.3).rounded()
        return p
    }

    var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: ink, .paragraphStyle: bodyParagraph]
    }
}

/// Turns parsed markdown into text attributes.
enum MarkdownStyler {
    /// Styles `range` of `text`, using `tokens` parsed from all of it.
    static func style(_ text: NSMutableAttributedString, tokens: [MarkdownToken], in range: NSRange, theme: MarkdownTheme) {
        guard range.length > 0 else { return }
        let string = text.string as NSString
        text.setAttributes(theme.bodyAttributes, range: range)

        // Lines first, then inline styles within them, then markers and syntax on top.
        for token in tokens.sorted(by: { priority($0.kind) < priority($1.kind) }) {
            let r = NSIntersectionRange(token.range, range)
            guard r.length > 0 else { continue }
            switch token.kind {
            case .heading(let level):
                // The whole line, `#`s included, takes the heading's size.
                let line = NSIntersectionRange(string.paragraphRange(for: token.range), range)
                text.addAttributes([.font: theme.headingFont(level), .paragraphStyle: headingParagraph(level, theme)], range: line)
            case .listLine:
                break // after the syntax is known; see below
            case .quote:
                let line = NSIntersectionRange(string.paragraphRange(for: token.range), range)
                text.addAttributes([
                    .foregroundColor: theme.softInk,
                    .paragraphStyle: indented(theme.bodyParagraph, by: theme.baseSize * 0.95),
                    .cxDecoration: MarkdownDecoration.quote.rawValue,
                ], range: line)
            case .codeBlock:
                let p = indented(theme.bodyParagraph, by: theme.baseSize * 0.75, tail: true)
                p.paragraphSpacing = 0
                text.addAttributes([.font: theme.monoFont, .paragraphStyle: p, .cxDecoration: MarkdownDecoration.codeBlock.rawValue], range: r)
            case .rule:
                text.addAttribute(.cxDecoration, value: MarkdownDecoration.rule.rawValue, range: r)
            case .bold:
                transformFonts(in: r, of: text) { $0.adding(.bold) }
            case .italic:
                transformFonts(in: r, of: text) { $0.adding(.italic) }
                obliqueIfNeeded(r, in: text)
            case .strikethrough:
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            case .highlight:
                text.addAttribute(.backgroundColor, value: theme.highlightColor, range: r)
            case .code:
                text.addAttributes([.font: theme.monoFont, .backgroundColor: theme.codeBackground], range: r)
            case .link(let url):
                text.addAttributes([
                    .foregroundColor: theme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: theme.linkColor.withAlphaComponent(0.4),
                    .cxLink: url,
                ], range: r)
            case .done:
                text.addAttributes([.foregroundColor: theme.fadedInk, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: r)
            case .bullet:
                let nested = token.range.location > string.paragraphRange(for: token.range).location
                text.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .cxDecoration: (nested ? MarkdownDecoration.nestedBullet : .bullet).rawValue,
                ], range: r)
            case .number:
                text.addAttribute(.foregroundColor, value: theme.markerColor, range: r)
            case .task(let checked):
                text.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .cxDecoration: (checked ? MarkdownDecoration.taskDone : .task).rawValue,
                ], range: r)
                // `[ ]` and `[x]` differ in width; kern both to just fit the drawn box.
                if r == token.range, let font = text.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont {
                    let natural = NSAttributedString(string: string.substring(with: r), attributes: [.font: font]).size().width
                    let target = theme.checkboxSide(for: font) + (theme.baseSize * 0.15).rounded()
                    text.addAttribute(.kern, value: target - natural, range: NSRange(location: NSMaxRange(r) - 1, length: 1))
                }
            case .syntax:
                text.addAttributes([.foregroundColor: theme.syntaxColor, .cxHidden: true], range: r)
                text.removeAttribute(.backgroundColor, range: r)
                text.removeAttribute(.underlineStyle, range: r)
                text.removeAttribute(.strikethroughStyle, range: r)
            }
        }

        // Wrapped lines of a list item line up under its text, not its marker.
        for token in tokens {
            guard case .listLine(let prefix) = token.kind, NSIntersectionRange(token.range, range).length > 0 else { continue }
            let marker = NSRange(location: token.range.location, length: prefix)
            let visible = NSMutableString()
            text.enumerateAttributes(in: marker) { attrs, sub, _ in
                if attrs[.cxHidden] == nil { visible.append(string.substring(with: sub)) }
            }
            let width = NSAttributedString(string: visible as String, attributes: [.font: theme.bodyFont]).size().width
            let p = theme.bodyParagraph.mutableCopy() as! NSMutableParagraphStyle
            p.headIndent = width
            let line = NSIntersectionRange(string.paragraphRange(for: token.range), range)
            text.addAttribute(.paragraphStyle, value: p, range: line)
        }
    }

    private static func priority(_ kind: MarkdownToken.Kind) -> Int {
        switch kind {
        case .heading, .listLine, .quote, .codeBlock, .rule: 0
        case .code: 1
        case .bold, .italic, .strikethrough, .highlight, .link, .done: 2
        case .bullet, .number, .task: 3
        case .syntax: 4
        }
    }

    private static func headingParagraph(_ level: Int, _ theme: MarkdownTheme) -> NSParagraphStyle {
        let p = theme.bodyParagraph.mutableCopy() as! NSMutableParagraphStyle
        p.paragraphSpacingBefore = (theme.baseSize * (level == 1 ? 0.5 : 0.3)).rounded()
        p.paragraphSpacing = (theme.baseSize * 0.25).rounded()
        return p
    }

    private static func indented(_ style: NSParagraphStyle, by indent: CGFloat, tail: Bool = false) -> NSMutableParagraphStyle {
        let p = style.mutableCopy() as! NSMutableParagraphStyle
        p.firstLineHeadIndent = indent
        p.headIndent = indent
        if tail { p.tailIndent = -indent }
        return p
    }

    private static func transformFonts(in range: NSRange, of text: NSMutableAttributedString, _ transform: (NSFont) -> NSFont) {
        text.enumerateAttribute(.font, in: range) { value, sub, _ in
            guard let font = value as? NSFont else { return }
            text.addAttribute(.font, value: transform(font), range: sub)
        }
    }

    /// SF Rounded and SF Mono have no italic, so they lean instead.
    private static func obliqueIfNeeded(_ range: NSRange, in text: NSMutableAttributedString) {
        text.enumerateAttribute(.font, in: range) { value, sub, _ in
            guard let font = value as? NSFont, !font.fontDescriptor.symbolicTraits.contains(.italic) else { return }
            text.addAttribute(.obliqueness, value: NoteTextStyle.obliqueness, range: sub)
        }
    }
}

private extension NSFont {
    func adding(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(trait))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
