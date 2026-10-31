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
                    .overlay { resizeHandles }
                    .padding(StickyLayout.insets)

                WindowDragArea()
                    .frame(height: StickyLayout.dragStripHeight)
                    .padding(.horizontal, StickyLayout.insets.leading)

                ChopsticksView(layer: .front, lacquer: note.flavor.lacquer)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Edge and bottom-corner resize handles. The top edge is left to the drag strip
    /// (which sits above these in the ZStack), so it keeps moving the note.
    private var resizeHandles: some View {
        let edge = StickyLayout.resizeEdgeThickness
        let corner = StickyLayout.foldSize + 4
        let min = StickyLayout.minSize
        return ZStack {
            WindowResizeHandle(position: .left, minSize: min)
                .frame(width: edge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            WindowResizeHandle(position: .right, minSize: min)
                .frame(width: edge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            WindowResizeHandle(position: .bottom, minSize: min)
                .frame(height: edge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            WindowResizeHandle(position: .bottomLeft, minSize: min)
                .frame(width: corner, height: corner)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            WindowResizeHandle(position: .bottomRight, minSize: min)
                .frame(width: corner, height: corner)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}
