import SwiftUI

/// Root view of an on-screen note window: the note held up by a pair of chopsticks.
struct StickyNoteView: View {
    @Environment(AppModel.self) private var model
    let noteID: UUID
    var autofocus = false

    var body: some View {
        if let note = model.store.note(noteID) {
            ZStack(alignment: .top) {
                ChopsticksView(layer: .back, lacquer: note.flavor.lacquer)

                NoteSurface(note: note, context: .sticky, autofocus: autofocus)
                    .overlay(alignment: .bottomTrailing) {
                        WindowResizeHandle(minSize: StickyLayout.minSize)
                            .frame(width: StickyLayout.foldSize + 4, height: StickyLayout.foldSize + 4)
                    }
                    .padding(StickyLayout.insets)

                WindowDragArea()
                    .frame(height: StickyLayout.dragStripHeight)
                    .padding(.horizontal, StickyLayout.insets.leading)

                ChopsticksView(layer: .front, lacquer: note.flavor.lacquer)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
