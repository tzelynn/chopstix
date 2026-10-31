import AppKit

/// Formatting commands available from the Format menu and the note toolbar.
enum FormatAction: CaseIterable, Identifiable {
    case bold, italic, underline, strikethrough, bulletList, checklist

    var id: Self { self }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .bulletList: "Bulleted List"
        case .checklist: "Checklist"
        }
    }

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .bulletList: "list.bullet"
        case .checklist: "checklist"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .underline: "u"
        case .strikethrough: "x"
        case .bulletList: "7"
        case .checklist: "l"
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .bold, .italic, .underline: [.command]
        case .strikethrough, .bulletList, .checklist: [.command, .shift]
        }
    }

    var shortcutHint: String {
        let shift = modifiers.contains(.shift) ? "⇧" : ""
        return "\(title)  \(shift)⌘\(keyEquivalent.uppercased())"
    }

    /// Selector sent down the responder chain by the Format menu.
    var selector: Selector {
        switch self {
        case .bold: #selector(NoteTextView.cxToggleBold(_:))
        case .italic: #selector(NoteTextView.cxToggleItalic(_:))
        case .underline: #selector(NoteTextView.cxToggleUnderline(_:))
        case .strikethrough: #selector(NoteTextView.cxToggleStrikethrough(_:))
        case .bulletList: #selector(NoteTextView.cxToggleBulletList(_:))
        case .checklist: #selector(NoteTextView.cxToggleChecklist(_:))
        }
    }
}

/// Note editor: rich text plus list behaviour (continue on Return, click to tick).
final class NoteTextView: NSTextView {

    // MARK: Format commands

    @objc func cxToggleBold(_ sender: Any?) { toggleStyle(\.bold) }
    @objc func cxToggleItalic(_ sender: Any?) { toggleStyle(\.italic) }
    @objc func cxToggleUnderline(_ sender: Any?) { toggleStyle(\.underline) }
    @objc func cxToggleStrikethrough(_ sender: Any?) { toggleStyle(\.strikethrough) }
    @objc func cxToggleBulletList(_ sender: Any?) { toggleList(.bullet) }
    @objc func cxToggleChecklist(_ sender: Any?) { toggleList(.checklist) }

    private func toggleStyle(_ flag: WritableKeyPath<RunStyle, Bool>) {
        guard let storage = textStorage else { return }
        let range = selectedRange()

        if range.length == 0 {
            var style = NoteTextStyle.style(of: typingAttributes)
            style[keyPath: flag].toggle()
            typingAttributes = NoteTextStyle.attributes(for: style)
            return
        }

        var allOn = true
        storage.enumerateAttributes(in: range) { attrs, _, stop in
            if !NoteTextStyle.style(of: attrs)[keyPath: flag] { allOn = false; stop.pointee = true }
        }

        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attrs, subrange, _ in
            var style = NoteTextStyle.style(of: attrs)
            style[keyPath: flag] = !allOn
            storage.setAttributes(NoteTextStyle.attributes(for: style), range: subrange)
        }
        storage.endEditing()
        didChangeText()
    }

    private func toggleList(_ kind: ListEditing.Kind) {
        let selection = selectedRange()
        let edits = ListEditing.toggleEdits(kind, in: textStorage!.string as NSString, selection: selection)
        guard !edits.isEmpty else { return }
        apply(edits)
        // Keep the caret/selection on the same text after markers were added or removed.
        let start = ListEditing.map(selection.location, through: edits)
        let end = ListEditing.map(NSMaxRange(selection), through: edits)
        setSelectedRange(NSRange(location: start, length: end - start))
    }

    /// Applies plain-text edits (back-to-front) with undo support, in the house style.
    func apply(_ edits: [TextEdit]) {
        guard let storage = textStorage else { return }
        for edit in edits {
            guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { continue }
            storage.replaceCharacters(
                in: edit.range,
                with: NSAttributedString(string: edit.replacement, attributes: NoteTextStyle.baseAttributes)
            )
            didChangeText()
        }
    }

    override func didChangeText() {
        if let storage = textStorage { ListEditing.restyleChecklist(in: storage) }
        super.didChangeText()
    }

    // MARK: Lists

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0,
           let result = ListEditing.newlineEdits(in: textStorage!.string as NSString, at: selection.location) {
            apply(result.edits)
            setSelectedRange(NSRange(location: result.cursor, length: 0))
            typingAttributes = NoteTextStyle.baseAttributes
            return
        }
        super.insertNewline(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = checkboxIndex(at: point),
           let edit = ListEditing.checkboxToggleEdit(in: textStorage!.string as NSString, at: index) {
            let selection = selectedRange()
            apply([edit])
            setSelectedRange(selection)
            return
        }
        super.mouseDown(with: event)
    }

    /// Character index of a ☐/☑ under `point`, if any.
    private func checkboxIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: p, in: textContainer)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -3, dy: -2).contains(p) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        let string = textStorage!.string as NSString
        guard index < string.length else { return nil }
        let ch = string.character(at: index)
        return ch == 0x2610 || ch == 0x2611 ? index : nil
    }

    // MARK: Pasting

    /// Pasted text takes on the note's own style, so notes always look like notes.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}
