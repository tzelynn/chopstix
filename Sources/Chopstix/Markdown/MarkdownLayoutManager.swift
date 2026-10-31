import AppKit

/// Lays out styled markdown: hides syntax (`.cxHidden`) except on the lines being edited, and
/// draws the `.cxDecoration` shapes — bullets, checkboxes, quote bars, code blocks and rules.
///
/// Hidden characters are laid out as zero-width control characters: they stay in the text (so
/// nothing about editing, undo or saving changes) but take up no space and aren't drawn. Unlike
/// null glyphs, they keep their place on their own line. The line with the caret is always
/// revealed, so the caret never has to step over characters it can't see.
final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var theme: MarkdownTheme

    /// Characters whose syntax is shown — the paragraphs holding the selection. `nil` hides all syntax.
    private(set) var revealed: NSRange?

    init(theme: MarkdownTheme) {
        self.theme = theme
        super.init()
        delegate = self
        allowsNonContiguousLayout = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setRevealed(_ range: NSRange?) {
        guard range != revealed else { return }
        let old = revealed
        revealed = range
        guard let length = textStorage?.length else { return }
        for r in [old, range].compactMap({ $0 }) {
            let clamped = NSIntersectionRange(r, NSRange(location: 0, length: length))
            guard clamped.length > 0 || r.location <= length else { continue }
            invalidateGlyphs(forCharacterRange: clamped, changeInLength: 0, actualCharacterRange: nil)
            invalidateLayout(forCharacterRange: clamped, actualCharacterRange: nil)
        }
        for container in textContainers { container.textView?.needsDisplay = true }
    }

    private func isRevealed(_ index: Int) -> Bool {
        guard let revealed else { return false }
        return index >= revealed.location && index < NSMaxRange(revealed)
    }

    // MARK: Collapsing hidden code fences

    /// A hidden ``` line would otherwise leave a blank, clickable line at the top and bottom of
    /// its code block (and typing there lands on the fence). Squash it down to a little padding.
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard let storage = textStorage, isHiddenFence(characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil), in: storage) else { return false }
        let height = (theme.baseSize * 0.45).rounded()
        lineFragmentRect.pointee.size.height = height
        lineFragmentUsedRect.pointee.size.height = height
        baselineOffset.pointee = min(baselineOffset.pointee, height)
        return true
    }

    private func isHiddenFence(_ characters: NSRange, in storage: NSTextStorage) -> Bool {
        let string = storage.string as NSString
        var content = characters
        while content.length > 0, CharacterSet.newlines.contains(Unicode.Scalar(string.character(at: NSMaxRange(content) - 1)) ?? " ") {
            content.length -= 1
        }
        guard content.length > 0, !isRevealed(content.location),
              (storage.attribute(.cxDecoration, at: content.location, effectiveRange: nil) as? Int) == MarkdownDecoration.codeBlock.rawValue,
              string.substring(with: content).trimmingCharacters(in: .whitespaces).hasPrefix("```") else { return false }
        var hidden = NSRange()
        return storage.attribute(.cxHidden, at: content.location, longestEffectiveRange: &hidden, in: content) != nil
            && NSMaxRange(hidden) >= NSMaxRange(content)
    }

    // MARK: Hiding syntax

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = textStorage else { return 0 }
        var modified: [NSLayoutManager.GlyphProperty]?
        for i in 0..<glyphRange.length {
            let index = charIndexes[i]
            guard index < storage.length, storage.attribute(.cxHidden, at: index, effectiveRange: nil) != nil,
                  !isRevealed(index) else { continue }
            if modified == nil { modified = Array(UnsafeBufferPointer(start: props, count: glyphRange.length)) }
            modified![i] = .controlCharacter
        }
        guard let modified else { return 0 } // 0 = use the glyphs as generated
        modified.withUnsafeBufferPointer {
            setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = textStorage, charIndex < storage.length,
              storage.attribute(.cxHidden, at: charIndex, effectiveRange: nil) != nil, !isRevealed(charIndex) else { return action }
        return .zeroAdvancement
    }

    // MARK: Decorations

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let all = NSRange(location: 0, length: storage.length)

        var drawn = Set<Int>()
        storage.enumerateAttribute(.cxDecoration, in: characters) { value, range, _ in
            guard let raw = value as? Int, let decoration = MarkdownDecoration(rawValue: raw) else { return }
            // Blocks are drawn whole, even if only part of them is being redrawn.
            var full = range
            storage.attribute(.cxDecoration, at: range.location, longestEffectiveRange: &full, in: all)
            guard drawn.insert(full.location).inserted else { return }
            NSGraphicsContext.saveGraphicsState()
            draw(decoration, characters: full, in: container, at: origin)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func draw(_ decoration: MarkdownDecoration, characters: NSRange, in container: NSTextContainer, at origin: NSPoint) {
        let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let padding = container.lineFragmentPadding
        let size = theme.baseSize

        switch decoration {
        case .codeBlock:
            guard let block = lineFragmentsRect(glyphs)?.offsetBy(dx: origin.x, dy: origin.y) else { return }
            let rect = NSRect(x: block.minX + padding, y: block.minY, width: block.width - 2 * padding, height: block.height)
            theme.codeBackground.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        case .quote:
            // Spans the text itself, not the spacing after it.
            guard let block = lineFragmentsRect(glyphs, used: true)?.offsetBy(dx: origin.x, dy: origin.y) else { return }
            let bar = NSRect(x: origin.x + padding + 1, y: block.minY + 1, width: 3, height: block.height - 2)
            theme.markerColor.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()

        case .rule:
            guard !isRevealed(characters.location) else { return }
            enumerateLineFragments(forGlyphRange: glyphs) { rect, used, _, _, _ in
                let y = (origin.y + used.midY).rounded() + 0.5
                let path = NSBezierPath()
                path.move(to: NSPoint(x: origin.x + rect.minX + padding, y: y))
                path.line(to: NSPoint(x: origin.x + rect.maxX - padding, y: y))
                path.lineWidth = 1
                self.theme.ruleColor.setStroke()
                path.stroke()
            }

        case .bullet, .nestedBullet:
            guard let (rect, baseline, font) = glyphBox(glyphs.location, character: characters.location, origin: origin) else { return }
            let d = (size * 0.34).rounded()
            let dot = NSRect(x: rect.midX - d / 2, y: baseline - font.xHeight / 2 - d / 2, width: d, height: d)
            theme.markerColor.setFill()
            theme.markerColor.setStroke()
            if decoration == .bullet {
                NSBezierPath(ovalIn: dot).fill()
            } else {
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.6, dy: 0.6))
                ring.lineWidth = 1.2
                ring.stroke()
            }

        case .task, .taskDone:
            // The box is drawn over the `[ ]` characters, which are left in place but invisible.
            guard let (start, baseline, font) = glyphBox(glyphs.location, character: characters.location, origin: origin) else { return }
            let side = theme.checkboxSide(for: font)
            let rect = NSRect(x: start.minX, y: baseline - font.capHeight / 2 - side / 2, width: side, height: side)
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), xRadius: side * 0.26, yRadius: side * 0.26)
            if decoration == .taskDone {
                theme.markerColor.setFill()
                shape.fill()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: rect.minX + side * 0.26, y: rect.midY + side * 0.02))
                tick.line(to: NSPoint(x: rect.minX + side * 0.43, y: rect.maxY - side * 0.28))
                tick.line(to: NSPoint(x: rect.maxX - side * 0.24, y: rect.minY + side * 0.3))
                tick.lineWidth = max(1.4, side * 0.12)
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                NSColor.white.withAlphaComponent(0.45).setFill()
                shape.fill()
                shape.lineWidth = 1.2
                theme.markerColor.setStroke()
                shape.stroke()
            }
        }
    }

    /// The union of the line fragments holding `glyphs` (or just their used parts), in container coordinates.
    private func lineFragmentsRect(_ glyphs: NSRange, used: Bool = false) -> NSRect? {
        var union: NSRect?
        enumerateLineFragments(forGlyphRange: glyphs) { rect, usedRect, _, _, _ in
            let r = used ? usedRect : rect
            union = union.map { $0.union(r) } ?? r
        }
        return union
    }

    /// A glyph's rect and its line's baseline (in view coordinates), and the font it's set in.
    private func glyphBox(_ glyph: Int, character: Int, origin: NSPoint) -> (NSRect, CGFloat, NSFont)? {
        guard let container = textContainers.first, let storage = textStorage, character < storage.length,
              let font = storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont else { return nil }
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let rect = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).offsetBy(dx: origin.x, dy: origin.y)
        let baseline = origin.y + fragment.minY + location(forGlyphAt: glyph).y
        return (rect, baseline, font)
    }
}
