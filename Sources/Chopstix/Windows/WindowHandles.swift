import SwiftUI

/// A transparent strip that moves its window when dragged.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.makeKeyAndOrderFront(nil)
            window?.performDrag(with: event)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

/// Resizes its window from the bottom-right corner, keeping the top-left corner pinned.
struct WindowResizeHandle: NSViewRepresentable {
    var minSize: CGSize

    final class HandleView: NSView {
        var minSize = CGSize.zero
        private var startFrame = NSRect.zero
        private var startMouse = NSPoint.zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            if #available(macOS 15.0, *) {
                addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
            } else {
                addCursorRect(bounds, cursor: .crosshair)
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            startFrame = window.frame
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            let width = max(minSize.width, startFrame.width + (mouse.x - startMouse.x))
            let height = max(minSize.height, startFrame.height - (mouse.y - startMouse.y))
            // Screen coordinates grow upward, so pin the top edge by moving the origin down.
            let frame = NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height)
            window.setFrame(frame, display: true)
        }
    }

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.minSize = minSize
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.minSize = minSize
    }
}
