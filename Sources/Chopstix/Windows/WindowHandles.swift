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

/// Resizes its window by dragging one of its edges or bottom corners, keeping the top edge pinned
/// (the top of a sticky note is reserved for moving it).
struct WindowResizeHandle: NSViewRepresentable {
    enum Position {
        case left, right, bottom, bottomLeft, bottomRight

        var movesLeft: Bool { self == .left || self == .bottomLeft }
        var movesRight: Bool { self == .right || self == .bottomRight }
        var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }

        var cursor: NSCursor {
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition = switch self {
                case .left: .left
                case .right: .right
                case .bottom: .bottom
                case .bottomLeft: .bottomLeft
                case .bottomRight: .bottomRight
                }
                return .frameResize(position: position, directions: .all)
            }
            return switch self {
            case .left, .right: .resizeLeftRight
            case .bottom: .resizeUpDown
            case .bottomLeft, .bottomRight: .crosshair
            }
        }
    }

    var position: Position = .bottomRight
    var minSize: CGSize

    final class HandleView: NSView {
        var position = Position.bottomRight
        var minSize = CGSize.zero
        private var startFrame = NSRect.zero
        private var startMouse = NSPoint.zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: position.cursor)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            startFrame = window.frame
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - startMouse.x
            let dy = mouse.y - startMouse.y

            var width = startFrame.width
            if position.movesRight { width += dx }
            if position.movesLeft { width -= dx }
            width = max(minSize.width, width)

            var height = startFrame.height
            if position.movesBottom { height -= dy }
            height = max(minSize.height, height)

            // Dragging the left edge pins the right edge instead of the left.
            let x = position.movesLeft ? startFrame.maxX - width : startFrame.minX
            // Screen coordinates grow upward, so pin the top edge by moving the origin down.
            let frame = NSRect(x: x, y: startFrame.maxY - height, width: width, height: height)
            window.setFrame(frame, display: true)
        }
    }

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.position = position
        view.minSize = minSize
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        if nsView.position != position {
            nsView.position = position
            nsView.window?.invalidateCursorRects(for: nsView)
        }
        nsView.minSize = minSize
    }
}
