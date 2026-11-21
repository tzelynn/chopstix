import AppKit
import Testing
@testable import Chopstix

/// Drives a real `MarkdownTextView` in a window, typing a character at a time.
@MainActor @Suite struct MarkdownTextViewTests {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    private let view = MarkdownTextView.make(theme: .sticky(.ramen))

    init() {
        view.frame = window.contentLayoutRect
        window.contentView = view
        window.makeFirstResponder(view)
    }

    private func type(_ text: String) {
        for character in text {
            if character == "\n" {
                view.insertNewline(nil)
            } else {
                view.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
    }

    private var revealed: NSRange? { view.markdownLayout.revealed }

    /// Height of the line fragment holding `character`.
    private func lineHeight(at character: Int) -> CGFloat {
        let layout = view.markdownLayout!
        layout.ensureLayout(for: view.textContainer!)
        return layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: character), effectiveRange: nil).height
    }

    @Test func revealsTheLineBeingTyped() {
        type("# Title\nsecond")
        // A plain caret used to reveal the first paragraph, wherever it was.
        #expect(revealed == NSRange(location: 8, length: 6))
    }

    @Test func revealsBothFencesInsideACodeBlock() {
        type("hi\n```\nlet x\n```\nafter")
        view.setSelectedRange(NSRange(location: 10, length: 0)) // in `let x`
        #expect(revealed == NSRange(location: 3, length: 14))
        #expect(lineHeight(at: 3) > 10)

        // An unclosed block still shows its fence from the empty line at the end.
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.string = ""
        type("```\n")
        #expect(revealed == NSRange(location: 0, length: 4))
    }

    @Test func collapsesFencesOutsideTheCaretsBlock() {
        type("```\nlet x\n```\nafter")
        let fenceHeight = lineHeight(at: 0)
        #expect(fenceHeight < 10)
        #expect(lineHeight(at: 10) == fenceHeight)
        #expect(lineHeight(at: 4) > 10)
    }

    @Test func typesIntoAnInsertedCodeBlock() {
        // As the `/` menu's Code Block does it.
        type("/")
        view.apply(MarkdownChange(edits: [TextEdit(range: NSRange(location: 0, length: 1), replacement: "```\n\n```")],
                                  selection: NSRange(location: 4, length: 0)))
        type("test")
        #expect(view.string == "```\ntest\n```")
        #expect(view.selectedRange() == NSRange(location: 8, length: 0))
    }

    @Test func typingMidLineKeepsTheCaretInPlace() {
        type("hello world")
        view.setSelectedRange(NSRange(location: 5, length: 0))
        type("XY")
        #expect(view.string == "helloXY world")
        #expect(view.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test func turningALineIntoAHeadingKeepsTheCaretInPlace() {
        type("Title")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        type("# ")
        #expect(view.string == "# Title")
        #expect(view.selectedRange() == NSRange(location: 2, length: 0))
    }

    /// Every visible glyph in `view` matches its character in the font it's styled with.
    private func glyphsMatchTheirFonts(in view: MarkdownTextView) -> Bool {
        let layout = view.markdownLayout!
        layout.ensureLayout(for: view.textContainer!)
        let string = view.string as NSString
        return (0..<string.length).allSatisfy { index in
            guard let font = view.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont else { return false }
            var character = string.character(at: index)
            var expected: CGGlyph = 0
            guard CTFontGetGlyphsForCharacters(font as CTFont, &character, &expected, 1) else { return true }
            let glyph = layout.glyphIndexForCharacter(at: index)
            // Hidden syntax is laid out as invisible control characters instead.
            if layout.propertyForGlyph(at: glyph).contains(.controlCharacter) { return true }
            return layout.cgGlyph(at: glyph) == expected
        }
    }

    @Test func restylingRegeneratesEveryGlyph() {
        // Loaded the way `MarkdownEditor` does, before the view is in a window. The last character
        // used to keep a glyph from the unstyled font and draw as the wrong letter ("nap" → "naẺ").
        let fresh = MarkdownTextView.make(theme: .sticky(.udon))
        fresh.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        fresh.markdown = "**slow sunday**\n- laundry\n- nap"
        #expect(glyphsMatchTheirFonts(in: fresh))

        type("**slow sunday**\n- nap\n# heading")
        #expect(glyphsMatchTheirFonts(in: view))
    }

    // MARK: Navigation keys

    private func press(_ key: NSEvent.SpecialKey, _ modifiers: NSEvent.ModifierFlags = []) {
        let command = MarkdownTextView.keyCommand(for: key, modifiers: modifiers)
        #expect(command != nil)
        if let command { view.doCommand(by: command) }
    }

    @Test func endAndHomeMoveWithinTheLine() {
        type("first line\nsecond line")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        press(.end)
        #expect(view.selectedRange() == NSRange(location: 10, length: 0))
        press(.home, .shift)
        #expect(view.selectedRange() == NSRange(location: 0, length: 10))
    }

    @Test func commandArrowsMoveByWord() {
        type("one two three")
        view.setSelectedRange(NSRange(location: 5, length: 0))
        press(.rightArrow, .command)
        #expect(view.selectedRange() == NSRange(location: 7, length: 0))
        press(.leftArrow, .command)
        #expect(view.selectedRange() == NSRange(location: 4, length: 0))
        press(.rightArrow, [.command, .shift])
        #expect(view.selectedRange() == NSRange(location: 4, length: 3))
    }

    @Test func otherKeysKeepTheirDefaults() {
        #expect(MarkdownTextView.keyCommand(for: .leftArrow, modifiers: .option) == nil)
        #expect(MarkdownTextView.keyCommand(for: .upArrow, modifiers: .command) == nil)
        #expect(MarkdownTextView.keyCommand(for: .end, modifiers: .command) == nil)
    }

    @Test func commandDeleteRemovesTheWordBefore() {
        type("one two three")
        press(.delete, .command)
        #expect(view.string == "one two ")
    }

    // MARK: Cutting lines

    private let pasteboard = NSPasteboard(name: .init("chopstix-tests-\(UUID())"))

    private func cutLine(at caret: Int) -> String? {
        view.linePasteboard = pasteboard
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.cut(nil)
        return pasteboard.string(forType: .string)
    }

    @Test func cutWithNoSelectionTakesTheLine() {
        type("one\ntwo\nthree")
        #expect(cutLine(at: 5) == "two\n")
        #expect(view.string == "one\nthree")
        #expect(view.selectedRange() == NSRange(location: 4, length: 0))
    }

    @Test func cuttingTheLastLineTakesTheNewlineBefore() {
        view.markdown = "one\ntwo" // not typed, so undo only reverts the cut
        #expect(cutLine(at: 6) == "two\n")
        #expect(view.string == "one")
        view.undoManager?.undo()
        #expect(view.string == "one\ntwo")
    }

    @Test func pastingACutLineInsertsItAbove() {
        type("one\ntwo\nthree")
        _ = cutLine(at: 1)              // "two\nthree", caret at the start of "two"
        view.setSelectedRange(NSRange(location: 6, length: 0)) // "th|ree"
        view.paste(nil)
        #expect(view.string == "two\none\nthree")
        #expect(view.selectedRange() == NSRange(location: 10, length: 0)) // still "th|ree"
    }
}
