import SwiftUI

/// A borderless, transparent window holding one sticky note.
final class NoteWindow: NSWindow {
    let noteID: UUID
    var onClose: () -> Void = {}

    init(noteID: UUID, frame: NSRect) {
        self.noteID = noteID
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // drawn in SwiftUI so it follows the note's shape
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .aqua)
        acceptsMouseMovedEvents = true
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

/// Keeps one `NoteWindow` open for every note that is stuck on the screen.
final class NoteWindowManager: NSObject, NSWindowDelegate {
    private unowned let model: AppModel
    private var windows: [UUID: NoteWindow] = [:]

    init(model: AppModel) {
        self.model = model
    }

    /// Opens, closes and re-levels windows to match the store.
    func sync() {
        let notes = model.store.notes.filter(\.isOnScreen)
        let wanted = Set(notes.map(\.id))

        for (id, window) in windows where !wanted.contains(id) {
            window.delegate = nil
            window.orderOut(nil)
            window.close()
            windows[id] = nil
        }
        for note in notes {
            let window = windows[note.id] ?? open(note)
            window.level = note.alwaysOnTop ? .floating : .normal
        }
    }

    func bringToFront(_ id: UUID, focus: Bool) {
        guard let window = windows[id] else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if focus, let textView = window.contentView?.firstDescendant(ofType: NoteTextView.self) {
            window.makeFirstResponder(textView)
        }
    }

    private func open(_ note: Note) -> NoteWindow {
        let frame = note.frame.flatMap(onScreenFrame) ?? nextDefaultFrame()
        let window = NoteWindow(noteID: note.id, frame: frame)
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
}

extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(ofType: type) { return match }
        }
        return nil
    }
}
