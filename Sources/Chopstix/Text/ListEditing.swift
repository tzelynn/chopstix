import AppKit

/// Plain-text list prefixes: how a note's lists read in summaries and board previews,
/// and how old rich-text sticky notes marked their lists.
enum ListMarker: String, CaseIterable {
    case bullet = "• "
    case unchecked = "☐ "
    case checked = "☑ "
}

/// A plain-text replacement. Lists of edits are ordered back-to-front so that applying
/// them in order never invalidates the ranges of the edits still to come.
struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String
}

/// Line and edit helpers shared by the markdown editing commands.
enum ListEditing {
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

    /// Where `location` (in the original text) ends up once `edits` are applied.
    static func map(_ location: Int, through edits: [TextEdit]) -> Int {
        var result = location
        for edit in edits where edit.range.location <= location {
            let removedBefore = min(location, NSMaxRange(edit.range)) - edit.range.location
            result += (edit.replacement as NSString).length - removedBefore
        }
        return result
    }
}
