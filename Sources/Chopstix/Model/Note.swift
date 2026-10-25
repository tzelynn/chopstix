import Foundation

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Dish number shown on the board, e.g. "No. 07".
    var number: Int
    var flavor: Flavor
    var content: [TextRun] = []
    /// Stuck around the screen (true) or living only in the board (false).
    var isOnScreen: Bool
    var alwaysOnTop = false
    /// Last on-screen window frame, in screen coordinates.
    var frame: CGRect?
    var createdAt = Date()
    var updatedAt = Date()

    var plainText: String { content.map(\.text).joined() }

    /// No real text — only whitespace or bare list markers.
    var isEmpty: Bool { titleIndex == nil }

    private var lines: [String] { plainText.components(separatedBy: .newlines) }

    /// A line's text with any list marker and surrounding whitespace removed.
    private static func content(of line: String) -> String {
        var line = Substring(line)
        if let marker = ListMarker.allCases.first(where: { line.hasPrefix($0.rawValue) }) {
            line = line.dropFirst(marker.rawValue.count)
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    private var titleIndex: Int? { lines.firstIndex { !Note.content(of: $0).isEmpty } }

    /// First non-empty line, without any list marker.
    var title: String { titleIndex.map { Note.content(of: lines[$0]) } ?? "" }

    /// The non-empty lines after the title, as typed (markers kept so checklists read naturally).
    var preview: String {
        guard let titleIndex else { return "" }
        return lines[(titleIndex + 1)...]
            .filter { !Note.content(of: $0).isEmpty }
            .joined(separator: "\n")
    }
}
