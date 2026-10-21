import Foundation

// MARK: - Model

public struct ListItem: Equatable {
    public var ordered: Bool
    public var index: Int      // 1-based for ordered lists
    public var indent: Int     // 0-based nesting level
    public var task: TaskState?

    public init(ordered: Bool, index: Int = 1, indent: Int = 0, task: TaskState? = nil) {
        self.ordered = ordered
        self.index = index
        self.indent = indent
        self.task = task
    }
}

public enum TaskState: String, Equatable {
    case unchecked = "[ ]"
    case checked = "[x]"
}

public struct InlineNode {
    public enum Kind {
        case text, strong, em, strike, code, link, image, lineBreak
    }
    public var kind: Kind
    /// UTF-16 offsets into the source document.
    public var rawRange: Range<Int>
    public var children: [InlineNode]
    public var content: String
    public var url: String?

    public init(kind: Kind, rawRange: Range<Int>, children: [InlineNode] = [], content: String = "", url: String? = nil) {
        self.kind = kind
        self.rawRange = rawRange
        self.children = children
        self.content = content
        self.url = url
    }
}

public struct Block {
    public enum Kind: Equatable {
        case heading(Int)
        case paragraph
        case codeBlock(String?)
        case blockquote
        case listItem(ListItem)
        case thematicBreak
    }
    public var kind: Kind
    public var rawRange: Range<Int>
    /// Raw range of the visible content (marker excluded).
    public var contentRange: Range<Int>
    public var inlines: [InlineNode]
    public var codeLines: [(text: String, range: Range<Int>)]
    /// Raw range of the `[ ]` / `[x]` marker on a task list item.
    public var taskMarkerRange: Range<Int>?

    public init(kind: Kind, rawRange: Range<Int>, contentRange: Range<Int>, inlines: [InlineNode] = [], codeLines: [(String, Range<Int>)] = [], taskMarkerRange: Range<Int>? = nil) {
        self.kind = kind
        self.rawRange = rawRange
        self.contentRange = contentRange
        self.inlines = inlines
        self.codeLines = codeLines
        self.taskMarkerRange = taskMarkerRange
    }

    public var isParagraphLike: Bool {
        switch kind {
        case .paragraph, .heading, .blockquote, .listItem: return true
        case .codeBlock, .thematicBreak: return false
        }
    }

    /// Every raw offset covered by inline leaves — used by the editor to find the line of the caret.
    public var displayTextSourceOffsets: [Range<Int>] {
        switch kind {
        case .codeBlock:
            return codeLines.map { $0.range }
        default:
            var out: [Range<Int>] = []
            func walk(_ nodes: [InlineNode]) {
                for n in nodes {
                    switch n.kind {
                    case .text, .code: out.append(n.rawRange)
                    case .lineBreak: out.append(n.rawRange)
                    case .strong, .em, .strike: walk(n.children)
                    case .link: walk(n.children)
                    case .image: out.append(n.rawRange)
                    }
                }
            }
            walk(inlines)
            return out
        }
    }
}

// MARK: - Line index

public struct LineIndex {
    /// UTF-16 offset of the first character of each line.
    public let starts: [Int]
    public let length: Int
    private let ns: NSString

    public init(_ raw: String) {
        let ns = raw as NSString
        self.ns = ns
        var s: [Int] = [0]
        var i = 0
        while i < ns.length {
            if ns.character(at: i) == 0x0A { s.append(i + 1) }
            i += 1
        }
        starts = s
        length = ns.length
    }

    public var count: Int { starts.count }

    /// Raw range of line `index` excluding its trailing newline.
    public func range(ofLine index: Int) -> Range<Int> {
        guard index >= 0, index < starts.count else { return 0..<length }
        let start = starts[index]
        var end = (index + 1 < starts.count) ? starts[index + 1] - 1 : length
        if end > start, ns.character(at: end - 1) == 0x0D { end -= 1 }
        return start..<end
    }

    public func line(of offset: Int) -> Int {
        var lo = 0, hi = starts.count - 1, result = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if starts[mid] <= offset { result = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return result
    }
}

// MARK: - Parser

public enum MarkdownParser {

