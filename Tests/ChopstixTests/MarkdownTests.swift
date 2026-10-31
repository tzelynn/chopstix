import AppKit
import Testing
@testable import Chopstix

/// Applies a change's back-to-front edits the same way `MarkdownTextView.apply` does.
private func applying(_ change: MarkdownChange?, to string: String) -> String {
    let result = NSMutableString(string: string)
    for edit in change?.edits ?? [] { result.replaceCharacters(in: edit.range, with: edit.replacement) }
    return result as String
}

/// The source text of every token of `kind` (compared loosely, ignoring payloads like URLs).
private func texts(_ markdown: String, _ matches: (MarkdownToken.Kind) -> Bool) -> [String] {
    MarkdownParser.parse(markdown).filter { matches($0.kind) }.map { (markdown as NSString).substring(with: $0.range) }
}

private func sel(_ location: Int, _ length: Int = 0) -> NSRange { NSRange(location: location, length: length) }

@Suite struct MarkdownParserTests {
    @Test func headingsHideTheirMarker() {
        let tokens = MarkdownParser.parse("## Plan")
        #expect(tokens.contains(MarkdownToken(.heading(2), sel(3, 4))))
        #expect(tokens.contains(MarkdownToken(.syntax, sel(0, 3))))
        #expect(texts("#hashtag", { $0 == .heading(1) }).isEmpty)
    }

    @Test func inlineStyles() {
        let md = "**b** *i* ~~s~~ ==h== `c`"
        #expect(texts(md, { $0 == .bold }) == ["b"])
        #expect(texts(md, { $0 == .italic }) == ["i"])
        #expect(texts(md, { $0 == .strikethrough }) == ["s"])
        #expect(texts(md, { $0 == .highlight }) == ["h"])
        #expect(texts(md, { $0 == .code }) == ["c"])
        let syntax = MarkdownParser.parse(md).filter { $0.kind == .syntax }.sorted { $0.range.location < $1.range.location }
        #expect(syntax.map { (md as NSString).substring(with: $0.range) } == ["**", "**", "*", "*", "~~", "~~", "==", "==", "`", "`"])
    }

    @Test func boldItalicTogether() {
        let md = "***x***"
        #expect(texts(md, { $0 == .bold }).count == 1)
        #expect(texts(md, { $0 == .italic }).count == 1)
        #expect(texts(md, { $0 == .syntax }).joined() == "******")
    }

    @Test func noEmphasisInsideCodeOrWords() {
        #expect(texts("`a*b*c`", { $0 == .italic }).isEmpty)
        #expect(texts("snake_case_name", { $0 == .italic }).isEmpty)
        #expect(texts("2 * 3 * 4", { $0 == .italic }).isEmpty)
    }

    @Test func escapedMarkersAreLiteral() {
        #expect(texts(#"\*not italic\*"#, { $0 == .italic }).isEmpty)
        #expect(texts(#"\*not italic\*"#, { $0 == .syntax }) == [#"\"#, #"\"#])
    }

    @Test func links() {
        let tokens = MarkdownParser.parse("see [docs](https://x.org/a_b_c) now")
        #expect(tokens.contains(MarkdownToken(.link("https://x.org/a_b_c"), sel(5, 4))))
        #expect(texts("see [docs](https://x.org/a_b_c) now", { $0 == .syntax }) == ["[", "](https://x.org/a_b_c)"])
        // Bare URLs link themselves; trailing punctuation isn't part of them.
        #expect(texts("go to https://example.com/x_y.", { if case .link = $0 { true } else { false } }) == ["https://example.com/x_y"])
    }

    @Test func lists() {
        #expect(texts("- a\n* b\n+ c", { $0 == .bullet }) == ["-", "*", "+"])
        #expect(texts("1. a\n10) b", { $0 == .number }) == ["1.", "10)"])
        #expect(texts("-no space", { $0 == .bullet }).isEmpty)
        let md = "- [ ] open\n- [x] done"
        #expect(texts(md, { $0 == .task(checked: false) }) == ["[ ]"])
        #expect(texts(md, { $0 == .task(checked: true) }) == ["[x]"])
        #expect(texts(md, { $0 == .done }) == ["done"])
        #expect(MarkdownParser.parse("    - [ ] nested").contains(MarkdownToken(.listLine(prefix: 10), sel(0, 16))))
    }

    @Test func quotesAndRules() {
        #expect(texts("> said", { $0 == .quote }) == ["> said"])
        #expect(texts("---\n* * *", { $0 == .rule }) == ["---", "* * *"])
        #expect(texts("- not a rule", { $0 == .rule }).isEmpty)
    }

