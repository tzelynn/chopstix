import Foundation

/// Markdown as plain text, for titles, board previews and word counts.
enum MarkdownPlainText {
    /// Only this much of a note is read for its title and preview, so long notes stay cheap.
    static let summaryLimit = 4000

    /// The start of `markdown` with its syntax removed. List items keep the sticky-note markers
    /// (`• `, `☐ `, `☑ `) so they read the same on the board as sticky notes do.
    static func summary(of markdown: String) -> String {
        var source = markdown as NSString
        if source.length > summaryLimit {
            source = source.substring(to: source.lineRange(for: NSRange(location: summaryLimit, length: 0)).location) as NSString
        }
        return render(source)
    }

    static func render(_ source: NSString) -> String {
        var replacements: [(range: NSRange, text: String)] = []
        for token in MarkdownParser.parse(source) {
            switch token.kind {
            case .syntax: replacements.append((token.range, ""))
            case .bullet: replacements.append((token.range, "•"))
            case .task(let checked): replacements.append((token.range, checked ? "☑" : "☐"))
            default: break
            }
        }
        replacements.sort { $0.range.location < $1.range.location }

        var result = ""
        var cursor = 0
        for (range, text) in replacements where range.location >= cursor {
            result += source.substring(with: NSRange(location: cursor, length: range.location - cursor)) + text
            cursor = NSMaxRange(range)
        }
        return result + source.substring(from: cursor)
    }

    static func wordCount(of markdown: String) -> Int {
        var count = 0
        markdown.enumerateSubstrings(in: markdown.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

/// Turns a sticky note's rich text into markdown.
enum MarkdownConversion {
    static func markdown(from runs: [TextRun]) -> String {
        // Split the runs into lines, keeping each piece's style.
        var lines: [[TextRun]] = [[]]
        for run in runs {
            let parts = run.text.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if index > 0 { lines.append([]) }
                if !part.isEmpty { lines[lines.count - 1].append(TextRun(text: part, style: run.style)) }
            }
        }
        return lines.map(line).joined(separator: "\n")
    }

    private static func line(_ runs: [TextRun]) -> String {
        var runs = runs
        let plain = runs.map(\.text).joined()
        var prefix = ""
        if let marker = ListMarker.allCases.first(where: { plain.hasPrefix($0.rawValue) }) {
            prefix = switch marker {
            case .bullet: "- "
            case .unchecked: "- [ ] "
            case .checked: "- [x] "
            }
            drop(marker.rawValue.count, from: &runs)
        }
        var body = runs.map(inline).joined()
        if prefix.isEmpty { body = escapeLineStart(body) }
        return prefix + body
    }

    /// Removes the first `count` characters, which may span runs.
    private static func drop(_ count: Int, from runs: inout [TextRun]) {
        var remaining = count
        while remaining > 0, !runs.isEmpty {
            let n = min(remaining, runs[0].text.count)
            runs[0].text.removeFirst(n)
            remaining -= n
            if runs[0].text.isEmpty { runs.removeFirst() }
        }
    }

    /// Markdown has no underline, so underlined text comes across plain.
    private static func inline(_ run: TextRun) -> String {
        let text = escape(run.text)
        let style = run.style
        let open = (style.strikethrough ? "~~" : "") + (style.bold ? "**" : "") + (style.italic ? "*" : "")
        guard !open.isEmpty else { return text }
        // Markers have to hug the text, so surrounding spaces stay outside them.
        let core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty, let range = text.range(of: core) else { return text }
        return String(text[..<range.lowerBound]) + open + core + String(open.reversed()) + String(text[range.upperBound...])
    }

    /// Backslash-escapes characters that would otherwise read as markdown.
    static func escape(_ text: String) -> String {
        var result = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            switch c {
            case "\\", "*", "`", "~", "[", "]":
                result += "\\\(c)"
            case "_":
                // Inside a word (snake_case) an underscore is literal anyway.
                let inWord = i > 0 && i + 1 < chars.count && chars[i - 1].isLetterOrDigit && chars[i + 1].isLetterOrDigit
                result += inWord ? "_" : "\\_"
            case "=" where i + 1 < chars.count && chars[i + 1] == "=":
                result += "\\="
            default:
                result.append(c)
            }
        }
        return result
    }

    /// Escapes a line that would otherwise start a heading, quote or list.
    private static func escapeLineStart(_ line: String) -> String {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        if line.hasPrefix("#") || line.hasPrefix(">") || line.hasPrefix("+ ") || line.hasPrefix("- ")
            || MarkdownParser.Pattern.rule.firstMatch(in: line, range: whole) != nil {
            return "\\" + line
        }
        if let m = MarkdownParser.Pattern.ordered.firstMatch(in: line, range: whole) {
            let number = m.range(at: 2)
            return ns.replacingCharacters(in: NSRange(location: NSMaxRange(number) - 1, length: 0), with: "\\")
        }
        return line
    }
}

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
