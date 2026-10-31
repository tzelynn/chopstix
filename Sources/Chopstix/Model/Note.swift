import Foundation

/// What a note is written in.
enum NoteKind: String, Codable {
    /// Rich text with bold/italic/lists — the original sticky note.
    case sticky
    /// Plain markdown, rendered as it's typed. Its body lives in its own `.md` file.
    case markdown
}

struct Note: Identifiable, Equatable {
    var id = UUID()
    /// Dish number shown on the board, e.g. "No. 07".
    var number: Int
    var flavor: Flavor
    var kind = NoteKind.sticky
    /// Body of a sticky note.
    var content: [TextRun] = []
    /// Body of a markdown note. Not stored in the index — `NoteStore` keeps it in its own file.
    var markdown = ""
    /// Stuck around the screen (true) or living only in the board (false).
    var isOnScreen: Bool
    var alwaysOnTop = false
    /// Last on-screen window frame, in screen coordinates.
    var frame: CGRect?
    var createdAt = Date()
    var updatedAt = Date()
    /// Where a markdown note was last saved as a `.md` file, so ⌘S can save there again.
    var exportPath: String?
    var exportedAt: Date?

    init(id: UUID = UUID(), number: Int, flavor: Flavor, kind: NoteKind = .sticky, content: [TextRun] = [],
         markdown: String = "", isOnScreen: Bool, frame: CGRect? = nil) {
        self.id = id
        self.number = number
        self.flavor = flavor
        self.kind = kind
        self.content = content
        self.markdown = markdown
        self.isOnScreen = isOnScreen
        self.frame = frame
    }

    /// The note's text with formatting removed (markdown lists become `•`/`☐`/`☑` lines).
    var plainText: String {
        switch kind {
        case .sticky: content.map(\.text).joined()
        case .markdown: MarkdownPlainText.summary(of: markdown)
        }
    }

    /// No real text — only whitespace or bare list markers.
    var isEmpty: Bool { titleIndex == nil }

    private var lines: [String] { plainText.components(separatedBy: .newlines) }

    /// A line's text with any list marker and surrounding whitespace removed.
    private static func content(of line: String) -> String {
        // Leading indent only: markers include their trailing space.
        var line = Substring(line).drop { $0 == " " || $0 == "\t" }
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

extension Note: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, number, flavor, kind, content, isOnScreen, alwaysOnTop, frame, createdAt, updatedAt, exportPath, exportedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        flavor = try c.decode(Flavor.self, forKey: .flavor)
        // Files from before markdown notes have no kind: they're all sticky notes.
        kind = try c.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .sticky
        content = try c.decodeIfPresent([TextRun].self, forKey: .content) ?? []
        isOnScreen = try c.decode(Bool.self, forKey: .isOnScreen)
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        exportPath = try c.decodeIfPresent(String.self, forKey: .exportPath)
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt)
    }

    /// The markdown body is deliberately left out; `kind` is only written for markdown notes.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(number, forKey: .number)
        try c.encode(flavor, forKey: .flavor)
        if kind != .sticky { try c.encode(kind, forKey: .kind) }
        if kind == .sticky { try c.encode(content, forKey: .content) }
        try c.encode(isOnScreen, forKey: .isOnScreen)
        try c.encode(alwaysOnTop, forKey: .alwaysOnTop)
        try c.encodeIfPresent(frame, forKey: .frame)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(exportPath, forKey: .exportPath)
        try c.encodeIfPresent(exportedAt, forKey: .exportedAt)
    }
}