    @Test func codeBlocksSwallowMarkdown() {
        let md = "a\n```swift\n# not a heading\n**no**\n```\nb **yes**"
        #expect(texts(md, { $0 == .codeBlock }) == ["```swift\n# not a heading\n**no**\n```"])
        #expect(texts(md, { if case .heading = $0 { true } else { false } }).isEmpty)
        #expect(texts(md, { $0 == .bold }) == ["yes"])
        // An unclosed fence runs to the end.
        #expect(texts("```\ncode", { $0 == .codeBlock }) == ["```\ncode"])
    }

    @Test func handlesEmojiOffsets() {
        let md = "🍜 **ramen**"
        #expect(texts(md, { $0 == .bold }) == ["ramen"])
    }
}

@Suite struct MarkdownEditingTests {
    private func newline(_ s: String, at location: Int, code: Bool = false) -> String? {
        MarkdownEditing.newline(in: s as NSString, at: location, inCodeBlock: code).map { applying($0, to: s) }
    }

    @Test func returnContinuesLists() {
        #expect(newline("- a", at: 3) == "- a\n- ")
        #expect(newline("* a", at: 3) == "* a\n* ")
        #expect(newline("- [x] a", at: 7) == "- [x] a\n- [ ] ")
        #expect(newline("9. a", at: 4) == "9. a\n10. ")
        #expect(newline("> a", at: 3) == "> a\n> ")
        #expect(newline("    - a", at: 7) == "    - a\n    - ")
        #expect(newline("plain", at: 5) == nil)
        #expect(newline("# Title", at: 7) == nil)
    }

    @Test func returnOnEmptyItemUnnestsThenEnds() {
        #expect(newline("- a\n    - ", at: 10) == "- a\n- ")
        #expect(newline("- a\n- ", at: 6) == "- a\n")
        #expect(newline("- [ ] ", at: 6) == "")
    }

    @Test func returnKeepsCodeIndent() {
        #expect(newline("    let x", at: 9, code: true) == "    let x\n    ")
        #expect(newline("let x", at: 5, code: true) == nil)
    }

    @Test func returnPlacesCaretAfterNewMarker() {
        let change = MarkdownEditing.newline(in: "1. a", at: 4)
        #expect(change?.selection == sel(8))
    }

    @Test func tabNestsListItemsOnly() {
        let s = "- a\n- b"
        #expect(applying(MarkdownEditing.indent(in: s as NSString, selection: sel(6), outdent: false), to: s) == "- a\n    - b")
        #expect(applying(MarkdownEditing.indent(in: "    - b", selection: sel(6), outdent: true), to: "    - b") == "- b")
        #expect(applying(MarkdownEditing.indent(in: "\t- b", selection: sel(3), outdent: true), to: "\t- b") == "- b")
        #expect(MarkdownEditing.indent(in: "plain", selection: sel(2), outdent: false) == nil)
    }

    @Test func backspaceAfterMarkerRemovesIt() {
        #expect(applying(MarkdownEditing.backspace(in: "- a", at: 2), to: "- a") == "a")
        #expect(applying(MarkdownEditing.backspace(in: "## a", at: 3), to: "## a") == "a")
        #expect(applying(MarkdownEditing.backspace(in: "    - a", at: 6), to: "    - a") == "- a")
        #expect(MarkdownEditing.backspace(in: "- ab", at: 3) == nil)
    }

    @Test func wrapAndUnwrap() {
        let wrapped = MarkdownEditing.toggleWrap("**", in: "say hi", selection: sel(4, 2))
        #expect(applying(wrapped, to: "say hi") == "say **hi**")
        #expect(wrapped?.selection == sel(6, 2))
        #expect(applying(MarkdownEditing.toggleWrap("**", in: "say **hi**", selection: sel(6, 2)), to: "say **hi**") == "say hi")
    }

    @Test func wrapLeavesSurroundingSpacesOutside() {
        #expect(applying(MarkdownEditing.toggleWrap("*", in: "a b c", selection: sel(1, 3)), to: "a b c") == "a *b* c")
    }

    @Test func italicAndBoldShareStarsWithoutConfusion() {
        // Italic inside bold adds italic rather than eating a bold star.
        #expect(applying(MarkdownEditing.toggleWrap("*", in: "**x**", selection: sel(2, 1)), to: "**x**") == "***x***")
        #expect(applying(MarkdownEditing.toggleWrap("*", in: "***x***", selection: sel(3, 1)), to: "***x***") == "**x**")
        #expect(applying(MarkdownEditing.toggleWrap("**", in: "***x***", selection: sel(3, 1)), to: "***x***") == "*x*")
    }

