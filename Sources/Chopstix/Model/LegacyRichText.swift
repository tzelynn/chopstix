import Foundation

/// Inline styling from the old rich-text sticky notes. Only read, to convert those notes
/// to markdown (see `Note.init(from:)` and `MarkdownConversion`).
struct RunStyle: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
}

/// A span of old sticky-note text sharing one `RunStyle`.
struct TextRun: Equatable {
    var text: String
    var style = RunStyle()
}

extension TextRun: Decodable {
    private enum CodingKeys: String, CodingKey { case text, bold, italic, underline, strikethrough }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        style = RunStyle(
            bold: try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false,
            italic: try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false,
            underline: try c.decodeIfPresent(Bool.self, forKey: .underline) ?? false,
            strikethrough: try c.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
        )
    }
}
