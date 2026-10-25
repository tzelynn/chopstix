import AppKit

/// Inline styling that a note can carry. Fonts and colours are not stored — they are
/// rebuilt from `NoteTextStyle` so the house typography can change without migrations.
struct RunStyle: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
}

/// A span of note text sharing one `RunStyle`.
struct TextRun: Equatable {
    var text: String
    var style = RunStyle()
}

extension TextRun: Codable {
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

    /// Only `true` flags are written, keeping the JSON small and readable.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        if style.bold { try c.encode(true, forKey: .bold) }
        if style.italic { try c.encode(true, forKey: .italic) }
        if style.underline { try c.encode(true, forKey: .underline) }
        if style.strikethrough { try c.encode(true, forKey: .strikethrough) }
    }
}

/// The house typography for note text.
enum NoteTextStyle {
    static let fontSize: CGFloat = 14
    static let ink = NSColor(hex: 0x4B3A33)
    static let inkChecked = NSColor(hex: 0x4B3A33, alpha: 0.42)

    static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        p.paragraphSpacing = 3
        return p
    }()

    static func font(bold: Bool = false, italic: Bool = false) -> NSFont {
        let base = NSFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular)
        var descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        if italic {
            descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic))
        }
        return NSFont(descriptor: descriptor, size: fontSize) ?? base
    }

    /// SF Rounded has no true italic, so italics fall back to a synthetic slant.
    static let italicNeedsObliqueness: Bool = !font(italic: true).fontDescriptor.symbolicTraits.contains(.italic)

    static let obliqueness: CGFloat = 0.16

    static func attributes(for style: RunStyle) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(bold: style.bold, italic: style.italic),
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
        ]
        if style.italic && italicNeedsObliqueness { attrs[.obliqueness] = obliqueness }
        if style.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.strikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }

    static var baseAttributes: [NSAttributedString.Key: Any] { attributes(for: RunStyle()) }

    static func style(of attrs: [NSAttributedString.Key: Any]) -> RunStyle {
        let descriptor = (attrs[.font] as? NSFont)?.fontDescriptor
        let traits = descriptor?.symbolicTraits ?? []
        // Bold is drawn as semibold, which doesn't always set the `.bold` symbolic trait.
        let weight = ((descriptor?.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? NSNumber)?.doubleValue ?? 0
        let oblique = ((attrs[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0
        return RunStyle(
            bold: traits.contains(.bold) || weight >= NSFont.Weight.semibold.rawValue - 0.01,
            italic: traits.contains(.italic) || oblique,
            underline: ((attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0,
            strikethrough: ((attrs[.strikethroughStyle] as? NSNumber)?.intValue ?? 0) != 0
        )
    }
}

enum RichTextCodec {
    static func attributedString(from runs: [TextRun]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs {
            result.append(NSAttributedString(string: run.text, attributes: NoteTextStyle.attributes(for: run.style)))
        }
        ListEditing.restyleChecklist(in: result)
        return result
    }

    static func runs(from text: NSAttributedString) -> [TextRun] {
        var runs: [TextRun] = []
        let string = text.string as NSString
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            let run = TextRun(text: string.substring(with: range), style: NoteTextStyle.style(of: attrs))
            if let last = runs.last, last.style == run.style {
                runs[runs.count - 1].text += run.text
            } else {
                runs.append(run)
            }
        }
        return runs
    }
}