    @Test func wrapWithCaretInsertsPairAndRemovesEmptyPair() {
        let inserted = MarkdownEditing.toggleWrap("`", in: "a ", selection: sel(2))
        #expect(applying(inserted, to: "a ") == "a ``")
        #expect(inserted?.selection == sel(3))
        #expect(applying(MarkdownEditing.toggleWrap("`", in: "a ``", selection: sel(3)), to: "a ``") == "a ")
    }

    @Test func wrapsEachLineSeparately() {
        let s = "- one\n- two"
        #expect(applying(MarkdownEditing.toggleWrap("**", in: s as NSString, selection: sel(0, 11)), to: s) == "- **one**\n- **two**")
    }

    @Test func lineKinds() {
        func set(_ kind: MarkdownEditing.LineKind, _ s: String, _ selection: NSRange) -> String {
            applying(MarkdownEditing.setLineKind(kind, in: s as NSString, selection: selection), to: s)
        }
        #expect(set(.bullet, "a\nb", sel(0, 3)) == "- a\n- b")
        #expect(set(.bullet, "- a\n- b", sel(0, 7)) == "a\nb")
        #expect(set(.task, "- a", sel(0)) == "- [ ] a")
        #expect(set(.number, "a\nb\nc", sel(0, 5)) == "1. a\n2. b\n3. c")
        #expect(set(.heading(2), "# a", sel(0)) == "## a")
        #expect(set(.heading(2), "## a", sel(0)) == "a")
        #expect(set(.quote, "    - a", sel(0)) == "> a")
        #expect(set(.body, "> a", sel(0)) == "a")
    }

    @Test func cycleHeading() {
        func cycle(_ s: String) -> String { applying(MarkdownEditing.cycleHeading(in: s as NSString, selection: sel(0)), to: s) }
        #expect(cycle("a") == "# a")
        #expect(cycle("# a") == "## a")
        #expect(cycle("### a") == "a")
    }

    @Test func toggleTask() {
        #expect(MarkdownEditing.toggleTask(in: "- [ ] a", boxLocation: 2) == TextEdit(range: sel(3, 1), replacement: "x"))
        #expect(MarkdownEditing.toggleTask(in: "- [x] a", boxLocation: 2) == TextEdit(range: sel(3, 1), replacement: " "))
        #expect(MarkdownEditing.toggleTask(in: "- a", boxLocation: 0) == nil)
    }

    @Test func links() {
        let s = "see docs"
        let change = MarkdownEditing.link(in: s as NSString, selection: sel(4, 4))
        #expect(applying(change, to: s) == "see [docs](url)")
        #expect(change.selection == sel(11, 3))
        let pasted = MarkdownEditing.link(in: s as NSString, selection: sel(4, 4), url: "https://a.b")
        #expect(applying(pasted, to: s) == "see [docs](https://a.b)")
        #expect(pasted.selection == sel(23))
    }
}

@Suite struct MarkdownConversionTests {
    @Test func plainSummaryDropsSyntax() {
        #expect(MarkdownPlainText.summary(of: "# Title\n**bold** and [link](http://x)") == "Title\nbold and link")
        #expect(MarkdownPlainText.summary(of: "- a\n- [ ] b\n- [x] c") == "• a\n☐ b\n☑ c")
    }

    @Test func markdownNoteTitleAndPreview() {
        let note = Note(number: 1, flavor: .pho, kind: .markdown, markdown: "\n## Reading notes\n- [ ] chapter 1\n\n> quote", isOnScreen: false)
        #expect(note.title == "Reading notes")
        #expect(note.preview == "☐ chapter 1\nquote")
        #expect(Note(number: 1, flavor: .pho, kind: .markdown, markdown: "#\n- [ ] ", isOnScreen: false).isEmpty)
    }

    @Test func wordCount() {
        #expect(MarkdownPlainText.wordCount(of: "# Two words\n- **and** three more") == 5)
    }

    @Test func richTextBecomesMarkdown() {
        let runs = [
            TextRun(text: "today", style: RunStyle(bold: true)),
            TextRun(text: "\n☑ wake up\n☐ eat "),
            TextRun(text: "laksa ", style: RunStyle(italic: true)),
            TextRun(text: "\n• "),
            TextRun(text: "old", style: RunStyle(strikethrough: true)),
            TextRun(text: " plan *1*"),
        ]
        #expect(MarkdownConversion.markdown(from: runs) == "**today**\n- [x] wake up\n- [ ] eat *laksa* \n- ~~old~~ plan \\*1\\*")
    }

