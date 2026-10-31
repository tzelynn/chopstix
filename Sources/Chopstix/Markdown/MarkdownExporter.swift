import AppKit
import UniformTypeIdentifiers

/// Writes markdown notes out as `.md` files and PDFs.
enum MarkdownExporter {
    enum FileType {
        case markdown, pdf

        var contentType: UTType {
            switch self {
            case .markdown: UTType(filenameExtension: "md") ?? .plainText
            case .pdf: .pdf
            }
        }

        var verb: String { self == .markdown ? "Save" : "Export" }
    }

    /// A file name from the note's title, e.g. "Reading notes.md".
    static func suggestedName(for note: Note) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let title = note.title.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return title.isEmpty ? String(format: "Note %02d", note.number) : String(title.prefix(80))
    }

    /// Asks where to save, as a sheet on `window` if there is one.
    static func chooseLocation(for note: Note, type: FileType, window: NSWindow?, then save: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = type.verb
        panel.title = type == .markdown ? "Save as Markdown" : "Export as PDF"
        let existing = note.exportPath.map { URL(fileURLWithPath: $0) }
        panel.nameFieldStringValue = type == .markdown && existing != nil
            ? existing!.lastPathComponent
            : suggestedName(for: note) + (type == .markdown ? ".md" : ".pdf")
        if let folder = existing?.deletingLastPathComponent() { panel.directoryURL = folder }

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            save(url)
        }
        if let window {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            finish(panel.runModal())
        }
    }

    static func writeMarkdown(_ note: Note, to url: URL) throws {
        var text = note.markdown
        if !text.hasSuffix("\n") { text += "\n" }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Renders the note as the editor draws it (syntax hidden, drawn checkboxes, quote bars…)
    /// onto paginated pages. Returns whether the PDF was written.
    @discardableResult
    static func writePDF(_ note: Note, to url: URL) -> Bool {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 60
        info.bottomMargin = 60
        info.leftMargin = 64
        info.rightMargin = 64

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = MarkdownTextView.make(theme: .print(note.flavor))
        view.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.isEditable = false
        view.markdown = note.markdown
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.jobTitle = suggestedName(for: note)
        return operation.run()
    }

    static func present(_ error: Error, window: NSWindow?) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
