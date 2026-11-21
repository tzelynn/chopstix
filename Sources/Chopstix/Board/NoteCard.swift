import SwiftUI

/// A note as it appears on the menu board: a little dish card.
struct NoteCard: View {
    @Environment(AppModel.self) private var model
    let note: Note
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "No. %02d", note.number))
                    .font(Theme.serif(11).italic())
                    .foregroundStyle(Theme.ink.opacity(0.5))
                Spacer()
                if note.isOnScreen {
                    HStack(spacing: 4) {
                        ChopsticksGlyph(color: Theme.ink.opacity(0.45)).frame(width: 10, height: 10)
                        Text("on screen")
                    }
                    .font(Theme.rounded(10, .medium))
                    .foregroundStyle(Theme.ink.opacity(0.5))
                }
            }

            Text(note.title.isEmpty ? "a blank note" : note.title)
                .font(Theme.rounded(14.5, .semibold))
                .foregroundStyle(note.title.isEmpty ? Theme.ink.opacity(0.4) : Theme.ink)
                .lineLimit(2)

            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(Theme.rounded(12))
                    .foregroundStyle(Theme.ink.opacity(0.65))
                    .lineSpacing(2)
                    .lineLimit(5)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, minHeight: 176, maxHeight: 176, alignment: .topLeading)
        .background {
            ZStack {
                NotePaper(flavor: note.flavor, fold: 14)
                FlavorDecoration(flavor: note.flavor, scale: 0.8, showsTopGarnish: false)
                    .mask(NoteShape(fold: 14))
                    .opacity(0.9)
                    .padding(.bottom, -4)
            }
            .shadow(color: .black.opacity(hovering ? 0.14 : 0.08), radius: hovering ? 10 : 5, y: hovering ? 6 : 3)
        }
        .overlay(alignment: .bottomTrailing) {
            if hovering { actions.padding(.trailing, 20).padding(.bottom, 8) }
        }
        .offset(y: hovering ? -2 : 0)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .onTapGesture(perform: open)
        .contextMenu {
            Button(openTitle) { open() }
            NoteMenuItems(note: note, context: .board)
        }
        .help(note.isOnScreen ? "Click to bring this note forward" : "Click to open as a page")
    }

    private var openTitle: String {
        note.isOnScreen ? "Show on Screen" : "Open as Page"
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if note.isOnScreen {
                ToolbarIcon(symbol: "tray.and.arrow.down", help: "Return to Menu Board") { model.returnToBoard(note.id) }
            } else {
                ToolbarIcon(symbol: "macwindow.on.rectangle", help: "Stick on Screen") { model.stickOnScreen(note.id) }
            }
            ToolbarIcon(symbol: "trash", help: "Delete Note") { model.delete(note.id) }
        }
        .padding(2)
        .background(Capsule().fill(note.flavor.paper.opacity(0.9)))
    }
}
