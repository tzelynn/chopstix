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

    var body: some View {
        ZStack(alignment: .topLeading) {
            NotePaper(flavor: note.flavor)
            // Bottom garnishes sit just above the toolbar's space so they never collide.
            FlavorDecoration(flavor: note.flavor, topInset: context == .sticky ? 40 : 26, bottomInset: 24)

            VStack(spacing: 0) {
                RichTextEditor(
                    initialContent: note.content,
                    flavor: note.flavor,
                    controller: editor,
                    autofocus: autofocus
                ) { model.setContent(note.id, $0) }
                .overlay(alignment: .topLeading) {
                    if note.plainText.isEmpty {
                        Text("jot something down…")
                            .font(Theme.rounded(NoteTextStyle.fontSize))
                            .foregroundStyle(Theme.ink.opacity(0.35))
                            .padding(.leading, 6)
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.top, context == .sticky ? StickyLayout.textTopPadding : 12)
                .padding(.horizontal, 8)

                NoteToolbar(note: note, context: context, editor: editor)
                    .opacity(hovering || context == .board ? 1 : 0)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.10), radius: 1, y: 0.5)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
    }
}

/// Formatting buttons plus the note's menu. Fades in when hovering a sticky note.
struct NoteToolbar: View {
    let note: Note
    let context: NoteSurface.Context
    let editor: EditorController

    var body: some View {
        HStack(spacing: 1) {
            ForEach(FormatAction.allCases) { action in
                ToolbarIcon(symbol: action.symbol, help: action.shortcutHint) { editor.perform(action) }
                if action == .strikethrough {
                    Rectangle().fill(Theme.ink.opacity(0.15)).frame(width: 1, height: 12).padding(.horizontal, 3)
                }
            }
            Spacer(minLength: 2)
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
        .frame(height: 30)
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
        Picker("Flavour", selection: Binding(get: { note.flavor }, set: { model.setFlavor(note.id, $0) })) {
            ForEach(Flavor.allCases) { flavor in
                Text("\(flavor.name)  \(flavor.nativeName)").tag(flavor)
            }
        }

        Divider()

        if note.isOnScreen {
            Toggle("Always on Top", isOn: Binding(get: { note.alwaysOnTop }, set: { _ in model.toggleAlwaysOnTop(note.id) }))
            Button("Return to Menu Board") { model.returnToBoard(note.id) }
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
