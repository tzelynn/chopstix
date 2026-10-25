import AppKit

/// Paragraph prefixes that turn a line into a list item.
enum ListMarker: String, CaseIterable {
    case bullet = "• "
    case unchecked = "☐ "
    case checked = "☑ "

    /// Length in UTF-16 units (all markers are two BMP characters).
    static let length = 2

    var isChecklist: Bool { self != .bullet }

    static func at(_ location: Int, in string: NSString) -> ListMarker? {
        guard location + length <= string.length else { return nil }
        let prefix = string.substring(with: NSRange(location: location, length: length))
        return ListMarker(rawValue: prefix)
    }
}

/// A plain-text replacement. Lists of edits are ordered back-to-front so that applying
/// them in order never invalidates the ranges of the edits still to come.
struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String
}

/// List behaviour for note text: toggling bullets/checklists, continuing lists on
/// Return, ticking boxes, and styling ticked items.
enum ListEditing {
    enum Kind {
        case bullet, checklist

        var marker: ListMarker { self == .bullet ? .bullet : .unchecked }

        func matches(_ marker: ListMarker?) -> Bool {
            guard let marker else { return false }
            return self == .bullet ? marker == .bullet : marker.isChecklist
        }
    }

    /// Ranges of every paragraph touched by `selection` (including the empty last line).
    static func paragraphRanges(in string: NSString, for selection: NSRange) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = selection.location
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            ranges.append(paragraph)
            location = NSMaxRange(paragraph)
        } while location < NSMaxRange(selection) && location < string.length
        return ranges
    }

    /// Range of a paragraph's text after its marker, excluding the line terminator.
    static func contentRange(ofParagraphAt location: Int, in string: NSString) -> NSRange {
        var start = 0, contentsEnd = 0
        string.getParagraphStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        let markerLength = ListMarker.at(start, in: string) == nil ? 0 : ListMarker.length
        return NSRange(location: start + markerLength, length: max(0, contentsEnd - start - markerLength))
    }

    /// Turns the selected paragraphs into a list of `kind`, or removes the list if they all already are one.
    static func toggleEdits(_ kind: Kind, in string: NSString, selection: NSRange) -> [TextEdit] {
        let paragraphs = paragraphRanges(in: string, for: selection)
        let markers = paragraphs.map { ListMarker.at($0.location, in: string) }
        let removing = markers.allSatisfy(kind.matches)

        var edits: [TextEdit] = []
        for (paragraph, marker) in zip(paragraphs, markers) {
            let markerRange = NSRange(location: paragraph.location, length: marker == nil ? 0 : ListMarker.length)
            if removing {
                edits.append(TextEdit(range: markerRange, replacement: ""))
            } else if !kind.matches(marker) {
                edits.append(TextEdit(range: markerRange, replacement: kind.marker.rawValue))
            }
        }
        return edits.reversed()
    }

    /// Where `location` (in the original text) ends up once `edits` are applied.
    static func map(_ location: Int, through edits: [TextEdit]) -> Int {
        var result = location
        for edit in edits where edit.range.location <= location {
            let removedBefore = min(location, NSMaxRange(edit.range)) - edit.range.location
            result += (edit.replacement as NSString).length - removedBefore
        }
        return result
    }

    /// What Return should do at `location`. `nil` means "insert a plain newline".
    /// Inside a list it continues the list; on an empty item it ends the list instead.
    static func newlineEdits(in string: NSString, at location: Int) -> (edits: [TextEdit], cursor: Int)? {
        let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
        guard let marker = ListMarker.at(paragraph.location, in: string),
              location >= paragraph.location + ListMarker.length else { return nil }

        let content = string.substring(with: contentRange(ofParagraphAt: paragraph.location, in: string))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            let markerRange = NSRange(location: paragraph.location, length: ListMarker.length)
            return ([TextEdit(range: markerRange, replacement: "")], paragraph.location)
        }

        let next = marker == .bullet ? ListMarker.bullet : .unchecked
        let insertion = "\n" + next.rawValue
        return ([TextEdit(range: NSRange(location: location, length: 0), replacement: insertion)],
                location + (insertion as NSString).length)
    }

    /// Ticks or unticks the checkbox at `index`, if there is one there.
    static func checkboxToggleEdit(in string: NSString, at index: Int) -> TextEdit? {
        guard index < string.length else { return nil }
        let start = string.paragraphRange(for: NSRange(location: index, length: 0)).location
        guard index == start, let marker = ListMarker.at(start, in: string), marker.isChecklist else { return nil }
        let flipped = marker == .checked ? ListMarker.unchecked : .checked
        return TextEdit(range: NSRange(location: start, length: 1), replacement: String(flipped.rawValue.first!))
    }

    /// Ticked items are struck through and faded; unticked items are restored.
    static func restyleChecklist(in text: NSMutableAttributedString) {
        let string = text.string as NSString
        guard string.length > 0 else { return }
        text.beginEditing()
        // All note text is ink; only ticked items are faded.
        text.addAttribute(.foregroundColor, value: NoteTextStyle.ink, range: NSRange(location: 0, length: string.length))
        for paragraph in paragraphRanges(in: string, for: NSRange(location: 0, length: string.length)) {
            guard let marker = ListMarker.at(paragraph.location, in: string), marker.isChecklist else { continue }
            let content = contentRange(ofParagraphAt: paragraph.location, in: string)
            let markerRange = NSRange(location: paragraph.location, length: ListMarker.length)
            text.removeAttribute(.strikethroughStyle, range: markerRange)
            guard content.length > 0 else { continue }
            if marker == .checked {
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
                text.addAttribute(.foregroundColor, value: NoteTextStyle.inkChecked, range: content)
            } else {
                text.removeAttribute(.strikethroughStyle, range: content)
            }
        }
        text.endEditing()
    }
}