    /// Parses a whole markdown document into blocks with source offsets.
    public static func parse(_ raw: String) -> [Block] {
        let ns = raw as NSString
        let idx = LineIndex(raw)
        var blocks: [Block] = []
        var i = 0

        while i < idx.count {
            let range = idx.range(ofLine: i)
            let line = ns.substring(with: range)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let leadingWidth = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
            let unindented = ns.substring(with: (range.lowerBound + leadingWidth)..<range.upperBound)

            if trimmed.isEmpty { i += 1; continue }

            // fenced code block
            if let fence = fenceInfo(line) {
                let startLine = i
                var j = i + 1
                var lines: [(String, Range<Int>)] = []
                let contentStart = (j < idx.count) ? idx.starts[j] : idx.length
                var contentEnd = contentStart
                while j < idx.count {
                    let r = idx.range(ofLine: j)
                    let l = ns.substring(with: r)
                    if isClosingFence(l, fence: fence) { break }
                    lines.append((l, r))
                    contentEnd = idx.length >= maxRange(r) ? idx.length : maxRange(r)
                    j += 1
                }
                let rawEnd = (j < idx.count) ? maxRange(idx.range(ofLine: j)) : idx.length
                blocks.append(Block(
                    kind: .codeBlock(fence.language),
                    rawRange: range.lowerBound..<rawEnd,
                    contentRange: contentStart..<contentEnd,
                    codeLines: lines
                ))
                i = (j < idx.count) ? j + 1 : j
                _ = startLine
                continue
            }

            // thematic break
            if isThematicBreak(trimmed) {
                blocks.append(Block(kind: .thematicBreak, rawRange: range, contentRange: range))
                i += 1
                continue
            }

            // ATX heading
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                if hashes <= 6, unindented.dropFirst(hashes).first == " " {
                    var cr = range.lowerBound + leadingWidth + hashes
                    if cr < range.upperBound, ns.character(at: cr) == 0x20 { cr += 1 }
                    var end = range.upperBound
                    while end > cr, ns.character(at: end - 1) == 0x20 { end -= 1 }
                    // strip closing hashes
                    var trimmedEnd = end
                    while trimmedEnd > cr, ns.character(at: trimmedEnd - 1) == 0x23 { trimmedEnd -= 1 }
                    if trimmedEnd < end, trimmedEnd > cr, ns.character(at: trimmedEnd - 1) == 0x20 { end = trimmedEnd - 1 }
                    blocks.append(Block(
                        kind: .heading(hashes),
                        rawRange: range,
                        contentRange: cr..<end,
                        inlines: parseInline(ns, range: cr..<end, depth: 0)
                    ))
                    i += 1
                    continue
                }
            }

            // blockquote
            if trimmed.hasPrefix(">") {
                var cr = range.lowerBound + leadingWidth + 1
                if cr < range.upperBound, ns.character(at: cr) == 0x20 { cr += 1 }
                var end = range.upperBound
                while end > cr, ns.character(at: end - 1) == 0x20 { end -= 1 }
                blocks.append(Block(
                    kind: .blockquote,
                    rawRange: range,
                    contentRange: cr..<end,
                    inlines: parseInline(ns, range: cr..<end, depth: 0)
                ))
                i += 1
                continue
            }

            // list item
            if let li = parseListItem(ns, range: range) {
                var cr = range.lowerBound + li.indentWidth + li.markerWidth
                if li.item.task != nil {
                    cr = li.taskMarkerRange.upperBound
                    if cr < range.upperBound, ns.character(at: cr) == 0x20 { cr += 1 }
                } else if cr < range.upperBound, ns.character(at: cr) == 0x20 {
                    cr += 1
                }
                var end = range.upperBound
                while end > cr, ns.character(at: end - 1) == 0x20 { end -= 1 }
                if cr > end { cr = end }
                blocks.append(Block(
                    kind: .listItem(li.item),
                    rawRange: range,
                    contentRange: cr..<end,
                    inlines: parseInline(ns, range: cr..<end, depth: 0),
                    taskMarkerRange: li.item.task != nil ? li.taskMarkerRange : nil
                ))
                i += 1
                continue
            }

            // paragraph: consume following non-blank, non-block lines
            let startLine = i
            var endOffset = range.upperBound
            var j = i + 1
            while j < idx.count {
                let r = idx.range(ofLine: j)
                let l = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                if l.isEmpty { break }
                if l.hasPrefix("#") || l.hasPrefix(">") || fenceInfo(ns.substring(with: r)) != nil
                    || isThematicBreak(l) || parseListItem(ns, range: r) != nil { break }
                endOffset = r.upperBound
                j += 1
            }
            let contentRange = range.lowerBound..<endOffset
            var inlines: [InlineNode] = []
            var lineCursor = startLine
            while lineCursor < j {
                let r = idx.range(ofLine: lineCursor)
                var cr = r.lowerBound
                while cr < r.upperBound, ns.character(at: cr) == 0x20 || ns.character(at: cr) == 0x09 { cr += 1 }
                var ce = r.upperBound
                while ce > cr, ns.character(at: ce - 1) == 0x20 || ns.character(at: ce - 1) == 0x09 { ce -= 1 }
                inlines += parseInline(ns, range: cr..<ce, depth: 0)
                if lineCursor + 1 < j {
                    inlines.append(InlineNode(kind: .lineBreak, rawRange: r.upperBound..<min(r.upperBound + 1, idx.length)))
                }
                lineCursor += 1
            }
            blocks.append(Block(kind: .paragraph, rawRange: contentRange, contentRange: contentRange, inlines: inlines))
            i = j
        }
        return blocks
    }

