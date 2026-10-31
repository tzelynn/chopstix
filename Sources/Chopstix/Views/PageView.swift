import SwiftUI

/// A markdown note opened as a full page: the note's paper, held up by chopsticks, on the
/// menu board's cream — with room to write, and a stamp to save it as a file.
struct PageView: View {
    @Environment(AppModel.self) private var model
    let noteID: UUID
    @State private var editor = EditorController()

    var body: some View {
        if let note = model.store.note(noteID) {
            VStack(spacing: 0) {
                PageHeader(note: note, editor: editor)
                    .padding(.leading, 84) // clear of the traffic lights
                    .padding(.trailing, 20)
                    .frame(height: 54)
                    .background(WindowDragArea())

                PageSheet(note: note, editor: editor)
                    .padding(.horizontal, 26)

                PageFooter(note: note)
                    .padding(.horizontal, 40)
                    .frame(height: 36)
            }
            .background(MenuBackground())
        }
    }
}

enum PageLayout {
    /// Widest the paper gets, so lines stay readable in full screen.
    static let maxPaperWidth: CGFloat = 880
    /// Widest the text column gets.
    static let maxTextWidth: CGFloat = 660
    static let minTextInset: CGFloat = 46
    static let fold: CGFloat = 26
}

// MARK: - Header

private struct PageHeader: View {
    @Environment(AppModel.self) private var model
    let note: Note
    let editor: EditorController

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "No. %02d", note.number))
                    .font(Theme.serif(13).italic())
                    .foregroundStyle(Theme.inkSoft)
                Text(note.flavor.name)
                    .font(Theme.serif(17, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(note.flavor.nativeName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
            }
            .lineLimit(1)
            .fixedSize()

            Spacer(minLength: 12)

            PageFormatBar(editor: editor)

            ToolbarIcon(
                symbol: note.isOnScreen ? "arrow.down.right.and.arrow.up.left" : "macwindow.on.rectangle",
                help: note.isOnScreen ? "Back to Sticky Note" : "Stick on Screen"
            ) { model.shrinkToSticky(note.id) }

            Menu {
                FlavorPicker(note: note)
                Divider()
                Button("Delete Note…", role: .destructive) { model.delete(note.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink.opacity(0.7))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Flavour & more")

            SaveStamp(note: note)
        }
    }
}

/// Formatting buttons, grouped like the board's filter tabs.
private struct PageFormatBar: View {
    let editor: EditorController

    var body: some View {
        HStack(spacing: 1) {
            icon(MarkdownAction.cycleHeading.selector, "textformat.size", "Heading  ⌥⌘1–3")
            icon(FormatAction.bold)
            icon(FormatAction.italic)
            icon(FormatAction.strikethrough)
            icon(MarkdownAction.inlineCode)
            icon(MarkdownAction.link)
            ToolbarDivider()
            icon(FormatAction.bulletList)
            icon(MarkdownAction.numberedList)
            icon(FormatAction.checklist.selector, "checklist", "To-do  ⇧⌘L")
            icon(MarkdownAction.quote)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Capsule().fill(Theme.menuPaperDeep.opacity(0.7)))
        .overlay(Capsule().strokeBorder(Theme.menuRule.opacity(0.6), lineWidth: 1))
    }

    private func icon(_ action: FormatAction) -> some View {
        icon(action.selector, action.symbol, action.shortcutHint)
    }

    private func icon(_ action: MarkdownAction) -> some View {
        icon(action.selector, action.symbol, action.help)
    }

    private func icon(_ selector: Selector, _ symbol: String, _ help: String) -> some View {
        ToolbarIcon(symbol: symbol, help: help) { editor.perform(selector) }
    }
}

/// "save" — a stamp like the board's "order a note", with export options beside it.
private struct SaveStamp: View {
    @Environment(AppModel.self) private var model
    let note: Note
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button { model.saveMarkdown(note.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .bold))
                    Text("save")
                        .font(Theme.serif(14, .semibold))
                }
                .padding(.leading, 13)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(note.exportPath == nil ? "Save as a Markdown file (⌘S)" : "Save to \(fileName) (⌘S)")

            Rectangle().fill(Theme.menuStamp.opacity(0.35)).frame(width: 1, height: 16)

            Menu {
                Button("Save as Markdown…") { model.saveMarkdown(note.id, choosingLocation: true) }
                Button("Export as PDF…") { model.exportPDF(note.id) }
                if note.exportPath != nil {
                    Divider()
                    Button("Show in Finder") { model.revealExport(note.id) }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.leading, 7)
            .padding(.trailing, 11)
            .help("Save as… or export as PDF")
        }
        .foregroundStyle(Theme.menuStamp)
        .background(Capsule().fill(Theme.menuStamp.opacity(hovering ? 0.08 : 0.03)))
        .overlay(Capsule().strokeBorder(Theme.menuStamp.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, dash: [4, 2.5])))
        .onHover { hovering = $0 }
        .fixedSize()
    }

    private var fileName: String {
        note.exportPath.map { ($0 as NSString).lastPathComponent } ?? ""
    }
}

