import AppKit
import Observation

/// The single place that changes notes. Keeps on-screen windows in step with the store.
@Observable
final class AppModel {
    let store: NoteStore
    @ObservationIgnored private(set) lazy var windows = NoteWindowManager(model: self)
    /// Installed by the app delegate; brings the menu board forward.
    @ObservationIgnored var showBoard: () -> Void = {}

    init(store: NoteStore = NoteStore()) {
        self.store = store
    }

    var notes: [Note] { store.notes }

    func bootstrap() {
        if !store.load() { seedWelcomeNotes() }
        windows.sync()
    }

    // MARK: Creating

    /// Flavours cycle so a fresh batch of notes isn't all one colour.
    private var nextFlavor: Flavor {
        store.notes.max(by: { $0.createdAt < $1.createdAt })?.flavor.next ?? .ramen
    }

    @discardableResult
    func newNote(flavor: Flavor? = nil, onScreen: Bool, content: [TextRun] = []) -> Note {
        let note = Note(number: store.nextNumber, flavor: flavor ?? nextFlavor, content: content, isOnScreen: onScreen)
        store.add(note)
        if onScreen {
            windows.sync()
            windows.bringToFront(note.id, focus: true)
        }
        return note
    }

    /// A new markdown note: stuck on the screen, or opened as a page if it lives in the board.
    @discardableResult
    func newMarkdownNote(flavor: Flavor? = nil, onScreen: Bool, markdown: String = "") -> Note {
        let note = Note(number: store.nextNumber, flavor: flavor ?? nextFlavor, kind: .markdown, markdown: markdown, isOnScreen: onScreen)
        store.add(note)
        if onScreen {
            windows.sync()
            windows.bringToFront(note.id, focus: true)
        } else {
            openPage(note.id)
        }
        return note
    }

    // MARK: Editing

    func setContent(_ id: UUID, _ content: [TextRun]) {
        store.update(id) { $0.content = content }
    }

    func setMarkdown(_ id: UUID, _ markdown: String) {
        store.update(id) { $0.markdown = markdown }
    }

    /// Turns a sticky note into a markdown note, after asking — there's no way back.
    func convertToMarkdown(_ id: UUID) {
        guard let note = store.note(id), note.kind == .sticky else { return }
        let alert = NSAlert()
        alert.messageText = "Turn “\(note.isEmpty ? "this note" : note.title)” into a markdown note?"
        alert.informativeText = "Bold, italic, strikethrough, bullets and checklists carry over; underlines don’t. Markdown notes can’t be turned back."
        alert.addButton(withTitle: "Convert")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.update(id) {
            $0.markdown = MarkdownConversion.markdown(from: $0.content)
            $0.content = []
            $0.kind = .markdown
        }
    }

    func setFlavor(_ id: UUID, _ flavor: Flavor) {
        store.update(id) { $0.flavor = flavor }
    }

    /// A flavour's menu description: the user's own if they've written one.
    func blurb(for flavor: Flavor) -> String {
        store.blurbs[flavor] ?? flavor.blurb
    }

    func setBlurb(_ flavor: Flavor, _ text: String?) {
        store.setBlurb(flavor, text)
    }

    /// The user's description of a flavour's section, if they've written one.
    func sectionDescription(for flavor: Flavor) -> String? {
        store.descriptions[flavor]
    }

    func setSectionDescription(_ flavor: Flavor, _ text: String?) {
        store.setDescription(flavor, text)
    }

    func setFrame(_ id: UUID, _ frame: CGRect) {
        store.update(id, touch: false) { $0.frame = frame }
    }

    func toggleAlwaysOnTop(_ id: UUID) {
        store.update(id, touch: false) { $0.alwaysOnTop.toggle() }
        windows.sync()
    }

    // MARK: Screen vs. board

    func stickOnScreen(_ id: UUID) {
        store.update(id, touch: false) { $0.isOnScreen = true }
        windows.sync()
        windows.bringToFront(id, focus: false)
    }

    func returnToBoard(_ id: UUID) {
        store.update(id, touch: false) { $0.isOnScreen = false }
        windows.sync()
    }

    /// A note the board should open in its editor sheet (consumed by `BoardView`).
    var requestedBoardEdit: UUID?

    func editOnBoard(_ id: UUID) {
        requestedBoardEdit = id
        showBoard()
    }

    /// Board click: an open page or on-screen note comes forward, and a markdown note in the
    /// board opens as a page. Returns false if the note should be edited in the board instead.
    func revealIfOnScreen(_ id: UUID) -> Bool {
        guard let note = store.note(id) else { return false }
        if windows.isPageOpen(id) || note.kind == .markdown && !note.isOnScreen {
            openPage(id)
        } else if note.isOnScreen {
            windows.bringToFront(id, focus: true)
        } else {
            return false
        }
        return true
    }

