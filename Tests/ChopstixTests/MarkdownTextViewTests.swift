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
}
