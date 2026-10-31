import Foundation

/// The result of a markdown editing command: edits (back-to-front, see `TextEdit`) and where
/// the selection should end up afterwards.
struct MarkdownChange: Equatable {
    var edits: [TextEdit]
    var selection: NSRange
}

/// Editing behaviour for markdown notes. Pure functions over the source text, so they're easy
/// to test; `MarkdownTextView` applies the results.
enum MarkdownEditing {
    /// Spaces added per nesting level. Four works under both `- ` and `1. ` items in CommonMark.
    static let indentUnit = "    "

    /// What starts a line.
    enum Marker: Equatable {
        case none
        case heading(Int)
        case quote
        case bullet(Character)
        case task(bullet: Character, checked: Bool)
        case number(Int, delimiter: Character)

        var isList: Bool {
            switch self {
            case .bullet, .task, .number: true
            default: false
            }
        }

        /// The marker the next line gets when Return continues this one.
        var continued: String? {
            switch self {
            case .bullet(let c): "\(c) "
            case .task(let c, _): "\(c) [ ] "
            case .number(let n, let d): "\(n + 1)\(d) "
            case .quote: "> "
            case .none, .heading: nil
            }
        }
    }

    /// The parts of one line: `indent` + marker, then the content from `contentStart`.
    struct Line {
        var range: NSRange
        var indent: NSRange
        var marker: Marker
        var contentStart: Int

        var markerRange: NSRange { NSRange(location: NSMaxRange(indent), length: contentStart - NSMaxRange(indent)) }
        var contentRange: NSRange { NSRange(location: contentStart, length: NSMaxRange(range) - contentStart) }
    }

    /// Kinds of line a command can turn the selected lines into.
    enum LineKind: Equatable {
        case body, heading(Int), bullet, task, number, quote

        func matches(_ marker: Marker) -> Bool {
            switch (self, marker) {
            case (.body, .none), (.bullet, .bullet), (.task, .task), (.number, .number), (.quote, .quote): true
            case (.heading(let a), .heading(let b)): a == b
            default: false
            }
        }
    }

    // MARK: Reading lines

