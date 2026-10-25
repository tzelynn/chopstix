import SwiftUI

/// Lets SwiftUI controls (the note toolbar) drive a specific note's text view.
final class EditorController {
    fileprivate(set) weak var textView: NoteTextView?

    func perform(_ action: FormatAction) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.perform(action)
    }

    func focus(selectingEnd: Bool = true) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        if selectingEnd { textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0)) }
    }
}

/// SwiftUI wrapper around `NoteTextView`. The text is loaded once from `initialContent`;
/// after that the text view owns it and reports every change through `onChange`.
struct RichTextEditor: NSViewRepresentable {
    let initialContent: [TextRun]
    let flavor: Flavor
    let controller: EditorController
    var autofocus = false
    let onChange: ([TextRun]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.drawsBackground = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.insertionPointColor = NoteTextStyle.ink
        textView.typingAttributes = NoteTextStyle.baseAttributes
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 2
        textView.textStorage?.setAttributedString(RichTextCodec.attributedString(from: initialContent))
        applyFlavor(to: textView)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView

        controller.textView = textView
        if autofocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        if let textView = scrollView.documentView as? NoteTextView {
            controller.textView = textView
            applyFlavor(to: textView)
        }
    }

    private func applyFlavor(to textView: NSTextView) {
        textView.selectedTextAttributes = [.backgroundColor: flavor.nsAccentSoft.withAlphaComponent(0.55)]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: ([TextRun]) -> Void

        init(onChange: @escaping ([TextRun]) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let storage = textView.textStorage else { return }
            onChange(RichTextCodec.runs(from: storage))
        }
    }
}
