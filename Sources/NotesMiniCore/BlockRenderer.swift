import AppKit
import Foundation

// MARK: - Theme

public struct RenderTheme: Equatable {
    public var fontSize: CGFloat
    public var isDark: Bool

    public init(fontSize: CGFloat = 14, isDark: Bool = false) {
        self.fontSize = fontSize
        self.isDark = isDark
    }

    public static func color(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    public var textColor: NSColor { .labelColor }
    public var secondaryColor: NSColor { .secondaryLabelColor }
    public var tertiaryColor: NSColor { .tertiaryLabelColor }
    public var linkColor: NSColor { RenderTheme.color(light: NSColor(srgbRed: 0.05, green: 0.35, blue: 0.85, alpha: 1),
                                             dark: NSColor(srgbRed: 0.35, green: 0.62, blue: 1.0, alpha: 1)) }
    public var codeBackground: NSColor { RenderTheme.color(light: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1),
                                                  dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09)) }
    public var inlineCodeBackground: NSColor { RenderTheme.color(light: NSColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1),
                                                        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13)) }
    public var quoteBarColor: NSColor { RenderTheme.color(light: NSColor(srgbRed: 0.76, green: 0.76, blue: 0.79, alpha: 1),
                                                          dark: NSColor(srgbRed: 0.44, green: 0.44, blue: 0.48, alpha: 1)) }

    public var baseFont: NSFont { .systemFont(ofSize: fontSize) }
    public var titleFont: NSFont { .systemFont(ofSize: fontSize * 1.5, weight: .semibold) }
    public var monoFont: NSFont { .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular) }
    public var monoBoldFont: NSFont { .monospacedSystemFont(ofSize: fontSize - 1, weight: .semibold) }

    public func headingFont(level: Int) -> NSFont {
        switch level {
        case 1: return .systemFont(ofSize: fontSize * 1.65, weight: .bold)
        case 2: return .systemFont(ofSize: fontSize * 1.34, weight: .semibold)
        case 3: return .systemFont(ofSize: fontSize * 1.14, weight: .semibold)
        default: return .systemFont(ofSize: fontSize, weight: .semibold)
        }
    }
}

extension NSFontDescriptor.SymbolicTraits {
    static let fontBold = NSFontDescriptor.SymbolicTraits(rawValue: 1 << 1)
    static let fontItalic = NSFontDescriptor.SymbolicTraits(rawValue: 1 << 0)
}

extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let merged = fontDescriptor.symbolicTraits.union(traits)
        let d = fontDescriptor.withSymbolicTraits(merged)
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}

// MARK: - Decorations & block info

public enum DecorationKind {
    case codeBlock
    case quoteBar
    case inlineCode
    case horizontalRule
}

