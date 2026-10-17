import AppKit
import NotesMiniCore

/// Draws everything that is decoration rather than text: code-block slabs, the quote bar,
/// inline-code chips and horizontal rules.
///
/// AppKit has no "hidden" attribute for attributed strings, so markdown markers are simply absent
/// from the display string; what remains that markdown would have expressed structurally has to
/// be painted here.
final class DecorationLayoutManager: NSLayoutManager {

    private var render: NoteRender?
    private var theme = RenderTheme()

    func update(render: NoteRender?, theme: RenderTheme) {
        self.render = render
        self.theme = theme
        invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0))
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let render, let container = textContainers.first else { return }
        let length = textStorage?.length ?? 0
        guard length > 0 else { return }

        // Decoration ranges live in character space; widen the query so a partially visible
        // slab still paints (its rounded top/bottom must not pop in while scrolling).
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let lower = max(0, visible.location - 1)
        let upper = min(length, max(lower, NSMaxRange(visible) + 1))
        let padded = NSRange(location: lower, length: upper - lower)

        for decoration in render.decorations {
            let clamped = NSIntersectionRange(decoration.range, NSRange(location: 0, length: length))
            guard clamped.length > 0, NSIntersectionRange(clamped, padded).length > 0 else { continue }
            switch decoration.kind {
            case .codeBlock: drawCodeBlock(clamped, container: container, origin: origin)
            case .quoteBar: drawQuoteBar(clamped, container: container, origin: origin)
            case .inlineCode: drawInlineCode(clamped, container: container, origin: origin)
            case .horizontalRule: drawRule(clamped, container: container, origin: origin)
            }
        }
    }

    // MARK: shapes

    private func rect(for range: NSRange, container: NSTextContainer) -> NSRect? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = boundingRect(forGlyphRange: glyphs, in: container)
        guard !rect.isNull, !rect.isEmpty else { return nil }
        return rect
    }

    private func drawCodeBlock(_ range: NSRange, container: NSTextContainer, origin: NSPoint) {
        guard let base = rect(for: range, container: container) else { return }
        let box = base.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -8, dy: -7)
        theme.codeBackground.setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
    }

    private func drawInlineCode(_ range: NSRange, container: NSTextContainer, origin: NSPoint) {
        guard let base = rect(for: range, container: container) else { return }
        let box = base.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -1.5, dy: -1)
        theme.inlineCodeBackground.setFill()
        NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5).fill()
    }

    private func drawQuoteBar(_ range: NSRange, container: NSTextContainer, origin: NSPoint) {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        // `usedRect` is where the glyphs actually start, which is what the rule has to sit beside;
        // the full line fragment rect starts at the container edge and would put the rule in the
        // page margin instead.
        enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, _, _, _ in
            let bar = NSRect(x: usedRect.minX + origin.x - 9,
                             y: usedRect.minY + origin.y + 2,
                             width: 3,
                             height: max(2, usedRect.height - 4))
            self.theme.quoteBarColor.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    private func drawRule(_ range: NSRange, container: NSTextContainer, origin: NSPoint) {
        guard let base = rect(for: range, container: container) else { return }
        let box = base.offsetBy(dx: origin.x, dy: origin.y)
        let y = box.midY.rounded() + 0.5
        theme.quoteBarColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: box.minX, y: y))
        path.line(to: NSPoint(x: box.maxX, y: y))
        path.stroke()
    }
}
