import AppKit
import Testing
@testable import Chopstix

@Suite struct RichTextCodecTests {
    @Test func roundTripsEveryStyle() {
        let runs = [
            TextRun(text: "plain "),
            TextRun(text: "bold", style: RunStyle(bold: true)),
            TextRun(text: " "),
            TextRun(text: "italic", style: RunStyle(italic: true)),
            TextRun(text: "both", style: RunStyle(bold: true, italic: true)),
            TextRun(text: " u", style: RunStyle(underline: true)),
            TextRun(text: " s", style: RunStyle(strikethrough: true)),
        ]
        #expect(RichTextCodec.runs(from: RichTextCodec.attributedString(from: runs)) == runs)
    }

    @Test func mergesAdjacentRunsWithTheSameStyle() {
        let runs = [TextRun(text: "a"), TextRun(text: "b")]
        #expect(RichTextCodec.runs(from: RichTextCodec.attributedString(from: runs)) == [TextRun(text: "ab")])
    }

    @Test func jsonOmitsFalseFlags() throws {
        let data = try JSONEncoder().encode(TextRun(text: "hi", style: RunStyle(bold: true)))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"bold\":true"))
        #expect(!json.contains("italic"))
        #expect(try JSONDecoder().decode(TextRun.self, from: data) == TextRun(text: "hi", style: RunStyle(bold: true)))
    }
}

@Suite struct NoteTests {
    private func note(_ text: String) -> Note {
        Note(number: 1, flavor: .ramen, content: [TextRun(text: text)], isOnScreen: false)
    }

    @Test func titleSkipsBlankLinesAndMarkers() {
        #expect(note("\n☐ buy milk\n• eggs").title == "buy milk")
        #expect(note("\n☐ buy milk\n\n• eggs").preview == "• eggs")
    }

    @Test func bareMarkersCountAsEmpty() {
        #expect(note("☐ \n• ").isEmpty)
        #expect(!note("☐ x").isEmpty)
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
        let note = Note(number: store.nextNumber, flavor: .laksa, content: [TextRun(text: "hi")], isOnScreen: true,
                        frame: CGRect(x: 10, y: 20, width: 260, height: 264))
        store.add(note)
        store.saveNow()

        let reloaded = NoteStore(directory: dir)
        #expect(reloaded.load() == true)
        #expect(reloaded.notes.count == 1)
        #expect(reloaded.notes.first?.content == note.content)
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