public struct Decoration {
    public var kind: DecorationKind
    public var range: NSRange
    public init(kind: DecorationKind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

public struct BlockRenderInfo {
    public var kind: Block.Kind
    public var rawRange: Range<Int>
    public var displayRange: NSRange           // block including its trailing newline
    public var contentDisplayRange: NSRange    // block without the trailing newline
    public var listItem: ListItem?
}

// MARK: - Render result

public final class NoteRender {
    public let raw: String
    public let rawLength: Int
    public let display: NSAttributedString
    public let displayLength: Int
    /// display utf16 offset -> raw utf16 offset
    public let displayToRaw: [Int]
    /// raw utf16 offset -> display utf16 offset
    public let rawToDisplay: [Int]
    public let blocks: [BlockRenderInfo]
    public let decorations: [Decoration]
    public let theme: RenderTheme

    init(raw: String,
         display: NSAttributedString,
         displayToRaw: [Int],
         rawToDisplay: [Int],
         blocks: [BlockRenderInfo],
         decorations: [Decoration],
         theme: RenderTheme) {
        self.raw = raw
        self.rawLength = (raw as NSString).length
        self.display = display
        self.displayLength = display.length
        self.displayToRaw = displayToRaw
        self.rawToDisplay = rawToDisplay
        self.blocks = blocks
        self.decorations = decorations
        self.theme = theme
    }

    // MARK: mapping

    public func rawRange(forDisplayRange range: NSRange) -> NSRange {
        let loc = min(max(0, range.location), displayLength)
        let len = max(0, range.length)
        if len == 0 || loc >= displayLength { return NSRange(location: rawOffsetForCaret(loc), length: 0) }
        let end = min(displayLength, loc + len)
        let rStart = rawOffsetForCaret(loc)
        let rEnd = rawOffsetForCaret(end)
        return NSRange(location: rStart, length: max(0, rEnd - rStart))
    }

    public func displayRange(forRawRange range: NSRange) -> NSRange {
        let loc = min(max(0, range.location), rawLength)
        let end = min(rawLength, loc + max(0, range.length))
        let dLoc = displayOffsetForCaret(loc)
        let dEnd = displayOffsetForCaret(end)
        if dEnd <= dLoc { return NSRange(location: dLoc, length: 0) }
        return NSRange(location: dLoc, length: dEnd - dLoc)
    }

    /// Caret at a display boundary → raw offset. A caret sitting at the start of visible content
    /// maps *after* the hidden markers of that line, so typing there edits the content, not the marker.
    public func rawOffsetForCaret(_ displayOffset: Int) -> Int {
        if displayLength == 0 { return rawLength }
        if displayOffset >= displayLength { return rawLength }
        return displayToRaw[max(0, min(displayOffset, displayLength))]
    }

    public func displayOffsetForCaret(_ rawOffset: Int) -> Int {
        if rawOffset <= 0 { return 0 }
        if rawOffset >= rawLength { return displayLength }
        let v = rawToDisplay[min(rawOffset, rawLength)]
        return min(max(0, v), displayLength)
    }

    public func block(containingRawOffset offset: Int) -> BlockRenderInfo? {
        blocks.first { $0.rawRange.contains(offset) } ?? blocks.last { $0.rawRange.lowerBound <= offset }
    }

    public func block(containingDisplayOffset offset: Int) -> BlockRenderInfo? {
        blocks.first { NSLocationInRange(offset, $0.displayRange) }
    }
}

// MARK: - Renderer

public enum NoteRenderer {

    public static func render(_ raw: String, theme: RenderTheme = RenderTheme()) -> NoteRender {
        let blocks = MarkdownParser.parse(raw)
        let b = Builder(raw: raw, theme: theme)
        var infos: [BlockRenderInfo] = []
        var cursor = 0

        for block in blocks {
            if block.rawRange.lowerBound > cursor {
                b.emitBlankLines(from: cursor, to: block.rawRange.lowerBound)
            }
            b.beginBlock()
            switch block.kind {
            case .heading(let level): b.emitHeading(block, level: level)
            case .paragraph: b.emitInlines(block.inlines, base: infos.isEmpty ? b.titleAttrs : b.bodyAttrs)
            case .blockquote:
                b.emitInlines(block.inlines, base: b.quoteAttrs)
                // The `>` marker is hidden like every other marker, so the rule that makes a quote
                // readable has to be painted separately — nothing in the text expresses it.
                if b.displayLength > b.blockStart {
                    b.decorations.append(Decoration(
                        kind: .quoteBar,
                        range: NSRange(location: b.blockStart, length: b.displayLength - b.blockStart)))
                }
            case .listItem(let item): b.emitListItem(block, item: item)
            case .codeBlock: b.emitCodeBlock(block)
            case .thematicBreak: b.emitHorizontalRule(block)
            }
            let contentRange = NSRange(location: b.blockStart, length: max(0, b.blockContentEnd - b.blockStart))
            b.finishBlock(block)
            infos.append(BlockRenderInfo(
                kind: block.kind,
                rawRange: block.rawRange,
                displayRange: NSRange(location: b.blockStart, length: b.displayLength - b.blockStart),
                contentDisplayRange: contentRange,
                listItem: { if case .listItem(let i) = block.kind { return i } else { return nil } }()
            ))
            // finishBlock already emitted the newline that terminates this block's last line
            var blockEnd = block.rawRange.upperBound
            if blockEnd < (raw as NSString).length, (raw as NSString).character(at: blockEnd) == 0x0A { blockEnd += 1 }
            cursor = max(cursor, blockEnd)
        }
        if cursor < b.rawLength {
            b.emitBlankLines(from: cursor, to: b.rawLength)
        }

        b.normalizeRawToDisplay()
        let attributed = b.display

        return NoteRender(raw: raw,
                          display: attributed,
                          displayToRaw: b.displayToRaw,
                          rawToDisplay: b.rawToDisplay,
                          blocks: infos,
                          decorations: b.decorations,
                          theme: theme)
    }

    // MARK: builder

    final class Builder {
        /// Appending attributed fragments is amortised O(1). Mutating a finished string one run at
        /// a time (`addAttributes(_:range:)`) is quadratic in the number of runs, so we never do it.
        private(set) var out = NSMutableAttributedString()
        var displayToRaw: [Int] = []
        var rawToDisplay: [Int]
        var decorations: [Decoration] = []
        let rawLength: Int
        let ns: NSString
        let theme: RenderTheme

        var blockStart = 0
        var blockContentEnd = 0

        var displayLength: Int { out.length }

        var display: NSAttributedString { out }

        /// Immutable, shared per-document styles: identical instances let the text storage
        /// coalesce attribute runs instead of treating every paragraph as a new one.
        let bodyAttrs: [NSAttributedString.Key: Any]
        let titleAttrs: [NSAttributedString.Key: Any]
        let quoteAttrs: [NSAttributedString.Key: Any]
        let codeAttrs: [NSAttributedString.Key: Any]
        private var headingStyles: [Int: NSParagraphStyle] = [:]
        private var listStyles: [Int: NSParagraphStyle] = [:]

        init(raw: String, theme: RenderTheme) {
            self.ns = raw as NSString
            self.rawLength = ns.length
            self.rawToDisplay = [Int](repeating: -1, count: rawLength + 2)
            self.theme = theme

            let body = NSMutableParagraphStyle()
            body.lineSpacing = max(1, theme.fontSize * 0.22)
            body.paragraphSpacing = max(2, theme.fontSize * 0.28)

            let title = NSMutableParagraphStyle()
            title.lineSpacing = max(1, theme.fontSize * 0.12)
            title.paragraphSpacing = theme.fontSize * 0.28

            let quote = NSMutableParagraphStyle()
            quote.lineSpacing = max(1, theme.fontSize * 0.22)
            quote.paragraphSpacing = max(2, theme.fontSize * 0.2)
            quote.headIndent = theme.fontSize * 1.1
            quote.firstLineHeadIndent = theme.fontSize * 1.1

            let code = NSMutableParagraphStyle()
            code.lineSpacing = max(1, theme.fontSize * 0.16)
            code.paragraphSpacing = 0

            self.bodyAttrs = [.font: theme.baseFont, .foregroundColor: theme.textColor,
                              .paragraphStyle: body.copy() as! NSParagraphStyle]
            self.titleAttrs = [.font: theme.titleFont, .foregroundColor: theme.textColor,
                               .paragraphStyle: title.copy() as! NSParagraphStyle]
            self.quoteAttrs = [.font: theme.baseFont, .foregroundColor: theme.secondaryColor,
                               .paragraphStyle: quote.copy() as! NSParagraphStyle]
            self.codeAttrs = [.font: theme.monoFont, .foregroundColor: theme.textColor,
                              .paragraphStyle: code.copy() as! NSParagraphStyle]
        }

        /// raw offsets that produced no visible character (markers, trimmed spaces, fences)
        /// map to the display position they were dropped at — forward-fill keeps the
        /// mapping monotonic, which the editor relies on when the caret sits on a marker.
        func normalizeRawToDisplay() {
            var last = 0
            for i in 0..<rawToDisplay.count {
                if rawToDisplay[i] < 0 { rawToDisplay[i] = last } else { last = rawToDisplay[i] }
            }
        }

        // MARK: primitives

        /// Raw range that produces no visible output (hidden markers).
        func skip(_ range: Range<Int>) {
            let d = out.length
            for i in range where i >= 0 && i < rawLength {
                if rawToDisplay[i] < 0 { rawToDisplay[i] = d }
            }
        }

        func append(_ text: String, rawStart: Int, rawLen: Int, attrs: [NSAttributedString.Key: Any]) {
            let start = out.length
            let n = (text as NSString).length
            let span = max(0, min(rawLen, rawLength - max(0, rawStart)))
            if n == 0 {
                for i in rawStart..<(rawStart + span) where rawToDisplay[i] < 0 { rawToDisplay[i] = start }
                return
            }
            out.append(NSAttributedString(string: text, attributes: attrs))
            let lastRaw = max(0, rawStart + max(0, span - 1))
            while displayToRaw.count < start { displayToRaw.append(max(0, rawStart)) }
            for k in 0..<n {
                displayToRaw.append(max(0, min(rawStart + k, lastRaw)))
            }
            // raw offsets map one-to-one; trailing raw characters that produced no glyph
            // (trimmed spaces, repeated markers) map to the end of the run
            for j in 0..<span {
                let rawOff = rawStart + j
                if rawOff >= 0, rawOff < rawLength, rawToDisplay[rawOff] < 0 {
                    rawToDisplay[rawOff] = min(start + j, start + n)
                }
            }
        }

        /// Zero-content placeholder (task checkbox) mapped to a raw offset.
        func appendAttachment(_ attachment: NSTextAttachment, rawOffset: Int) {
            let start = out.length
            let placeholder = String(UnicodeScalar(NSTextAttachment.character)!)
            out.append(NSAttributedString(string: placeholder, attributes: [.attachment: attachment]))
            while displayToRaw.count < start { displayToRaw.append(rawOffset) }
            displayToRaw.append(max(0, min(rawOffset, max(0, rawLength - 1))))
            if rawOffset >= 0, rawOffset < rawLength, rawToDisplay[rawOffset] < 0 { rawToDisplay[rawOffset] = start }
        }

        func appendNewline(rawOffset: Int) {
            append("\n", rawStart: rawOffset, rawLen: 1, attrs: bodyAttrs)
        }

        func emitBlankLines(from: Int, to: Int) {
            guard to > from else { return }
            for i in from..<min(to, rawLength) where ns.character(at: i) == 0x0A {
                appendNewline(rawOffset: i)
            }
        }

        // MARK: blocks

        func beginBlock() {
            blockStart = out.length
            blockContentEnd = out.length
        }

        func endContent() { blockContentEnd = out.length }

        func finishBlock(_ block: Block) {
            endContent()
            if block.rawRange.upperBound < rawLength {
                appendNewline(rawOffset: block.rawRange.upperBound)
            }
        }

        func emitHeading(_ block: Block, level: Int) {
            skip(block.rawRange.lowerBound..<block.contentRange.lowerBound)
            let font = theme.headingFont(level: level)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.textColor, .paragraphStyle: headingStyle(level: level)]
            emitInlines(block.inlines, base: attrs, fontOverride: font)
            endContent()
        }

        func headingStyle(level: Int) -> NSParagraphStyle {
            if let cached = headingStyles[level] { return cached }
            let p = NSMutableParagraphStyle()
            let f = theme.headingFont(level: level)
            p.lineSpacing = max(0, f.pointSize * 0.10)
            p.paragraphSpacingBefore = (level <= 2 ? theme.fontSize * 0.85 : theme.fontSize * 0.55)
            p.paragraphSpacing = theme.fontSize * 0.2
            let style = p.copy() as! NSParagraphStyle
            headingStyles[level] = style
            return style
        }

        func emitCodeBlock(_ block: Block) {
            // The fence lines themselves are hidden, but each of them still owns a line break,
            // so the display keeps the same line numbering as the source.
            skip(block.rawRange.lowerBound..<block.contentRange.lowerBound)
            let fenceNewline = block.contentRange.lowerBound - 1
            if fenceNewline >= 0, fenceNewline < rawLength, ns.character(at: fenceNewline) == 0x0A {
                appendNewline(rawOffset: fenceNewline)
            }
            let attrs = codeAttrs
            var prevEnd = block.contentRange.lowerBound
            // The rounded slab is drawn around the code itself, not around the hidden fence
            // lines: including them made the top padding a whole line taller than the bottom.
            var slabStart = -1
            var slabEnd = -1
            for (text, range) in block.codeLines {
                if range.lowerBound > prevEnd {
                    for i in prevEnd..<min(range.lowerBound, rawLength) where ns.character(at: i) == 0x0A {
                        appendNewline(rawOffset: i)
                    }
                }
                if !text.isEmpty {
                    if slabStart < 0 { slabStart = out.length }
                    append(text, rawStart: range.lowerBound, rawLen: range.count, attrs: attrs)
                    slabEnd = out.length
                }
                prevEnd = range.upperBound
                if prevEnd < rawLength, ns.character(at: prevEnd) == 0x0A {
                    // The line's own break. A blank code line is nothing but this break, so it
                    // must not be emitted a second time — that is what double-spaced code looked
                    // like, one blank display line after every real one.
                    appendNewline(rawOffset: prevEnd)
                    prevEnd += 1
                } else if text.isEmpty, range.upperBound == range.lowerBound {
                    // A blank last line with no break of its own.
                    appendNewline(rawOffset: min(range.lowerBound, max(0, rawLength - 1)))
                }
            }
            // closing fence: no visible characters, its line break is emitted by finishBlock
            if block.rawRange.upperBound > prevEnd {
                skip(prevEnd..<block.rawRange.upperBound)
            }
            endContent()
            if slabStart >= 0, slabEnd > slabStart {
                decorations.append(Decoration(kind: .codeBlock,
                                              range: NSRange(location: slabStart, length: slabEnd - slabStart)))
            }
        }

        func emitHorizontalRule(_ block: Block) {
            skip(block.rawRange.lowerBound..<block.rawRange.upperBound)
            endContent()
            decorations.append(Decoration(kind: .horizontalRule, range: NSRange(location: blockStart, length: max(1, blockContentEnd - blockStart))))
        }

        func emitListItem(_ block: Block, item: ListItem) {
            skip(block.rawRange.lowerBound..<block.contentRange.lowerBound)
            let style = listStyle(item)
            let prefixAttrs: [NSAttributedString.Key: Any] = [.font: theme.baseFont, .foregroundColor: theme.secondaryColor, .paragraphStyle: style]
            var contentAttrs = bodyAttrs
            contentAttrs[.paragraphStyle] = style
            // Raycast fades a completed task so the remaining ones stand out at a glance.
            if item.task == .checked {
                contentAttrs[.foregroundColor] = theme.secondaryColor
            }

            if let task = item.task {
                let att = NSTextAttachment()
                att.image = CheckboxImages.image(checked: task == .checked, size: theme.fontSize)
                att.bounds = CGRect(x: 0, y: -1.5, width: theme.fontSize, height: theme.fontSize)
                appendAttachment(att, rawOffset: block.taskMarkerRange?.lowerBound ?? block.contentRange.lowerBound)
                append(" ", rawStart: block.contentRange.lowerBound, rawLen: 1, attrs: prefixAttrs)
            } else if item.ordered {
                append("\(item.index). ", rawStart: block.rawRange.lowerBound, rawLen: 1, attrs: prefixAttrs)
            } else {
                append("•  ", rawStart: block.rawRange.lowerBound, rawLen: 1, attrs: prefixAttrs)
            }
            emitInlines(block.inlines, base: contentAttrs)
            endContent()
        }

        func listStyle(_ item: ListItem) -> NSParagraphStyle {
            if let cached = listStyles[item.indent] { return cached }
            let p = NSMutableParagraphStyle()
            let step = theme.fontSize * 1.3 * CGFloat(item.indent + 1)
            p.headIndent = step
            p.firstLineHeadIndent = step - theme.fontSize * 1.15
            p.lineSpacing = max(1, theme.fontSize * 0.18)
            p.paragraphSpacing = max(1, theme.fontSize * 0.14)
            let style = p.copy() as! NSParagraphStyle
            listStyles[item.indent] = style
            return style
        }

        func emitInlines(_ nodes: [InlineNode], base: [NSAttributedString.Key: Any], fontOverride: NSFont? = nil) {
            for node in nodes {
                emitInline(node, attrs: base, fontOverride: fontOverride)
            }
        }

        func emitInline(_ node: InlineNode, attrs: [NSAttributedString.Key: Any], fontOverride: NSFont? = nil) {
            var a = attrs
            switch node.kind {
            case .text:
                guard !node.content.isEmpty else { return }
                append(node.content, rawStart: node.rawRange.lowerBound, rawLen: node.rawRange.count, attrs: a)
            case .strong:
                a[.font] = fontOverride?.withTraits(.fontBold) ?? font(from: a).withTraits(.fontBold)
                emitInlines(node.children, base: a, fontOverride: fontOverride)
            case .em:
                a[.font] = fontOverride?.withTraits(.fontItalic) ?? font(from: a).withTraits(.fontItalic)
                emitInlines(node.children, base: a, fontOverride: fontOverride)
            case .strike:
                a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                emitInlines(node.children, base: a, fontOverride: fontOverride)
            case .code:
                var ca = a
                ca[.font] = monoFont(from: a)
                let start = out.length
                let rawStart = min(node.rawRange.lowerBound + 1, max(0, rawLength - 1))
                let rawLen = max(1, node.rawRange.count - 2)
                append(node.content, rawStart: rawStart, rawLen: rawLen, attrs: ca)
                let end = out.length
                if end > start {
                    decorations.append(Decoration(kind: .inlineCode, range: NSRange(location: start, length: end - start)))
                }
            case .link:
                var la = a
                la[.foregroundColor] = theme.linkColor
                la[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let url = node.url, let u = URL(string: url) { la[NSAttributedString.Key.link] = u }
                if node.children.isEmpty, let url = node.url {
                    append(url, rawStart: node.rawRange.lowerBound, rawLen: node.rawRange.count, attrs: la)
                } else {
                    emitInlines(node.children, base: la, fontOverride: nil)
                }
            case .image:
                var ia = a
                ia[.foregroundColor] = theme.linkColor
                ia[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let url = node.url, let u = URL(string: url) { ia[NSAttributedString.Key.link] = u }
                let label = node.content.isEmpty ? "image" : node.content
                append("🖼 \(label)", rawStart: node.rawRange.lowerBound, rawLen: node.rawRange.count, attrs: ia)
            case .lineBreak:
                let off = node.rawRange.lowerBound
                if off < rawLength, ns.character(at: off) == 0x0A {
                    appendNewline(rawOffset: off)
                } else {
                    skip(off..<min(off + 1, rawLength))
                }
            }
        }

        func font(from attrs: [NSAttributedString.Key: Any]) -> NSFont {
            (attrs[.font] as? NSFont) ?? theme.baseFont
        }
        func monoFont(from attrs: [NSAttributedString.Key: Any]) -> NSFont {
            if font(from: attrs).fontDescriptor.symbolicTraits.contains(.fontBold) { return theme.monoBoldFont }
            return theme.monoFont
        }
    }
}

// MARK: - Checkbox images

public enum CheckboxImages {
    private static var cache: [String: NSImage] = [:] // main-thread only (UI)

    public static func image(checked: Bool, size: CGFloat) -> NSImage {
        let key = "\(checked)-\(Int(size))"
        if let c = cache[key] { return c }
        let s = max(12, size)
        let img = NSImage(size: CGSize(width: s, height: s), flipped: false) { _ in
            let box = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: s - 2, height: s - 2), xRadius: 3.5, yRadius: 3.5)
            if checked {
                NSColor.controlAccentColor.setFill()
                box.fill()
                NSColor.white.setStroke()
                let p = NSBezierPath()
                p.lineWidth = max(1.4, s * 0.12)
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.move(to: NSPoint(x: s * 0.28, y: s * 0.52))
                p.line(to: NSPoint(x: s * 0.43, y: s * 0.34))
                p.line(to: NSPoint(x: s * 0.73, y: s * 0.68))
                p.stroke()
            } else {
                // Raycast outlines an open task in the accent colour, which is what makes the
                // checkbox read as clickable rather than as a piece of punctuation.
                NSColor.controlAccentColor.setStroke()
                box.lineWidth = 1.4
                box.stroke()
            }
            return true
        }
        cache[key] = img
        return img
    }

    /// Raw range of the `[ ]` / `[x]` marker on a task line, given a raw offset inside that line.
    public static func taskMarkerRawRange(containingRawOffset offset: Int, raw: String) -> Range<Int>? {
        let idx = LineIndex(raw)
        let line = idx.range(ofLine: idx.line(of: offset))
        let lineText = (raw as NSString).substring(with: line)
        let ns = lineText as NSString
        for marker in ["[ ]", "[x]", "[X]"] {
            let r = ns.range(of: marker)
            if r.location != NSNotFound {
                return line.lowerBound + r.location..<line.lowerBound + r.location + r.length
            }
        }
        return nil
    }
}