// MARK: - Paper

/// The note's paper, with its chopsticks and garnish, holding the editor.
private struct PageSheet: View {
    @Environment(AppModel.self) private var model
    let note: Note
    let editor: EditorController

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, PageLayout.maxPaperWidth)
            ZStack(alignment: .top) {
                ChopsticksView(layer: .back, lacquer: note.flavor.lacquer)

                ZStack {
                    NotePaper(flavor: note.flavor, fold: PageLayout.fold)
                    FlavorDecoration(flavor: note.flavor, topInset: 46, bottomInset: 10, scale: 1.3, scalesWithSize: false)
                        .opacity(0.85)
                    MarkdownEditor(
                        initialText: note.markdown,
                        theme: .page(note.flavor),
                        controller: editor,
                        autofocus: true,
                        inset: NSSize(width: max(PageLayout.minTextInset, (width - PageLayout.maxTextWidth) / 2), height: 16)
                    ) { model.setMarkdown(note.id, $0) }
                    .overlay(alignment: .topLeading) {
                        if note.markdown.isEmpty {
                            Text("start writing — type / for headings, lists & more")
                                .font(Theme.rounded(MarkdownTheme.page(note.flavor).baseSize))
                                .foregroundStyle(Theme.ink.opacity(0.35))
                                .padding(.leading, max(PageLayout.minTextInset, (width - PageLayout.maxTextWidth) / 2) + 2)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.top, 24)
                    // Stops above the garnishes, which make a footer the text never runs under.
                    .padding(.bottom, max(PageLayout.fold, FlavorDecoration.bottomBand(
                        for: note.flavor, size: geometry.size, bottomInset: 10, scale: 1.3, scalesWithSize: false) + 6))
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.10), radius: 1, y: 0.5)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                .padding(.top, StickyLayout.insets.top)

                ChopsticksView(layer: .front, lacquer: note.flavor.lacquer)
            }
            .frame(width: width)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Footer

private struct PageFooter: View {
    @Environment(AppModel.self) private var model
    let note: Note

    var body: some View {
        let words = MarkdownPlainText.wordCount(of: note.markdown)
        HStack {
            Text("\(words) \(words == 1 ? "word" : "words")  ·  \(max(1, Int((Double(words) / 230).rounded()))) min read")
            Spacer()
            saveStatus
        }
        .font(Theme.serif(12).italic())
        .foregroundStyle(Theme.inkFaint)
        .frame(maxWidth: PageLayout.maxPaperWidth - 28)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var saveStatus: some View {
        if let path = note.exportPath, let savedAt = note.exportedAt {
            let name = (path as NSString).lastPathComponent
            Button { model.revealExport(note.id) } label: {
                if note.updatedAt > savedAt.addingTimeInterval(1) {
                    Text("edited since saved to \(name)  ·  ⌘S to save again")
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text("saved to \(name)  ·  \(savedAt.formatted(.relative(presentation: .named)))")
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        } else {
            Text("not saved to a file yet  ·  ⌘S")
        }
    }
}
