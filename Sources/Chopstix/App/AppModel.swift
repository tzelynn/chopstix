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

    // MARK: Editing

    func setContent(_ id: UUID, _ content: [TextRun]) {
        store.update(id) { $0.content = content }
    }

    func setFlavor(_ id: UUID, _ flavor: Flavor) {
        store.update(id) { $0.flavor = flavor }
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

    /// Board click: on-screen notes come forward; returns false if the note should be edited in the board.
    func revealIfOnScreen(_ id: UUID) -> Bool {
        guard store.note(id)?.isOnScreen == true else { return false }
        windows.bringToFront(id, focus: true)
        return true
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
        newNote(flavor: .matchaSoba, onScreen: false, content: [
            TextRun(text: "kept in the menu", style: b),
            TextRun(text: "\nnotes can live only on the board too — use “Stick on Screen” to bring one out."),
        ])
    }
}