    @Test func conversionEscapesAccidentalBlocks() {
        #expect(MarkdownConversion.markdown(from: [TextRun(text: "# not a heading\n1. not a list\n---")])
            == "\\# not a heading\n1\\. not a list\n\\---")
    }

    @Test func convertedTextReadsBackTheSame() {
        let runs = [TextRun(text: "a_b __c__ ="), TextRun(text: "x", style: RunStyle(bold: true))]
        let markdown = MarkdownConversion.markdown(from: runs)
        #expect(MarkdownPlainText.summary(of: markdown) == "a_b __c__ =x")
    }
}

@Suite struct MarkdownStorageTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("chopstix-tests-\(UUID().uuidString)")
    }

    @Test func bodiesLiveInTheirOwnFiles() throws {
        let dir = tempDir()
        let store = NoteStore(directory: dir)
        let note = Note(number: 1, flavor: .ramen, kind: .markdown, markdown: "# hi\nthere", isOnScreen: true)
        store.add(note)
        store.saveNow()

        let index = try String(contentsOf: dir.appendingPathComponent("notes.json"), encoding: .utf8)
        #expect(!index.contains("there"))
        #expect(index.contains("\"kind\" : \"markdown\""))
        #expect(try String(contentsOf: store.bodyURL(note.id), encoding: .utf8) == "# hi\nthere")

        let reloaded = NoteStore(directory: dir)
        reloaded.load()
        #expect(reloaded.note(note.id)?.markdown == "# hi\nthere")
        #expect(reloaded.note(note.id)?.kind == .markdown)
    }

    @Test func onlyChangedBodiesAreRewritten() throws {
        let dir = tempDir()
        let store = NoteStore(directory: dir)
        let a = Note(number: 1, flavor: .ramen, kind: .markdown, markdown: "a", isOnScreen: false)
        let b = Note(number: 2, flavor: .ramen, kind: .markdown, markdown: "b", isOnScreen: false)
        store.add(a)
        store.add(b)
        store.saveNow()
        let before = try FileManager.default.attributesOfItem(atPath: store.bodyURL(b.id).path)[.modificationDate] as? Date

        Thread.sleep(forTimeInterval: 0.05)
        store.update(a.id) { $0.markdown = "a2" }
        store.saveNow()
        let after = try FileManager.default.attributesOfItem(atPath: store.bodyURL(b.id).path)[.modificationDate] as? Date
        #expect(before == after)
        #expect(try String(contentsOf: store.bodyURL(a.id), encoding: .utf8) == "a2")
    }

    @Test func deletingRemovesTheBody() {
        let dir = tempDir()
        let store = NoteStore(directory: dir)
        let note = Note(number: 1, flavor: .ramen, kind: .markdown, markdown: "x", isOnScreen: false)
        store.add(note)
        store.saveNow()
        store.remove(note.id)
        store.saveNow()
        #expect(!FileManager.default.fileExists(atPath: store.bodyURL(note.id).path))
    }

    @Test func lostIndexRecoversBodiesAndBackup() throws {
        let dir = tempDir()
        let store = NoteStore(directory: dir)
        let sticky = Note(number: 1, flavor: .laksa, content: [TextRun(text: "sticky")], isOnScreen: false)
        let page = Note(number: 2, flavor: .ramen, kind: .markdown, markdown: "# kept", isOnScreen: false)
        store.add(sticky)
        store.add(page)
        store.saveNow()
        NoteStore(directory: dir).load() // a clean launch takes the backup

        try Data("garbage".utf8).write(to: dir.appendingPathComponent("notes.json"))
        let recovered = NoteStore(directory: dir)
        #expect(recovered.load())
        #expect(recovered.note(sticky.id)?.plainText == "sticky")
        #expect(recovered.note(page.id)?.markdown == "# kept")
    }

    @Test func orphanBodiesAreAdopted() throws {
        let dir = tempDir()
        let id = UUID()
        let markdown = dir.appendingPathComponent("markdown", isDirectory: true)
        try FileManager.default.createDirectory(at: markdown, withIntermediateDirectories: true)
        try Data("# orphan".utf8).write(to: markdown.appendingPathComponent("\(id.uuidString).md"))

        let store = NoteStore(directory: dir)
        #expect(store.load())
        #expect(store.note(id)?.title == "orphan")
        #expect(store.note(id)?.isOnScreen == false)
    }

    @Test func versionOneFilesStillLoad() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let v1 = """
        {"version":1,"notes":[{"id":"6F1C5B8E-1C2D-4C47-9E33-9B0F7A8E2C11","number":3,"flavor":"pho",
        "content":[{"text":"old"}],"isOnScreen":false,"alwaysOnTop":false,
        "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}]}
        """
        try Data(v1.utf8).write(to: dir.appendingPathComponent("notes.json"))
        let store = NoteStore(directory: dir)
        store.load()
        #expect(store.notes.first?.kind == .sticky)
        #expect(store.notes.first?.plainText == "old")
    }
}
