import SwiftUI

/// Renders the app's views to PNG files for design review (`--snapshot <dir>`), and exports
/// the app icon set (`--export-icon <dir>.iconset`). Uses a throwaway store; real notes are untouched.
@MainActor
enum Snapshots {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = sampleModel()

        for note in model.notes where note.isOnScreen {
            let view = StickyNoteView(noteID: note.id).environment(model)
            let name = note.kind == .markdown ? "markdown" : note.flavor.rawValue
            let size = note.kind == .markdown ? CGSize(width: 300, height: 360) : StickyLayout.defaultSize
            write(view, size: size, to: directory.appendingPathComponent("note-\(name).png"))
        }
        if let page = model.notes.first(where: { $0.kind == .markdown && !$0.isOnScreen }) {
            write(PageView(noteID: page.id).environment(model), size: CGSize(width: 900, height: 820),
                  to: directory.appendingPathComponent("page.png"))
            MarkdownExporter.writePDF(page, to: directory.appendingPathComponent("page.pdf"))
        }
        if let note = model.notes.first(where: { !$0.isOnScreen }) {
            let sheet = NoteEditorSheet(noteID: note.id) {}.environment(model)
            write(sheet, size: CGSize(width: 440, height: 480), to: directory.appendingPathComponent("editor-sheet.png"))
        }
        write(BoardView().environment(model), size: CGSize(width: 900, height: 1500), to: directory.appendingPathComponent("board.png"))
        write(AppIconView(), size: CGSize(width: 512, height: 512), to: directory.appendingPathComponent("icon.png"))
        print("snapshots written to \(directory.path)")
    }

    static func exportIconset(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 1 ? "" : "@2x"
                let px = CGFloat(base * scale)
                let renderer = ImageRenderer(content: AppIconView().frame(width: px, height: px))
                renderer.scale = 1
                guard let cg = renderer.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
            }
        }
    }

    /// Renders through a real (off-screen) window so AppKit-backed views like the text editor draw too.
    private static func write<V: View>(_ view: V, size: CGSize, to url: URL) {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.appearance = NSAppearance(named: .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    private static func sampleModel() -> AppModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chopstix-snapshots-\(UUID().uuidString)")
        let model = AppModel(store: NoteStore(directory: dir))
        let bold = RunStyle(bold: true)
        let samples: [(Flavor, [TextRun])] = [
            (.prawnMee, [TextRun(text: "groceries", style: bold), TextRun(text: "\n☑ prawns\n☐ yellow noodles\n☐ kangkong\n☐ sambal")]),
            (.ramen, [TextRun(text: "thursday", style: bold), TextRun(text: "\n• standup at 10\n• "), TextRun(text: "send deck", style: RunStyle(underline: true)), TextRun(text: " to mei\n• gym")]),
            (.matchaSoba, [TextRun(text: "remember to "), TextRun(text: "breathe", style: RunStyle(italic: true)), TextRun(text: " 🌿")]),
            (.laksa, [TextRun(text: "ideas", style: bold), TextRun(text: "\nhot pot night with the team?\n"), TextRun(text: "too spicy", style: RunStyle(strikethrough: true)), TextRun(text: " just right")]),
            (.pho, [TextRun(text: "reading list", style: bold), TextRun(text: "\n☐ the remains of the day\n☑ pachinko\n☐ klara and the sun")]),
            (.japchae, [TextRun(text: "birthday", style: bold), TextRun(text: "\nmum — 14 nov\nbook the korean place")]),
            (.udon, [TextRun(text: "slow sunday", style: bold), TextRun(text: "\n• laundry\n• call grandma\n• nap")]),
        ]
        for (flavor, content) in samples {
            model.store.add(Note(number: model.store.nextNumber, flavor: flavor, content: content, isOnScreen: true))
        }
        model.store.add(Note(number: model.store.nextNumber, flavor: .ramen,
                             content: [TextRun(text: "someday", style: bold), TextRun(text: "\n☐ learn to hand-pull noodles\n☐ visit sapporo")],
                             isOnScreen: false))
        model.store.add(Note(number: model.store.nextNumber, flavor: .prawnMee, content: [], isOnScreen: false))
        model.store.add(Note(number: model.store.nextNumber, flavor: .pho, kind: .markdown, markdown: """
            ## article notes
            **hand-pulled** noodles need ==rested== dough, says [the piece](https://example.com)
            - [x] read part one
            - [ ] try the `2:1` ratio
            - fold, pull, repeat
                - every pull *doubles* the strands
            > the noodle remembers every pull
            """, isOnScreen: true))
        model.store.add(Note(number: model.store.nextNumber, flavor: .japchae, kind: .markdown, markdown: """
            # reading: the art of noodles
            notes from [the article](https://example.com/noodles) — **hand-pulled** vs ==knife-cut==, and why *resting* matters.

            ## key ideas
            - dough rests for *at least* 30 minutes so the gluten relaxes
            - stretching lines the gluten strands up
                - fold, pull, repeat — each pull doubles the strands
            - alkaline water (`kansui`) gives ramen its spring

            ## to try
            1. knead until smooth
            2. rest, covered
            3. pull ~~eight~~ seven times

            - [x] read part one
            - [ ] try the 2:1 flour-to-water ratio
            - [ ] find a lamian place nearby

            > the noodle remembers every pull

            ---
            ```
            water = flour * 0.5
            salt  = flour * 0.01
            ```
            """, isOnScreen: false))
        model.setSectionDescription(.ramen, "the week ahead — meetings, errands, and the odd someday")
        return model
    }
}
