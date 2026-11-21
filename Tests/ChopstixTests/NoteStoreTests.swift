import AppKit
import Testing
@testable import Chopstix

/// Applies back-to-front edits the same way the editors do.
private func applying(_ edits: [TextEdit], to string: String) -> String {
    let result = NSMutableString(string: string)
    for edit in edits { result.replaceCharacters(in: edit.range, with: edit.replacement) }
    return result as String
}

@Suite struct ListEditingTests {
    @Test func paragraphRangesCoverEverySelectedLine() {
        let ranges = ListEditing.paragraphRanges(in: "a\nb\nc", for: NSRange(location: 0, length: 3))
        #expect(ranges == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2)])
    }

    @Test func mapsCaretThroughEdits() {
        let edits = [TextEdit(range: NSRange(location: 3, length: 0), replacement: "- "),
                     TextEdit(range: NSRange(location: 0, length: 0), replacement: "- ")]
        #expect(applying(edits, to: "ab\ncd") == "- ab\n- cd")
        #expect(ListEditing.map(1, through: edits) == 3)  // a|b → - a|b
        #expect(ListEditing.map(4, through: edits) == 8)  // c|d → - c|d
        let removal = [TextEdit(range: NSRange(location: 0, length: 2), replacement: "")]
        #expect(ListEditing.map(1, through: removal) == 0) // caret inside a removed marker snaps to line start
    }
}

@Suite struct NoteTests {
    private func note(_ markdown: String) -> Note {
        Note(number: 1, flavor: .ramen, markdown: markdown, isOnScreen: false)
    }

    @Test func titleSkipsBlankLinesAndMarkers() {
        #expect(note("\n- [ ] buy milk\n- eggs").title == "buy milk")
        #expect(note("\n- [ ] buy milk\n\n- eggs").preview == "• eggs")
    }

    @Test func bareMarkersCountAsEmpty() {
        #expect(note("- [ ] \n- ").isEmpty)
        #expect(!note("- [ ] x").isEmpty)
    }
}

@Suite struct NoteStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("chopstix-tests-\(UUID().uuidString)")
    }

    @Test func savesAndLoads() {
        let dir = tempDir()
        let store = NoteStore(directory: dir)
        #expect(store.load() == false)
        let note = Note(number: store.nextNumber, flavor: .laksa, markdown: "hi", isOnScreen: true,
                        frame: CGRect(x: 10, y: 20, width: 260, height: 264))
        store.add(note)
        store.saveNow()

        let reloaded = NoteStore(directory: dir)
        #expect(reloaded.load() == true)
        #expect(reloaded.notes.count == 1)
        #expect(reloaded.notes.first?.markdown == "hi")
        #expect(reloaded.notes.first?.frame == note.frame)
        #expect(reloaded.nextNumber == 2)
    }

    @Test func setsAsideUnreadableFiles() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("notes.json"))

        let store = NoteStore(directory: dir)
        #expect(store.load() == true)
        #expect(store.notes.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("notes.unreadable-") })
    }
}
