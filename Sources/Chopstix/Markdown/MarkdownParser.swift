import Foundation

/// A piece of markdown that the editor styles. Ranges are UTF-16 (`NSString`) ranges in the source.
struct MarkdownToken: Equatable {
    enum Kind: Equatable {
        // Lines
        /// A heading's text (its `#` marker is `syntax`).
        case heading(Int)
        /// A whole list line; `prefix` is the length of its indent + marker, for the hanging indent.
        case listLine(prefix: Int)
        /// The `-`, `*` or `+` of a bulleted item, drawn as a dot.
        case bullet
        /// The `1.` of a numbered item.
        case number
        /// The `[ ]` / `[x]` of a to-do, drawn as a checkbox.
        case task(checked: Bool)
        /// The text of a ticked to-do.
        case done
        /// A `>` quote line.
        case quote
        /// A fenced code block, fences included.
        case codeBlock
        /// A `---` divider line.
        case rule
        // Inline
        case bold, italic, strikethrough, highlight, code
        /// A link's visible text, with its URL.
        case link(String)
        /// Markup characters, hidden away from the line being edited.
        case syntax
    }

    var kind: Kind
    var range: NSRange

    init(_ kind: Kind, _ range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// A small, line-based markdown parser covering what notes need (CommonMark-ish, no tables or HTML).
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownToken] { parse(text as NSString) }

