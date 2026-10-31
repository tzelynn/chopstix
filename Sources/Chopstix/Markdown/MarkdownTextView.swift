import AppKit

/// Markdown-only commands, for the Format menu and toolbars. Commands shared with sticky notes
/// (bold, italic, lists…) reuse `FormatAction`'s selectors, so one shortcut works in both editors.
enum MarkdownAction: CaseIterable, Identifiable {
    case heading1, heading2, heading3, body, cycleHeading, numberedList, quote, inlineCode, highlight, link

    var id: Self { self }

    var title: String {
        switch self {
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .body: "Body Text"
        case .cycleHeading: "Heading"
        case .numberedList: "Numbered List"
        case .quote: "Quote"
        case .inlineCode: "Code"
        case .highlight: "Highlight"
        case .link: "Link…"
        }
    }

    var symbol: String {
        switch self {
        case .heading1, .heading2, .heading3, .cycleHeading: "textformat.size"
        case .body: "text.alignleft"
        case .numberedList: "list.number"
        case .quote: "text.quote"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .highlight: "highlighter"
        case .link: "link"
        }
    }

    /// Key equivalent and modifiers, if the command has a shortcut.
    var shortcut: (key: String, modifiers: NSEvent.ModifierFlags)? {
        switch self {
        case .heading1: ("1", [.command, .option])
        case .heading2: ("2", [.command, .option])
        case .heading3: ("3", [.command, .option])
        case .body: ("0", [.command, .option])
        case .numberedList: ("9", [.command, .shift])
        case .inlineCode: ("e", [.command])
        case .highlight: ("h", [.command, .shift])
        case .link: ("k", [.command])
        case .cycleHeading, .quote: nil
        }
    }

    var help: String {
        guard let shortcut else { return title }
        let m = shortcut.modifiers
        let keys = (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "") + "⌘" + shortcut.key.uppercased()
        return "\(title)  \(keys)"
    }

    var selector: Selector {
        switch self {
        case .heading1: #selector(MarkdownTextView.mdHeading1(_:))
        case .heading2: #selector(MarkdownTextView.mdHeading2(_:))
        case .heading3: #selector(MarkdownTextView.mdHeading3(_:))
        case .body: #selector(MarkdownTextView.mdBody(_:))
        case .cycleHeading: #selector(MarkdownTextView.mdCycleHeading(_:))
        case .numberedList: #selector(MarkdownTextView.mdNumberedList(_:))
        case .quote: #selector(MarkdownTextView.mdQuote(_:))
        case .inlineCode: #selector(MarkdownTextView.mdInlineCode(_:))
        case .highlight: #selector(MarkdownTextView.mdHighlight(_:))
        case .link: #selector(MarkdownTextView.mdLink(_:))
        }
    }
}

/// The markdown editor: plain markdown text, styled as it's typed by `MarkdownStyler`, with
/// syntax tucked away by `MarkdownLayoutManager` everywhere but the line being edited.
final class MarkdownTextView: NSTextView {
    private(set) var markdownLayout: MarkdownLayoutManager!
    private var lastFenceCount = 0

    var theme: MarkdownTheme {
        get { markdownLayout.theme }
        set {
            guard newValue != markdownLayout.theme else { return }
            markdownLayout.theme = newValue
            insertionPointColor = newValue.ink
            // Outside of an edit, so batch the restyle into one.
            textStorage?.beginEditing()
            restyle(nil)
            textStorage?.endEditing()
        }
    }

    /// Builds the TextKit 1 stack around a `MarkdownLayoutManager`.
    static func make(theme: MarkdownTheme) -> MarkdownTextView {
        let storage = MarkdownTextStorage()
        let layout = MarkdownLayoutManager(theme: theme)
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let view = MarkdownTextView(frame: .zero, textContainer: container)
        view.markdownLayout = layout
        storage.didEditCharacters = { [weak view] edited in
            view?.restyle(edited)
            // The selection moved before the restyle; reveal again with code blocks known.
            view?.updateRevealedRange()
        }
        view.isRichText = false // pasted and dropped text is always plain markdown
        view.allowsUndo = true
        view.importsGraphics = false
        view.usesFontPanel = false
        view.drawsBackground = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false // `---` must stay a rule
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.insertionPointColor = theme.ink
        view.typingAttributes = theme.bodyAttributes
        NotificationCenter.default.addObserver(view, selector: #selector(selectionDidChange(_:)),
                                               name: NSTextView.didChangeSelectionNotification, object: view)
        return view
    }

