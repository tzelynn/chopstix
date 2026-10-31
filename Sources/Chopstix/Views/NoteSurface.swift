import SwiftUI

/// A note's paper, garnish, editor and hover toolbar. Used both for sticky notes on the
/// screen and for editing in-app notes on the board.
struct NoteSurface: View {
    enum Context { case sticky, board }

    @Environment(AppModel.self) private var model
    let note: Note
    let context: Context
    var autofocus = false

    @State private var editor = EditorController()
    @State private var hovering = false

    /// Bottom garnishes sit just above the toolbar's space so they never collide.
    private static let garnishInset: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            surface(size: geometry.size)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.10), radius: 1, y: 0.5)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
    }

    private func surface(size: CGSize) -> some View {
        // The garnishes and toolbar make a footer the text stops above, rather than running under.
        let band = FlavorDecoration.bottomBand(for: note.flavor, size: size, bottomInset: Self.garnishInset)
        return ZStack(alignment: .topLeading) {
            NotePaper(flavor: note.flavor)
            FlavorDecoration(flavor: note.flavor, topInset: context == .sticky ? 40 : 26, bottomInset: Self.garnishInset)

            VStack(spacing: 0) {
                textEditor
                .overlay(alignment: .topLeading) {
                    if isBlank {
                        Text(note.kind == .markdown ? "jot something down… (/ for blocks)" : "jot something down…")
                            .font(Theme.rounded(NoteTextStyle.fontSize))
                            .foregroundStyle(Theme.ink.opacity(0.35))
                            .padding(.leading, 6)
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.top, context == .sticky ? StickyLayout.textTopPadding : 12)
                .padding(.horizontal, 8)
                .padding(.bottom, max(0, band + 6 - NoteToolbar.height))

                NoteToolbar(note: note, context: context, editor: editor)
                    .opacity(hovering || context == .board ? 1 : 0)
            }
        }
    }

    /// Sticky notes edit rich text; markdown notes edit markdown. Keyed by kind so converting a
    /// note swaps in the right editor.
    @ViewBuilder private var textEditor: some View {
        switch note.kind {
        case .sticky:
            RichTextEditor(initialContent: note.content, flavor: note.flavor, controller: editor, autofocus: autofocus) {
                model.setContent(note.id, $0)
            }
            .id(NoteKind.sticky)
        case .markdown:
            MarkdownEditor(initialText: note.markdown, theme: .sticky(note.flavor), controller: editor, autofocus: autofocus) {
                model.setMarkdown(note.id, $0)
            }
            .id(NoteKind.markdown)
        }
    }

    private var isBlank: Bool {
        note.kind == .markdown ? note.markdown.isEmpty : note.plainText.isEmpty
    }
}

/// Formatting buttons plus the note's menu. Fades in when hovering a sticky note.
struct NoteToolbar: View {
    static let height: CGFloat = 30

    @Environment(AppModel.self) private var model
    let note: Note
    let context: NoteSurface.Context
    let editor: EditorController

    var body: some View {
        HStack(spacing: 1) {
            switch note.kind {
            case .sticky:
                ForEach(FormatAction.allCases) { action in
                    ToolbarIcon(symbol: action.symbol, help: action.shortcutHint) { editor.perform(action) }
                    if action == .strikethrough { ToolbarDivider() }
                }
            case .markdown:
                // Kept short to fit the narrowest note; the rest are in the Format menu and `/` menu.
                ToolbarIcon(symbol: "textformat.size", help: "Heading  ⌥⌘1–3") { editor.perform(MarkdownAction.cycleHeading.selector) }
                ToolbarIcon(symbol: "bold", help: FormatAction.bold.shortcutHint) { editor.perform(.bold) }
                ToolbarDivider()
                ToolbarIcon(symbol: "list.bullet", help: FormatAction.bulletList.shortcutHint) { editor.perform(.bulletList) }
                ToolbarIcon(symbol: "checklist", help: "To-do  ⇧⌘L") { editor.perform(.checklist) }
            }
            Spacer(minLength: 2)
            if note.kind == .markdown {
                ToolbarIcon(symbol: "arrow.up.left.and.arrow.down.right", help: "Open as Page  ⌥⌘↩") { model.openPage(note.id) }
            }
            if context == .sticky {
                ToolbarIcon(symbol: "tray.and.arrow.down", help: "Return to Menu Board") { model.returnToBoard(note.id) }
            }
            Menu {
                NoteMenuItems(note: note, context: context)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink.opacity(0.7))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Flavour & more")
        }
        .padding(.leading, 8)
        .padding(.trailing, StickyLayout.foldSize + 4)
        .frame(height: Self.height)
    }
}

struct ToolbarDivider: View {
    var body: some View {
        Rectangle().fill(Theme.ink.opacity(0.15)).frame(width: 1, height: 12).padding(.horizontal, 3)
    }
}

struct ToolbarIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.ink.opacity(hovering ? 0.95 : 0.6))
                .frame(width: 21, height: 21)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.ink.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Menu entries shared by the note toolbar and board cards.
struct NoteMenuItems: View {
    @Environment(AppModel.self) private var model
    let note: Note
    let context: NoteSurface.Context
    var onDelete: () -> Void = {}

    var body: some View {
        FlavorPicker(note: note)

        Divider()

        switch note.kind {
        case .markdown:
            Button("Open as Page") { model.openPage(note.id) }
            Button("Save as Markdown…") { model.saveMarkdown(note.id) }
            Button("Export as PDF…") { model.exportPDF(note.id) }
        case .sticky:
            Button("Convert to Markdown Note…") { model.convertToMarkdown(note.id) }
        }

        Divider()

        if note.isOnScreen {
            Toggle("Always on Top", isOn: Binding(get: { note.alwaysOnTop }, set: { _ in model.toggleAlwaysOnTop(note.id) }))
            // Sticky notes have a dedicated toolbar button for this.
            if context == .board {
                Button("Return to Menu Board") { model.returnToBoard(note.id) }
            }
        } else {
            Button("Stick on Screen") { model.stickOnScreen(note.id) }
        }
        if context == .sticky {
            Button("Show Menu Board") { model.showBoard() }
        }

        Divider()

        Button("Delete Note…", role: .destructive) {
            if model.delete(note.id) { onDelete() }
        }
    }
}

struct FlavorPicker: View {
    @Environment(AppModel.self) private var model
    let note: Note

    var body: some View {
        Picker("Flavour", selection: Binding(get: { note.flavor }, set: { model.setFlavor(note.id, $0) })) {
            ForEach(Flavor.allCases) { flavor in
                Text("\(flavor.name)  \(flavor.nativeName)").tag(flavor)
            }
        }
    }
}