    static func parse(_ string: NSString) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []
        var openFence: Int?
        var location = 0
        while location < string.length {
            var start = 0, end = 0, contentsEnd = 0
            string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = NSRange(location: start, length: contentsEnd - start)
            let text = string.substring(with: line) as NSString

            if Pattern.fence.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) != nil {
                tokens.append(MarkdownToken(.syntax, line))
                if let open = openFence {
                    tokens.append(MarkdownToken(.codeBlock, NSRange(location: open, length: contentsEnd - open)))
                    openFence = nil
                } else {
                    openFence = start
                }
            } else if openFence == nil {
                parseLine(text, at: start, into: &tokens)
            }
            location = end
        }
        // An unclosed fence runs to the end, as in CommonMark.
        if let open = openFence {
            tokens.append(MarkdownToken(.codeBlock, NSRange(location: open, length: string.length - open)))
        }
        return tokens
    }

    // MARK: Lines

    private static func parseLine(_ line: NSString, at base: Int, into tokens: inout [MarkdownToken]) {
        let whole = NSRange(location: 0, length: line.length)
        func absolute(_ r: NSRange) -> NSRange { NSRange(location: base + r.location, length: r.length) }
        var contentStart = 0

        if let m = Pattern.heading.firstMatch(in: line as String, range: whole) {
            let level = m.range(at: 1).length
            tokens.append(MarkdownToken(.syntax, absolute(m.range)))
            contentStart = NSMaxRange(m.range)
            tokens.append(MarkdownToken(.heading(level), absolute(NSRange(location: contentStart, length: line.length - contentStart))))
        } else if Pattern.rule.firstMatch(in: line as String, range: whole) != nil {
            tokens.append(MarkdownToken(.rule, absolute(whole)))
            tokens.append(MarkdownToken(.syntax, absolute(whole)))
            return
        } else if let m = Pattern.quote.firstMatch(in: line as String, range: whole) {
            tokens.append(MarkdownToken(.quote, absolute(whole)))
            tokens.append(MarkdownToken(.syntax, absolute(m.range)))
            contentStart = NSMaxRange(m.range)
        } else if let m = Pattern.task.firstMatch(in: line as String, range: whole) {
            let box = m.range(at: 3)
            let checked = line.substring(with: NSRange(location: box.location + 1, length: 1)) != " "
            contentStart = NSMaxRange(m.range)
            tokens.append(MarkdownToken(.listLine(prefix: contentStart), absolute(whole)))
            tokens.append(MarkdownToken(.syntax, absolute(m.range(at: 2))))
            tokens.append(MarkdownToken(.task(checked: checked), absolute(box)))
            if checked && contentStart < line.length {
                tokens.append(MarkdownToken(.done, absolute(NSRange(location: contentStart, length: line.length - contentStart))))
            }
        } else if let m = Pattern.bullet.firstMatch(in: line as String, range: whole) {
            contentStart = NSMaxRange(m.range)
            tokens.append(MarkdownToken(.listLine(prefix: contentStart), absolute(whole)))
            tokens.append(MarkdownToken(.bullet, absolute(m.range(at: 2))))
        } else if let m = Pattern.ordered.firstMatch(in: line as String, range: whole) {
            contentStart = NSMaxRange(m.range)
            tokens.append(MarkdownToken(.listLine(prefix: contentStart), absolute(whole)))
            tokens.append(MarkdownToken(.number, absolute(m.range(at: 2))))
        }

        parseInline(line, from: contentStart, at: base, into: &tokens)
    }

    // MARK: Inline

    /// Emphasis-like spans: opening/closing marker length, and the token for the text between.
    private static let spans: [(NSRegularExpression, Int, MarkdownToken.Kind)] = [
        (Pattern.boldStars, 2, .bold),
        (Pattern.boldUnderscores, 2, .bold),
        (Pattern.strikethrough, 2, .strikethrough),
        (Pattern.highlight, 2, .highlight),
        (Pattern.italicStar, 1, .italic),
        (Pattern.italicUnderscore, 1, .italic),
    ]

    private static func parseInline(_ line: NSString, from start: Int, at base: Int, into tokens: inout [MarkdownToken]) {
        guard start < line.length else { return }
        // Markers already used up are blanked out so later patterns can't reuse them, and code
        // spans and URLs are blanked whole so nothing inside them is read as emphasis.
        let masked = NSMutableString(string: line)
        if start > 0 { mask(NSRange(location: 0, length: start), in: masked) }
        let range = NSRange(location: start, length: line.length - start)
        func absolute(_ r: NSRange) -> NSRange { NSRange(location: base + r.location, length: r.length) }
        func matches(_ pattern: NSRegularExpression) -> [NSTextCheckingResult] {
            pattern.matches(in: masked as String, range: range)
        }

        for m in matches(Pattern.escape) {
            tokens.append(MarkdownToken(.syntax, absolute(NSRange(location: m.range.location, length: 1))))
            mask(m.range, in: masked)
        }
        for m in matches(Pattern.code) {
            let fence = m.range(at: 1).length
            tokens.append(MarkdownToken(.syntax, absolute(NSRange(location: m.range.location, length: fence))))
            tokens.append(MarkdownToken(.code, absolute(m.range(at: 2))))
            tokens.append(MarkdownToken(.syntax, absolute(NSRange(location: NSMaxRange(m.range) - fence, length: fence))))
            mask(m.range, in: masked)
        }
        for m in matches(Pattern.link) {
            let text = m.range(at: 1)
            let tail = NSRange(location: NSMaxRange(text), length: NSMaxRange(m.range) - NSMaxRange(text))
            let url = line.substring(with: m.range(at: 2))
            tokens.append(MarkdownToken(.syntax, absolute(NSRange(location: m.range.location, length: 1))))
            tokens.append(MarkdownToken(.link(url), absolute(text)))
            tokens.append(MarkdownToken(.syntax, absolute(tail)))
            mask(NSRange(location: m.range.location, length: 1), in: masked)
            mask(tail, in: masked)
        }
        for m in matches(Pattern.autolink) {
            tokens.append(MarkdownToken(.link(line.substring(with: m.range)), absolute(m.range)))
            mask(m.range, in: masked)
        }
        for (pattern, marker, kind) in spans {
            for m in matches(pattern) {
                let open = NSRange(location: m.range.location, length: marker)
                let close = NSRange(location: NSMaxRange(m.range) - marker, length: marker)
                tokens.append(MarkdownToken(.syntax, absolute(open)))
                tokens.append(MarkdownToken(kind, absolute(NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open)))))
                tokens.append(MarkdownToken(.syntax, absolute(close)))
                mask(open, in: masked)
                mask(close, in: masked)
            }
        }
    }

    /// Replaces characters with a placeholder of the same UTF-16 length that no pattern matches.
    private static func mask(_ range: NSRange, in string: NSMutableString) {
        string.replaceCharacters(in: range, with: String(repeating: "\u{1}", count: range.length))
    }

    // MARK: Patterns

    enum Pattern {
        static let fence = regex(#"^ {0,3}```"#)
        static let heading = regex(#"^(#{1,6})(?:[ \t]+|$)"#)
        static let rule = regex(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
        static let quote = regex(#"^ {0,3}> ?"#)
        /// indent, `- ` marker, `[ ]` box, then a space (or the end of the line).
        static let task = regex(#"^([ \t]*)([-*+][ \t]+)(\[[ xX]\])(?:[ \t]+|$)"#)
        static let bullet = regex(#"^([ \t]*)([-*+])[ \t]+"#)
        static let ordered = regex(#"^([ \t]*)(\d{1,9}[.)])[ \t]+"#)

        static let escape = regex(#"\\[\\`*_{}\[\]()#+\-.!~=|>]"#)
        static let code = regex(#"(`+)([^`]|[^`].*?[^`])\1(?!`)"#)
        static let link = regex(#"\[([^\]\u0001]+)\]\(([^)\s\u0001]+)\)"#)
        static let autolink = regex(#"\bhttps?://[^\s\u0001<>]+[^\s\u0001<>.,;:!?'")\]]"#)
        static let boldStars = regex(#"\*\*(?=[^\s*])(.+?)(?<=[^\s*])\*\*"#)
        static let boldUnderscores = regex(#"(?<![\w_])__(?=\S)(.+?)(?<=\S)__(?![\w_])"#)
        static let strikethrough = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
        static let highlight = regex(#"==(?=\S)(.+?)(?<=\S)=="#)
        static let italicStar = regex(#"(?<!\*)\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)"#)
        static let italicUnderscore = regex(#"(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])"#)

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // The patterns are constants (and covered by tests), so this can't fail at runtime.
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }
}