    var markdown: String {
        get { string }
        // Styled by `MarkdownTextStorage`, like any other edit.
        set { textStorage?.replaceCharacters(in: NSRange(location: 0, length: (string as NSString).length), with: newValue) }
    }

    // MARK: Styling

    /// Restyles the paragraphs around `edited`, or everything if `nil` or a code fence changed
    /// (a fence can restyle the whole rest of the note).
    private func restyle(_ edited: NSRange?) {
        guard let storage = textStorage, let markdownLayout else { return }
        let string = storage.string as NSString
        let tokens = MarkdownParser.parse(string)
        let fences = tokens.reduce(0) { count, token in
            token.kind == .syntax && string.substring(with: token.range).hasPrefix("```") ? count + 1 : count
        }
        var range = NSRange(location: 0, length: string.length)
        if let edited, fences == lastFenceCount {
            range = string.paragraphRange(for: NSIntersectionRange(edited, range))
        }
        lastFenceCount = fences
        MarkdownStyler.style(storage, tokens: tokens, in: range, theme: markdownLayout.theme)
    }

    // MARK: Revealing syntax around the caret

    /// Typing moves the selection without going through `setSelectedRanges`, so follow the
    /// notification, which every selection change posts.
    @objc private func selectionDidChange(_ notification: Notification) {
        updateRevealedRange()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { updateRevealedRange() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { markdownLayout?.setRevealed(nil) }
        return resigned
    }

    private func updateRevealedRange() {
        guard let markdownLayout, window?.firstResponder === self else { return }
        let string = self.string as NSString
        let all = NSRange(location: 0, length: string.length)
        // Not `NSIntersectionRange`, which turns any empty selection (a plain caret) into {0, 0}.
        let selected = selectedRange()
        let start = min(selected.location, string.length)
        let selection = NSRange(location: start, length: min(selected.length, string.length - start))
        var revealed = string.paragraphRange(for: selection)
        // Inside a code block, show both fences, so it's clear where the block starts and ends.
        if let storage = textStorage {
            // An empty last line has no characters of its own; it belongs to whatever ends just before it.
            let edges = revealed.length == 0 ? [revealed.location - 1] : [revealed.location, NSMaxRange(revealed) - 1]
            for edge in edges where edge >= 0 && edge < storage.length {
                var block = NSRange()
                let value = storage.attribute(.cxDecoration, at: edge, longestEffectiveRange: &block, in: all) as? Int
                if value == MarkdownDecoration.codeBlock.rawValue {
                    revealed = NSUnionRange(revealed, string.paragraphRange(for: block))
                }
            }
        }
        markdownLayout.setRevealed(revealed)
    }

    // MARK: Applying changes

    /// Applies edits (back-to-front) with undo support, then moves the selection.
    func apply(_ change: MarkdownChange) {
        guard let storage = textStorage else { return }
        for edit in change.edits {
            guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { continue }
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
            didChangeText()
        }
        setSelectedRange(change.selection)
        scrollRangeToVisible(change.selection)
    }

    private var nsString: NSString { string as NSString }

    // MARK: Commands shared with sticky notes (see `FormatAction`)

    @objc func cxToggleBold(_ sender: Any?) { wrap("**") }
    @objc func cxToggleItalic(_ sender: Any?) { wrap("*") }
    @objc func cxToggleStrikethrough(_ sender: Any?) { wrap("~~") }
    @objc func cxToggleBulletList(_ sender: Any?) { setLineKind(.bullet) }
    @objc func cxToggleChecklist(_ sender: Any?) { setLineKind(.task) }

    // MARK: Markdown commands (see `MarkdownAction`)

    @objc func mdHeading1(_ sender: Any?) { setLineKind(.heading(1)) }
    @objc func mdHeading2(_ sender: Any?) { setLineKind(.heading(2)) }
    @objc func mdHeading3(_ sender: Any?) { setLineKind(.heading(3)) }
    @objc func mdBody(_ sender: Any?) { setLineKind(.body) }
    @objc func mdNumberedList(_ sender: Any?) { setLineKind(.number) }
    @objc func mdQuote(_ sender: Any?) { setLineKind(.quote) }
    @objc func mdInlineCode(_ sender: Any?) { wrap("`") }
    @objc func mdHighlight(_ sender: Any?) { wrap("==") }
    @objc func mdCycleHeading(_ sender: Any?) { apply(MarkdownEditing.cycleHeading(in: nsString, selection: selectedRange())) }

    @objc func mdLink(_ sender: Any?) {
        apply(MarkdownEditing.link(in: nsString, selection: selectedRange(), url: Self.clipboardURL()))
    }

    private func wrap(_ marker: String) {
        guard let change = MarkdownEditing.toggleWrap(marker, in: nsString, selection: selectedRange()) else { return }
        apply(change)
    }

    private func setLineKind(_ kind: MarkdownEditing.LineKind) {
        apply(MarkdownEditing.setLineKind(kind, in: nsString, selection: selectedRange()))
    }

    // MARK: Keys

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0,
           let change = MarkdownEditing.newline(in: nsString, at: selection.location, inCodeBlock: isInCodeBlock(selection.location)) {
            apply(change)
            return
        }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if let change = MarkdownEditing.indent(in: nsString, selection: selectedRange(), outdent: false) {
            apply(change)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if let change = MarkdownEditing.indent(in: nsString, selection: selectedRange(), outdent: true) {
            apply(change)
        } else {
            super.insertBacktab(sender)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, let change = MarkdownEditing.backspace(in: nsString, at: selection.location) {
            apply(change)
            return
        }
        super.deleteBackward(sender)
    }

    private func isInCodeBlock(_ location: Int) -> Bool {
        guard let storage = textStorage, location > 0, location <= storage.length else { return false }
        let value = storage.attribute(.cxDecoration, at: location - 1, effectiveRange: nil) as? Int
        return value == MarkdownDecoration.codeBlock.rawValue
    }

    // MARK: The `/` menu

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let selection = selectedRange()
        let line = MarkdownEditing.line(at: selection.location, in: nsString)
        let opensMenu = (string as? String) == "/" && selection.length == 0 && line.marker == .none
            && nsString.substring(with: line.range).trimmingCharacters(in: .whitespaces).isEmpty
        super.insertText(string, replacementRange: replacementRange)
        if opensMenu {
            let slash = selectedRange().location - 1
            DispatchQueue.main.async { [weak self] in self?.showBlockMenu(replacingSlashAt: slash) }
        }
    }

    private struct Block {
        let title: String
        let symbol: String
        let markdown: String
        /// Where the caret goes within `markdown` (end if `nil`).
        var caret: Int?
    }

    private static let blocks: [Block] = [
        Block(title: "Heading 1", symbol: "textformat.size.larger", markdown: "# "),
        Block(title: "Heading 2", symbol: "textformat.size", markdown: "## "),
        Block(title: "Heading 3", symbol: "textformat.size.smaller", markdown: "### "),
        Block(title: "Bulleted List", symbol: "list.bullet", markdown: "- "),
        Block(title: "Numbered List", symbol: "list.number", markdown: "1. "),
        Block(title: "To-do", symbol: "checklist", markdown: "- [ ] "),
        Block(title: "Quote", symbol: "text.quote", markdown: "> "),
        Block(title: "Code Block", symbol: "chevron.left.forwardslash.chevron.right", markdown: "```\n\n```", caret: 4),
        Block(title: "Divider", symbol: "minus", markdown: "---\n"),
    ]

    private func showBlockMenu(replacingSlashAt slash: Int) {
        guard slash >= 0, slash < nsString.length, nsString.character(at: slash) == 0x2F /* / */,
              let layoutManager, let textContainer else { return }
        let menu = NSMenu(title: "Blocks")
        menu.autoenablesItems = false
        let header = menu.addItem(withTitle: "Turn into", action: nil, keyEquivalent: "")
        header.isEnabled = false
        for (index, block) in Self.blocks.enumerated() {
            let item = menu.addItem(withTitle: block.title, action: #selector(chooseBlock(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.representedObject = slash
            item.image = NSImage(systemSymbolName: block.symbol, accessibilityDescription: nil)
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: slash)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        let point = NSPoint(x: rect.minX + textContainerOrigin.x, y: rect.maxY + textContainerOrigin.y + 4)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func chooseBlock(_ sender: NSMenuItem) {
        guard let slash = sender.representedObject as? Int, Self.blocks.indices.contains(sender.tag),
              slash < nsString.length, nsString.character(at: slash) == 0x2F else { return }
        let block = Self.blocks[sender.tag]
        let caret = slash + (block.caret ?? (block.markdown as NSString).length)
        apply(MarkdownChange(edits: [TextEdit(range: NSRange(location: slash, length: 1), replacement: block.markdown)],
                             selection: NSRange(location: caret, length: 0)))
    }

    // MARK: Mouse: checkboxes and links

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let box = taskBox(at: point), let edit = MarkdownEditing.toggleTask(in: nsString, boxLocation: box.location) {
            let selection = selectedRange()
            apply(MarkdownChange(edits: [edit], selection: selection))
            return
        }
        if event.modifierFlags.contains(.command), let url = link(at: point) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if taskBox(at: point) != nil || (event.modifierFlags.contains(.command) && link(at: point) != nil) {
            NSCursor.pointingHand.set()
        }
    }

    /// The character under `point`, if the point is really over it (not just nearest to it).
    private func characterIndex(at point: NSPoint, slop: CGFloat = 2) -> Int? {
        guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: p, in: textContainer)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -slop, dy: -slop).contains(p) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return index < nsString.length ? index : nil
    }

