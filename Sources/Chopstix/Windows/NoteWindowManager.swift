import SwiftUI

/// A window showing one note. Answers the File menu's save and export commands for markdown notes.
class NoteHostWindow: NSWindow {
    let noteID: UUID
    weak var model: AppModel?

    init(noteID: UUID, model: AppModel, frame: NSRect, styleMask: NSWindow.StyleMask) {
        self.noteID = noteID
        self.model = model
        super.init(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua)
        acceptsMouseMovedEvents = true
    }

    @objc func saveDocument(_ sender: Any?) { model?.saveMarkdown(noteID) }
    @objc func saveDocumentAs(_ sender: Any?) { model?.saveMarkdown(noteID, choosingLocation: true) }
    @objc func cxExportPDF(_ sender: Any?) { model?.exportPDF(noteID) }
    @objc func cxOpenAsPage(_ sender: Any?) { model?.openPage(noteID) }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)), #selector(cxExportPDF(_:)), #selector(cxOpenAsPage(_:)):
            return model?.store.note(noteID)?.kind == .markdown
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}

/// A borderless, transparent window holding one sticky note.
final class NoteWindow: NoteHostWindow {
    var onClose: () -> Void = {}

    init(noteID: UUID, model: AppModel, frame: NSRect) {
        super.init(noteID: noteID, model: model, frame: frame, styleMask: [.borderless])
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // drawn in SwiftUI so it follows the note's shape
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// ⌘W puts the note back on the menu board — closing never deletes.
    override func performClose(_ sender: Any?) { onClose() }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performClose(_:)) { return true }
        return super.validateMenuItem(menuItem)
    }
}

/// A markdown note opened as a full page: an ordinary window that can go full screen.
final class PageWindow: NoteHostWindow {
    static let minSize = NSSize(width: 640, height: 420)

    init(noteID: UUID, model: AppModel) {
        super.init(noteID: noteID, model: model, frame: NSRect(x: 0, y: 0, width: 860, height: 760),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        backgroundColor = NSColor(hex: 0xFBF6EC)
        minSize = Self.minSize
        collectionBehavior = [.fullScreenPrimary]
        tabbingMode = .disallowed
    }

    /// Already a page, so there's nothing to open.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(cxOpenAsPage(_:)) { return false }
        return super.validateMenuItem(menuItem)
    }
}

/// Keeps one `NoteWindow` open for every note stuck on the screen, and a `PageWindow` for every
/// note opened as a page. A note with an open page has no sticky window, so it is only ever
/// edited in one place.
final class NoteWindowManager: NSObject, NSWindowDelegate {
    private unowned let model: AppModel
    private var windows: [UUID: NoteWindow] = [:]
    private var pages: [UUID: PageWindow] = [:]

    init(model: AppModel) {
        self.model = model
    }

    /// Opens, closes and re-levels windows to match the store.
    func sync() {
        for (id, page) in pages where model.store.note(id)?.kind != .markdown {
            close(page)
            pages[id] = nil
        }

        let notes = model.store.notes.filter { $0.isOnScreen && pages[$0.id] == nil }
        let wanted = Set(notes.map(\.id))
        for (id, window) in windows where !wanted.contains(id) {
            close(window)
            windows[id] = nil
        }
        for note in notes {
            let window = windows[note.id] ?? open(note)
            window.level = note.alwaysOnTop ? .floating : .normal
        }
    }

    func bringToFront(_ id: UUID, focus: Bool) {
        guard let window = pages[id] ?? windows[id] else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if focus, let textView = window.contentView?.firstDescendant(ofType: NSTextView.self) {
            window.makeFirstResponder(textView)
        }
    }

    /// The window a note is showing in, if any.
    func window(for id: UUID) -> NSWindow? { pages[id] ?? windows[id] }

    func isPageOpen(_ id: UUID) -> Bool { pages[id] != nil }

    // MARK: Pages

    func openPage(_ id: UUID) {
        if pages[id] == nil {
            let page = PageWindow(noteID: id, model: model)
            page.contentView = NSHostingView(rootView: PageView(noteID: id).environment(model))
            page.delegate = self
            // Open over the sticky note it grew from, else where the last page was.
            if let sticky = windows[id] {
                page.setFrameTopLeftPoint(NSPoint(x: sticky.frame.minX, y: sticky.frame.maxY))
                page.constrainToScreen()
            } else if !page.setFrameUsingName("ChopstixPage") {
                page.center()
            }
            page.setFrameAutosaveName("ChopstixPage")
            pages[id] = page
            sync() // the sticky window steps aside
        }
        bringToFront(id, focus: true)
    }

    func closePage(_ id: UUID) {
        guard let page = pages.removeValue(forKey: id) else { return }
        close(page)
        sync() // an on-screen note comes back as a sticky note
    }

    // MARK: Sticky windows

    private func open(_ note: Note) -> NoteWindow {
        let frame = note.frame.flatMap(onScreenFrame) ?? nextDefaultFrame()
        let window = NoteWindow(noteID: note.id, model: model, frame: frame)
        let hosting = NSHostingView(rootView: StickyNoteView(noteID: note.id).environment(model))
        hosting.sizingOptions = [] // the window owns its size; SwiftUI just fills it
        window.contentView = hosting
        window.delegate = self
        window.onClose = { [weak model] in model?.returnToBoard(note.id) }
        window.orderFront(nil)
        windows[note.id] = window
        if note.frame != frame { model.setFrame(note.id, frame) }
        return window
    }

    private func close(_ window: NSWindow) {
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    /// The saved frame, if it is still (mostly) on a connected screen.
    private func onScreenFrame(_ frame: CGRect) -> CGRect? {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersection(frame).width > 60 && $0.visibleFrame.intersection(frame).height > 60 }
        return visible ? frame : nil
    }

    /// New notes cascade down from the upper right of the screen under the mouse.
    private func nextDefaultFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = StickyLayout.defaultSize
        let step = CGFloat(windows.count % 8) * 26
        return CGRect(
            x: screen.maxX - size.width - 80 - step,
            y: screen.maxY - size.height - 60 - step,
            width: size.width,
            height: size.height
        )
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { persistFrame(notification) }
    func windowDidResize(_ notification: Notification) { persistFrame(notification) }

    private func persistFrame(_ notification: Notification) {
        guard let window = notification.object as? NoteWindow else { return }
        model.setFrame(window.noteID, window.frame)
    }

    /// The page's close button (or ⌘W) closes the page through the model, so the sticky note returns.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let page = sender as? PageWindow else { return true }
        model.closePage(page.noteID)
        return false
    }
}

private extension NSWindow {
    func constrainToScreen() {
        guard let screen = screen ?? NSScreen.main else { return }
        setFrame(constrainFrameRect(frame, to: screen), display: false)
    }
}

extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(ofType: type) { return match }
        }
        return nil
    }
}