    static func line(at location: Int, in string: NSString) -> Line {
        var start = 0, contentsEnd = 0
        string.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: min(location, string.length), length: 0))
        let range = NSRange(location: start, length: contentsEnd - start)
        let text = string.substring(with: range)
        let whole = NSRange(location: 0, length: (text as NSString).length)
        typealias P = MarkdownParser.Pattern
        func at(_ r: NSRange) -> NSRange { NSRange(location: start + r.location, length: r.length) }
        func char(_ r: NSRange) -> Character { Character((text as NSString).substring(with: NSRange(location: r.location, length: 1))) }

        if let m = P.heading.firstMatch(in: text, range: whole) {
            return Line(range: range, indent: NSRange(location: start, length: 0), marker: .heading(m.range(at: 1).length), contentStart: start + NSMaxRange(m.range))
        }
        if let m = P.quote.firstMatch(in: text, range: whole) {
            return Line(range: range, indent: NSRange(location: start, length: 0), marker: .quote, contentStart: start + NSMaxRange(m.range))
        }
        if let m = P.task.firstMatch(in: text, range: whole) {
            let box = m.range(at: 3)
            let checked = (text as NSString).substring(with: NSRange(location: box.location + 1, length: 1)) != " "
            return Line(range: range, indent: at(m.range(at: 1)), marker: .task(bullet: char(m.range(at: 2)), checked: checked), contentStart: start + NSMaxRange(m.range))
        }
        if P.rule.firstMatch(in: text, range: whole) == nil, let m = P.bullet.firstMatch(in: text, range: whole) {
            return Line(range: range, indent: at(m.range(at: 1)), marker: .bullet(char(m.range(at: 2))), contentStart: start + NSMaxRange(m.range))
        }
        if let m = P.ordered.firstMatch(in: text, range: whole) {
            let token = (text as NSString).substring(with: m.range(at: 2))
            let number = Int(token.dropLast()) ?? 1
            return Line(range: range, indent: at(m.range(at: 1)), marker: .number(number, delimiter: token.last!), contentStart: start + NSMaxRange(m.range))
        }
        let indent = (text as NSString).range(of: "^[ \t]*", options: .regularExpression)
        return Line(range: range, indent: at(indent), marker: .none, contentStart: start + NSMaxRange(indent))
    }

    /// Every line touched by `selection`.
    static func lines(in string: NSString, for selection: NSRange) -> [Line] {
        ListEditing.paragraphRanges(in: string, for: selection).map { line(at: $0.location, in: string) }
    }

    // MARK: Return, Tab, Backspace

    /// What Return should do at `location`. `nil` means "insert a plain newline".
    /// Lists and quotes continue; Return on an empty item un-nests it, then ends the list.
    static func newline(in string: NSString, at location: Int, inCodeBlock: Bool = false) -> MarkdownChange? {
        let line = line(at: location, in: string)
        if inCodeBlock {
            // Keep the indentation of code going.
            let indent = (string.substring(with: line.range) as NSString).range(of: "^[ \t]*", options: .regularExpression)
            guard indent.length > 0, location >= line.range.location + indent.length else { return nil }
            return insert("\n" + (string.substring(with: line.range) as NSString).substring(with: indent), at: location)
        }
        guard let next = line.marker.continued, location >= line.contentStart else { return nil }

        if string.substring(with: line.contentRange).trimmingCharacters(in: .whitespaces).isEmpty {
            if line.marker.isList, line.indent.length > 0, let outdent = outdent(line, in: string) {
                return MarkdownChange(edits: [outdent], selection: NSRange(location: ListEditing.map(location, through: [outdent]), length: 0))
            }
            // The line is only its marker: clear it, ending the list.
            return MarkdownChange(edits: [TextEdit(range: line.range, replacement: "")], selection: NSRange(location: line.range.location, length: 0))
        }
        return insert("\n" + string.substring(with: line.indent) + next, at: location)
    }

    /// Tab / ⇧Tab on list items nests or un-nests them. `nil` if no list item is selected.
    static func indent(in string: NSString, selection: NSRange, outdent outward: Bool) -> MarkdownChange? {
        let items = lines(in: string, for: selection).filter { $0.marker.isList }
        guard !items.isEmpty else { return nil }
        let edits: [TextEdit] = items.reversed().compactMap { line in
            outward ? outdent(line, in: string) : TextEdit(range: NSRange(location: line.range.location, length: 0), replacement: indentUnit)
        }
        guard !edits.isEmpty else { return MarkdownChange(edits: [], selection: selection) }
        return MarkdownChange(edits: edits, selection: map(selection, through: edits))
    }

    /// Backspace right after a marker removes the marker (un-nesting list items first),
    /// turning the line back into body text. `nil` means "delete normally".
    static func backspace(in string: NSString, at location: Int) -> MarkdownChange? {
        let line = line(at: location, in: string)
        guard line.marker != .none, location == line.contentStart else { return nil }
        if line.marker.isList, line.indent.length > 0, let outdent = outdent(line, in: string) {
            return MarkdownChange(edits: [outdent], selection: NSRange(location: ListEditing.map(location, through: [outdent]), length: 0))
        }
        let edit = TextEdit(range: line.markerRange, replacement: "")
        return MarkdownChange(edits: [edit], selection: NSRange(location: line.markerRange.location, length: 0))
    }

    /// Removes one level of indent: a leading tab, or up to one indent unit of spaces.
    private static func outdent(_ line: Line, in string: NSString) -> TextEdit? {
        guard line.indent.length > 0 else { return nil }
        var length = 0
        if string.character(at: line.indent.location) == 0x09 {
            length = 1
        } else {
            while length < min(line.indent.length, indentUnit.count), string.character(at: line.indent.location + length) == 0x20 { length += 1 }
        }
        return TextEdit(range: NSRange(location: line.indent.location, length: length), replacement: "")
    }

    // MARK: Inline markers

    /// Wraps the selection in `marker` (e.g. `**`), or unwraps it if it already is.
    /// With no selection it inserts a pair of markers and puts the caret between them.
    static func toggleWrap(_ marker: String, in string: NSString, selection: NSRange) -> MarkdownChange? {
        let length = (marker as NSString).length
        if selection.length == 0 {
            // Caret between an empty pair → take the pair away again.
            let around = NSRange(location: selection.location - length, length: 2 * length)
            if around.location >= 0, NSMaxRange(around) <= string.length, string.substring(with: around) == marker + marker {
                return MarkdownChange(edits: [TextEdit(range: around, replacement: "")], selection: NSRange(location: around.location, length: 0))
            }
            return insert(marker + marker, at: selection.location, caretOffset: length)
        }

        // Act on each line's part of the selection, without its surrounding whitespace.
        var segments: [NSRange] = []
        for paragraph in ListEditing.paragraphRanges(in: string, for: selection) {
            let content = line(at: paragraph.location, in: string).contentRange
            var part = NSIntersectionRange(selection, content)
            while part.length > 0, isSpace(string.character(at: part.location)) { part.location += 1; part.length -= 1 }
            while part.length > 0, isSpace(string.character(at: NSMaxRange(part) - 1)) { part.length -= 1 }
            if part.length > 0 { segments.append(part) }
        }
        guard !segments.isEmpty else { return nil }

        let wrapped = segments.allSatisfy { isWrapped($0, in: marker, string: string) }
        var edits: [TextEdit] = []
        for part in segments.reversed() {
            if wrapped {
                edits.append(TextEdit(range: NSRange(location: NSMaxRange(part), length: length), replacement: ""))
                edits.append(TextEdit(range: NSRange(location: part.location - length, length: length), replacement: ""))
            } else {
                edits.append(TextEdit(range: NSRange(location: NSMaxRange(part), length: 0), replacement: marker))
                edits.append(TextEdit(range: NSRange(location: part.location, length: 0), replacement: marker))
            }
        }
        // Keep the same words selected (inside the markers). An opening marker inserted at the
        // start already pushes it along, so only the end needs pulling back inside its marker.
        let first = segments[0], last = segments[segments.count - 1]
        let start = ListEditing.map(first.location, through: edits)
        let end = ListEditing.map(NSMaxRange(last), through: edits) - (wrapped ? 0 : length)
        return MarkdownChange(edits: edits, selection: NSRange(location: start, length: max(0, end - start)))
    }

    /// Whether `part` sits directly inside `marker`s. `*` and `**` share a character, so they
    /// are told apart by how many of it there are (`***x***` is both bold and italic).
    private static func isWrapped(_ part: NSRange, in marker: String, string: NSString) -> Bool {
        let unit = (marker as NSString).character(at: 0)
        let length = (marker as NSString).length
        var before = 0, after = 0
        while part.location - before - 1 >= 0, string.character(at: part.location - before - 1) == unit { before += 1 }
        while NSMaxRange(part) + after < string.length, string.character(at: NSMaxRange(part) + after) == unit { after += 1 }
        if unit == 0x2A /* * */ && length == 1 { return before % 2 == 1 && after % 2 == 1 }
        if unit == 0x2A { return before >= 2 && after >= 2 }
        return before >= length && after >= length
    }

    /// Wraps the selection in a link, selecting the URL so it can be typed over. Uses `url` (e.g.
    /// one on the clipboard) if given.
    static func link(in string: NSString, selection: NSRange, url: String? = nil) -> MarkdownChange {
        let text = string.substring(with: selection)
        let target = url ?? "url"
        let replacement = "[\(text)](\(target))"
        let edit = TextEdit(range: selection, replacement: replacement)
        if text.isEmpty {
            return MarkdownChange(edits: [edit], selection: NSRange(location: selection.location + 1, length: 0))
        }
        let urlStart = selection.location + (text as NSString).length + 3
        return MarkdownChange(edits: [edit], selection: url == nil
            ? NSRange(location: urlStart, length: (target as NSString).length)
            : NSRange(location: selection.location + (replacement as NSString).length, length: 0))
    }

    // MARK: Line kinds

    /// Turns the selected lines into `kind`, or back into body text if they all already are.
    static func setLineKind(_ kind: LineKind, in string: NSString, selection: NSRange) -> MarkdownChange {
        let lines = lines(in: string, for: selection)
        let removing = kind != .body && lines.allSatisfy { kind.matches($0.marker) }
        var edits: [TextEdit] = []
        for (number, line) in lines.enumerated().reversed() {
            let target = removing ? .body : kind
            let prefix: String = switch target {
            case .body: ""
            case .heading(let level): String(repeating: "#", count: level) + " "
            case .bullet: if case .bullet(let c) = line.marker { "\(c) " } else { "- " }
            case .task: if case .task(let c, let checked) = line.marker { "\(c) [\(checked ? "x" : " ")] " } else { "- [ ] " }
            case .number: "\(number + 1). "
            case .quote: "> "
            }
            // Headings and quotes don't nest, so they take the line's indent away too.
            let keepsIndent = [.body, .bullet, .task, .number].contains(target)
            let range = keepsIndent ? line.markerRange : NSRange(location: line.range.location, length: line.contentStart - line.range.location)
            if string.substring(with: range) != prefix {
                edits.append(TextEdit(range: range, replacement: prefix))
            }
        }
        return MarkdownChange(edits: edits, selection: map(selection, through: edits))
    }

    /// Body → H1 → H2 → H3 → body, following the line the selection starts on.
    static func cycleHeading(in string: NSString, selection: NSRange) -> MarkdownChange {
        let level: Int = if case .heading(let n) = line(at: selection.location, in: string).marker { n } else { 0 }
        return setLineKind(level >= 3 ? .body : .heading(level + 1), in: string, selection: selection)
    }

    /// Ticks or unticks the to-do whose `[ ]` box starts at `boxLocation`.
    static func toggleTask(in string: NSString, boxLocation: Int) -> TextEdit? {
        guard boxLocation + 3 <= string.length, string.character(at: boxLocation) == 0x5B /* [ */ else { return nil }
        let mark = NSRange(location: boxLocation + 1, length: 1)
        return TextEdit(range: mark, replacement: string.substring(with: mark) == " " ? "x" : " ")
    }

    // MARK: Helpers

    private static func insert(_ text: String, at location: Int, caretOffset: Int? = nil) -> MarkdownChange {
        let length = (text as NSString).length
        return MarkdownChange(edits: [TextEdit(range: NSRange(location: location, length: 0), replacement: text)],
                              selection: NSRange(location: location + (caretOffset ?? length), length: 0))
    }

    private static func map(_ selection: NSRange, through edits: [TextEdit]) -> NSRange {
        let start = ListEditing.map(selection.location, through: edits)
        let end = ListEditing.map(NSMaxRange(selection), through: edits)
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }
}