    // MARK: Pages

    /// Opens a markdown note as a full page. While it's open its sticky window steps aside.
    func openPage(_ id: UUID) {
        guard store.note(id)?.kind == .markdown else { return }
        windows.openPage(id)
    }

    /// Closes the page; an on-screen note goes back to being a sticky note.
    func closePage(_ id: UUID) {
        windows.closePage(id)
    }

    /// From a page: back to a sticky note on the screen.
    func shrinkToSticky(_ id: UUID) {
        store.update(id, touch: false) { $0.isOnScreen = true }
        windows.closePage(id)
        windows.bringToFront(id, focus: true)
    }

    // MARK: Saving & exporting

    /// Saves a markdown note as a `.md` file: to the file it was last saved to, unless
    /// `choosingLocation` (Save As) or it hasn't been saved before.
    func saveMarkdown(_ id: UUID, choosingLocation: Bool = false) {
        guard let note = store.note(id), note.kind == .markdown else { return }
        let window = windows.window(for: id)
        if !choosingLocation, let path = note.exportPath,
           FileManager.default.fileExists(atPath: (path as NSString).deletingLastPathComponent) {
            write(note, to: URL(fileURLWithPath: path), window: window)
            return
        }
        MarkdownExporter.chooseLocation(for: note, type: .markdown, window: window) { [weak self] url in
            self?.write(note, to: url, window: window)
        }
    }

    private func write(_ note: Note, to url: URL, window: NSWindow?) {
        // Save what's in the store now, not the copy captured before a save panel.
        guard let current = store.note(note.id) else { return }
        do {
            try MarkdownExporter.writeMarkdown(current, to: url)
            store.update(note.id, touch: false) {
                $0.exportPath = url.path
                $0.exportedAt = Date()
            }
        } catch {
            MarkdownExporter.present(error, window: window)
        }
    }

    func exportPDF(_ id: UUID) {
        guard let note = store.note(id), note.kind == .markdown else { return }
        let window = windows.window(for: id)
        MarkdownExporter.chooseLocation(for: note, type: .pdf, window: window) { [weak self] url in
            guard let current = self?.store.note(id) else { return }
            if !MarkdownExporter.writePDF(current, to: url) {
                MarkdownExporter.present(CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]), window: window)
            }
        }
    }

    func revealExport(_ id: UUID) {
        guard let path = store.note(id)?.exportPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: Deleting

    /// Deletes a note, asking first unless it's empty. Returns whether it was deleted.
    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard let note = store.note(id) else { return false }
        if !note.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Delete “\(note.title)”?"
            alert.informativeText = "This note will be cleared from the menu. This can’t be undone."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Keep")
            alert.buttons.first?.hasDestructiveAction = true
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        store.remove(id)
        windows.sync()
        return true
    }

    // MARK: First run

    private func seedWelcomeNotes() {
        let b = RunStyle(bold: true)
        newNote(flavor: .ramen, onScreen: true, content: [
            TextRun(text: "welcome to chopstix", style: b),
            TextRun(text: "\nyour notes are served fresh, held up by chopsticks.\n\n• drag the chopsticks to move me\n• drag my folded corner to resize\n• hover for the toolbar & flavours"),
        ])
        newNote(flavor: .prawnMee, onScreen: true, content: [
            TextRun(text: "today’s order", style: b),
            TextRun(text: "\n☑ open chopstix\n☐ try "),
            TextRun(text: "bold", style: b),
            TextRun(text: ", "),
            TextRun(text: "italic", style: RunStyle(italic: true)),
            TextRun(text: " & "),
            TextRun(text: "underline", style: RunStyle(underline: true)),
            TextRun(text: "\n☐ tick a box\n☐ find the menu board (⌘0)"),
        ])
        store.add(Note(number: store.nextNumber, flavor: .pho, kind: .markdown, markdown: Self.markdownWelcome, isOnScreen: false))
        newNote(flavor: .matchaSoba, onScreen: false, content: [
            TextRun(text: "kept in the menu", style: b),
            TextRun(text: "\nnotes can live only on the board too — use “Stick on Screen” to bring one out."),
        ])
    }

    static let markdownWelcome = """
    # a markdown note
    for longer notes — it renders as you type, and the **markdown** tucks away off the line you're on.

    - type `/` on an empty line for headings, lists, to-dos & more
    - [ ] tick me
    - ⌘-click links like https://commonmark.org
    > open me as a page (⤢) to write with more room, then **save** as `.md` or export a PDF
    """
}
