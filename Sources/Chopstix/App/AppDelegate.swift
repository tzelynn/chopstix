import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var boardWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIcon.image(size: 512)
        NSApp.mainMenu = MainMenu.build(target: self)
        installStatusItem()

        model.showBoard = { [weak self] in self?.showBoard(nil) }
        model.bootstrap()
        showBoard(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !(boardWindow?.isVisible ?? false) { showBoard(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        model.store.saveNow()
    }

    // MARK: Actions

    @objc func newStickyNote(_ sender: Any?) {
        model.newNote(onScreen: true)
    }

    @objc func newMarkdownNote(_ sender: Any?) {
        model.newMarkdownNote(onScreen: true)
    }

    @objc func newMenuNote(_ sender: Any?) {
        model.editOnBoard(model.newNote(onScreen: false).id)
    }

    @objc func showBoard(_ sender: Any?) {
        let window = boardWindow ?? makeBoardWindow()
        boardWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeBoardWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "chopstix"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(hex: 0xFBF6EC)
        window.minSize = NSSize(width: 600, height: 480)
        window.contentView = NSHostingView(rootView: BoardView().environment(model))
        window.center()
        window.setFrameAutosaveName("ChopstixBoard")
        return window
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = AppIcon.statusBarImage()
        item.button?.toolTip = "chopstix"
        let menu = NSMenu()
        menu.addItem(withTitle: "New Sticky Note", action: #selector(newStickyNote(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Markdown Note", action: #selector(newMarkdownNote(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show Menu Board", action: #selector(showBoard(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit chopstix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        statusItem = item
    }
}
