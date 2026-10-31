import SwiftUI

/// SwiftUI wrapper around `MarkdownTextView`. Like `RichTextEditor`, the text is loaded once
/// from `initialText`; after that the text view owns it and reports changes through `onChange`.
struct MarkdownEditor: NSViewRepresentable {
    let initialText: String
    let theme: MarkdownTheme
    let controller: EditorController
    var autofocus = false
    var inset = NSSize(width: 4, height: 4)
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView.make(theme: theme)
        textView.delegate = context.coordinator
        textView.textContainerInset = inset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 2
        textView.markdown = initialText
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
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        controller.textView = textView
        textView.theme = theme
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
        applyFlavor(to: textView)
    }

    private func applyFlavor(to textView: NSTextView) {
        textView.selectedTextAttributes = [.backgroundColor: theme.flavor.nsAccentSoft.withAlphaComponent(0.55)]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }
    }
}