    /// The `[ ]` of a to-do under `point`.
    private func taskBox(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, let index = characterIndex(at: point, slop: 3) else { return nil }
        var range = NSRange()
        let value = storage.attribute(.cxDecoration, at: index, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) as? Int
        guard value == MarkdownDecoration.task.rawValue || value == MarkdownDecoration.taskDone.rawValue else { return nil }
        return range
    }

    private func link(at point: NSPoint) -> URL? {
        guard let index = characterIndex(at: point),
              let target = textStorage?.attribute(.cxLink, at: index, effectiveRange: nil) as? String else { return nil }
        return URL(string: target)
    }

    // MARK: Pasting

    /// Pasting a URL over selected text links it; everything else pastes as plain text.
    override func paste(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length > 0, let url = Self.clipboardURL() {
            apply(MarkdownEditing.link(in: nsString, selection: selection, url: url))
            return
        }
        pasteAsPlainText(sender)
    }

    private static func clipboardURL() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: \.isWhitespace),
              let url = URL(string: text), let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme) else { return nil }
        return text
    }
}

/// Text storage that restyles after each character edit, as an edit of its own.
///
/// Restyling in `willProcessEditing` widens the edit to the whole restyled paragraph, and
/// NSTextView then moves the caret to the end of it — so typing mid-line jumped to the end of
/// the line. An attributes-only edit afterwards leaves the selection alone.
final class MarkdownTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()
    /// Called with the edited range (in the new text) after each change to the characters.
    var didEditCharacters: ((NSRange) -> Void)?

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    override func processEditing() {
        let charactersChanged = editedMask.contains(.editedCharacters)
        let range = editedRange
        super.processEditing()
        guard charactersChanged, let didEditCharacters else { return }
        beginEditing()
        didEditCharacters(range)
        endEditing()
    }
}