    // MARK: block helpers

    private struct FenceInfo {
        var char: Character
        var count: Int
        var language: String?
    }

    private static func fenceInfo(_ line: String) -> FenceInfo? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first, first == "`" || first == "~" else { return nil }
        let count = t.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        let rest = String(t.dropFirst(count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if first == "`" && rest.contains("`") { return nil }
        let lang = rest.split(separator: " ").first.map(String.init)
        return FenceInfo(char: first, count: count, language: (lang?.isEmpty ?? true) ? nil : lang)
    }

    private static func isClosingFence(_ line: String, fence: FenceInfo) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first, first == fence.char else { return false }
        let count = t.prefix(while: { $0 == first }).count
        return count >= fence.count && t.dropFirst(count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let set = Set(trimmed)
        let c = trimmed.first!
        if c == "-" { return set == ["-"] || set == ["-", " "] }
        if c == "*" { return set == ["*"] || set == ["*", " "] }
        if c == "_" { return set == ["_"] || set == ["_", " "] }
        return false
    }

    private struct ParsedListItem {
        var item: ListItem
        var indentWidth: Int
        var markerWidth: Int
        var taskMarkerRange: Range<Int> = 0..<0
    }

    private static func parseListItem(_ ns: NSString, range: Range<Int>) -> ParsedListItem? {
        var i = range.lowerBound
        var indentWidth = 0
        var spaces = 0
        while i < range.upperBound {
            let c = ns.character(at: i)
            if c == 0x20 { spaces += 1; i += 1 }
            else if c == 0x09 { spaces += 4; i += 1 }
            else { break }
            if spaces >= 2 + 4 { break }
        }
        guard i < range.upperBound else { return nil }
        indentWidth = i - range.lowerBound
        let level = indentWidth / 2

        let c = ns.character(at: i)

        // task marker at line start
        if c == 0x5B { // [
            if i + 2 < range.upperBound {
                let a = ns.character(at: i + 1)
                let b = ns.character(at: i + 2)
                if a == 0x20 && b == 0x5D || (a == 0x78 || a == 0x58) && b == 0x5D {
                    let end = i + 3
                    if end == range.upperBound || ns.character(at: end) == 0x20 {
                        let ordered = false
                        return ParsedListItem(
                            item: ListItem(ordered: ordered, indent: level, task: a == 0x20 ? .unchecked : .checked),
                            indentWidth: indentWidth,
                            markerWidth: end - i,
                            taskMarkerRange: i..<end
                        )
                    }
                }
            }
        }

        // bullet
        if c == 0x2D || c == 0x2A || c == 0x2B { // - * +
            let next = i + 1
            if next < range.upperBound, ns.character(at: next) == 0x20 {
                // task list: bullet, space, then [ ] / [x]
                if let task = matchTaskMarker(ns, at: next + 1, limit: range.upperBound) {
                    return ParsedListItem(
                        item: ListItem(ordered: false, indent: level, task: task.state),
                        indentWidth: indentWidth,
                        markerWidth: task.markerRange.upperBound - i,
                        taskMarkerRange: task.markerRange
                    )
                }
                return ParsedListItem(
                    item: ListItem(ordered: false, indent: level, task: nil),
                    indentWidth: indentWidth,
                    markerWidth: next - i
                )
            }
            return nil
        }

        // ordered: digits then . or )
        if c >= 0x30 && c <= 0x39 {
            var j = i
            var digits = 0
            while j < range.upperBound, ns.character(at: j) >= 0x30, ns.character(at: j) <= 0x39 { j += 1; digits += 1 }
            if digits > 9 { return nil }
            if j < range.upperBound, ns.character(at: j) == 0x2E || ns.character(at: j) == 0x29 {
                let after = j + 1
                if after < range.upperBound, ns.character(at: after) == 0x20 {
                    let number = Int(ns.substring(with: i..<j)) ?? 1
                    if let task = matchTaskMarker(ns, at: after + 1, limit: range.upperBound) {
                        return ParsedListItem(
                            item: ListItem(ordered: true, index: number, indent: level, task: task.state),
                            indentWidth: indentWidth,
                            markerWidth: task.markerRange.upperBound - i,
                            taskMarkerRange: task.markerRange
                        )
                    }
                    return ParsedListItem(
                        item: ListItem(ordered: true, index: number, indent: level, task: nil),
                        indentWidth: indentWidth,
                        markerWidth: after - i
                    )
                }
            }
        }
        return nil
    }

    private struct TaskMarkerMatch {
        var state: TaskState
        var markerRange: Range<Int>
    }

    /// Matches `[ ]`, `[x]`, `[X]` or `[]` at `at`, requiring a space or end-of-line after the marker.
    private static func matchTaskMarker(_ ns: NSString, at: Int, limit: Int) -> TaskMarkerMatch? {
        guard at < limit, ns.character(at: at) == 0x5B else { return nil }
        var end = at
        if at + 1 < limit, ns.character(at: at + 1) == 0x5D {
            end = at + 2                     // []
            guard end == limit || ns.character(at: end) == 0x20 else { return nil }
            return TaskMarkerMatch(state: .unchecked, markerRange: at..<end)
        }
        guard at + 2 < limit, ns.character(at: at + 2) == 0x5D else { return nil }
        let middle = ns.character(at: at + 1)
        let state: TaskState?
        if middle == 0x20 { state = .unchecked }
        else if middle == 0x78 || middle == 0x58 { state = .checked }
        else { return nil }
        end = at + 3
        guard end == limit || ns.character(at: end) == 0x20 else { return nil }
        return TaskMarkerMatch(state: state!, markerRange: at..<end)
    }

    // MARK: inline parser

    private static let maxDepth = 6

    public static func parseInline(_ ns: NSString, range: Range<Int>, depth: Int) -> [InlineNode] {
        guard depth <= maxDepth, range.lowerBound < range.upperBound || range.lowerBound == range.upperBound else { return [] }
        var out: [InlineNode] = []
        var textStart: Int? = nil
        var i = range.lowerBound

        func flushText(upTo end: Int) {
            guard let s = textStart, s < end else { textStart = nil; return }
            out.append(InlineNode(kind: .text, rawRange: s..<end, content: ns.substring(with: s..<end)))
            textStart = nil
        }

        while i < range.upperBound {
            let c = ns.character(at: i)

            // hard line break inside paragraphs
            if c == 0x0A {
                flushText(upTo: i)
                out.append(InlineNode(kind: .lineBreak, rawRange: i..<min(i + 1, range.upperBound)))
                i += 1
                textStart = i
                continue
            }

            // escapes
            if c == 0x5C, i + 1 < range.upperBound {
                flushText(upTo: i)
                let next = ns.character(at: i + 1)
                if "*_[]()#`~!>-".unicodeScalars.contains(Unicode.Scalar(next)!) {
                    out.append(InlineNode(kind: .text, rawRange: i..<(i + 2), content: String(UnicodeScalar(next)!)))
                    i += 2
                    textStart = i
                    continue
                }
            }

            // code span
            if c == 0x60 {
                var j = i
                while j < range.upperBound, ns.character(at: j) == 0x60 { j += 1 }
                let fenceLen = j - i
                let close = ns.range(of: String(repeating: "`", count: fenceLen), options: [], range: NSRange(location: j, length: range.upperBound - j))
                if close.location != NSNotFound {
                    flushText(upTo: i)
                    let contentRange = j..<close.location
                    let content = ns.substring(with: contentRange)
                    out.append(InlineNode(kind: .code, rawRange: i..<maxRange(close), content: content))
                    i = maxRange(close)
                    textStart = i
                    continue
                }
            }

            // image
            if c == 0x21, i + 1 < range.upperBound, ns.character(at: i + 1) == 0x5B,
               let link = matchLink(ns, start: i + 1, limit: range.upperBound) {
                flushText(upTo: i)
                out.append(InlineNode(kind: .image, rawRange: i..<maxRange(link.urlRange),
                                     content: ns.substring(with: link.textRange), url: ns.substring(with: link.urlRange)))
                i = maxRange(link.urlRange)
                textStart = i
                continue
            }

            // link
            if c == 0x5B, let link = matchLink(ns, start: i, limit: range.upperBound) {
                flushText(upTo: i)
                let inner = parseInline(ns, range: link.textRange, depth: depth + 1)
                out.append(InlineNode(kind: .link, rawRange: i..<maxRange(link.urlRange),
                                     children: inner, url: ns.substring(with: link.urlRange)))
                i = maxRange(link.urlRange)
                textStart = i
                continue
            }

            // autolink <http://...>
            if c == 0x3C, let r = matchAutolink(ns, start: i, limit: range.upperBound) {
                flushText(upTo: i)
                out.append(InlineNode(kind: .link, rawRange: r, children: [InlineNode(kind: .text, rawRange: r, content: ns.substring(with: r))],
                                     url: ns.substring(with: r).trimmingCharacters(in: CharacterSet(charactersIn: "<>")))
                )
                i = maxRange(r)
                textStart = i
                continue
            }

            // bare url
            if c == 0x68 || c == 0x66, i == range.lowerBound || isBoundary(ns.character(at: i - 1)),
               let r = matchBareURL(ns, start: i, limit: range.upperBound) {
                flushText(upTo: i)
                let text = ns.substring(with: r)
                out.append(InlineNode(kind: .link, rawRange: r, children: [InlineNode(kind: .text, rawRange: r, content: text)], url: text))
                i = maxRange(r)
                textStart = i
                continue
            }

            // emphasis
            if let emph = matchEmphasis(ns, at: i, limit: range.upperBound, depth: depth) {
                flushText(upTo: i)
                out.append(emph)
                i = maxRange(emph.rawRange)
                textStart = i
                continue
            }

            if textStart == nil { textStart = i }
            i += 1
        }
        flushText(upTo: range.upperBound)
        return out
    }

    private static func isBoundary(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x28 || c == 0x5B || c == 0x0A
    }

    private struct LinkMatch {
        var textRange: Range<Int>
        var urlRange: Range<Int>
    }

    private static func matchLink(_ ns: NSString, start: Int, limit: Int) -> LinkMatch? {
        guard start < limit, ns.character(at: start) == 0x5B else { return nil }
        var i = start + 1
        var depth = 1
        while i < limit {
            let c = ns.character(at: i)
            if c == 0x5B { depth += 1 }
            if c == 0x5D {
                depth -= 1
                if depth == 0 { break }
            }
            i += 1
        }
        guard i < limit, ns.character(at: i) == 0x5D else { return nil }
        let textRange = (start + 1)..<i
        let j = i + 1
        guard j < limit, ns.character(at: j) == 0x28 else { return nil }
        var paren = 1
        var k = j + 1
        while k < limit {
            let c = ns.character(at: k)
            if c == 0x28 { paren += 1 }
            if c == 0x29 {
                paren -= 1
                if paren == 0 { break }
            }
            k += 1
        }
        guard k < limit, ns.character(at: k) == 0x29 else { return nil }
        let urlRange = (j + 1)..<k
        return LinkMatch(textRange: textRange, urlRange: urlRange)
    }

    private static func matchAutolink(_ ns: NSString, start: Int, limit: Int) -> Range<Int>? {
        guard start < limit, ns.character(at: start) == 0x3C else { return nil }
        var i = start + 1
        while i < limit {
            let c = ns.character(at: i)
            if c == 0x3E {
                let body = ns.substring(with: start + 1..<i)
                if body.hasPrefix("http://") || body.hasPrefix("https://") || body.hasPrefix("mailto:") { return start..<(i + 1) }
                return nil
            }
            if c == 0x0A || c == 0x20 { return nil }
            i += 1
        }
        return nil
    }

    private static func matchBareURL(_ ns: NSString, start: Int, limit: Int) -> Range<Int>? {
        let prefix = ns.substring(with: start..<min(start + 8, limit))
        guard prefix.hasPrefix("http://") || prefix.hasPrefix("https://") else { return nil }
        var i = start
        while i < limit {
            let c = ns.character(at: i)
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x29 || c == 0x5D { break }
            i += 1
        }
        // trim trailing punctuation
        while i > start, ".,;:!?".unicodeScalars.contains(Unicode.Scalar(ns.character(at: i - 1))!) { i -= 1 }
        return start..<i
    }

    private static func matchEmphasis(_ ns: NSString, at i: Int, limit: Int, depth: Int) -> InlineNode? {
        guard depth <= maxDepth, i < limit else { return nil }
        let c = ns.character(at: i)

        func strongish(_ marker: unichar) -> Range<Int>? {
            let m = String(UnicodeScalar(marker)!)
            var e = i + 2
            if e < limit, ns.character(at: e) == marker { e += 1 } // ***text*** → treat as strong+em
            guard e <= limit else { return nil }
            let search = NSRange(location: e, length: limit - e)
            let close = ns.range(of: m + m, options: [], range: search)
            guard close.location != NSNotFound, close.location > e else { return nil }
            return e..<close.location
        }

        if c == 0x7E { // ~~strike~~
            let inner = strongish(0x7E)
            if let inner, inner.lowerBound < inner.upperBound {
                return InlineNode(kind: .strike, rawRange: i..<maxRange(inner) + 2,
                                 children: parseInline(ns, range: inner, depth: depth + 1))
            }
            return nil
        }

        if c == 0x2A || c == 0x5F {
            let marker = c
            let isUnderscore = c == 0x5F
            let prev = i > 0 ? ns.character(at: i - 1) : 0x20
            // intra-word underscores stay literal (snake_case)
            if isUnderscore, isWordCharacter(prev) { return nil }

            let isDoubled = i + 1 < limit && ns.character(at: i + 1) == marker
            let searchStart = isDoubled ? i + 2 : i + 1
            let needle = String(repeating: String(UnicodeScalar(marker)!), count: isDoubled ? 2 : 1)
            let searchRange = NSRange(location: searchStart, length: max(0, limit - searchStart))
            let close = ns.range(of: needle, options: [], range: searchRange)
            guard close.location != NSNotFound, close.location > searchStart else { return nil }

            let after = close.location + close.length
            if isUnderscore, after < limit, isWordCharacter(ns.character(at: after)) { return nil }

            let inner = searchStart..<close.location
            let kind: InlineNode.Kind = isDoubled ? .strong : .em
            let children = parseInline(ns, range: inner, depth: depth + 1)
            if !isDoubled, after + 1 < limit, ns.character(at: after) == marker, ns.character(at: after + 1) == marker {
                // ***text*** → strong + emphasis
                return InlineNode(kind: .strong, rawRange: i..<(after + 2),
                                  children: [InlineNode(kind: .em, rawRange: i..<(after + 2), children: children)])
            }
            return InlineNode(kind: kind, rawRange: i..<after, children: children)
        }
        return nil
    }

    private static func isWordCharacter(_ c: unichar) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c > 0x7F
    }
}
