import Foundation

/// Pure text transformations behind the toolbar, keyboard shortcuts and markdown input rules.
/// Everything here works on raw markdown (the source of truth), never on the rendered text.
public enum EditorCommands {

    public enum BlockKind: Equatable {
        case heading1, heading2, heading3, heading4
        case codeBlock, blockquote
        case orderedList, bulletList, taskList
        case none
    }

    // MARK: inline

    /// Wraps or unwraps `selection` in `marker` (`**`, `*`, `~~`, `_`, `` ` ``).
    /// An empty selection inserts a pair and leaves the caret between the markers.
    public static func toggleInlineMarkers(_ raw: String, selection: NSRange, marker: String) -> String {
        let ns = raw as NSString
        let loc = max(0, min(selection.location, ns.length))
        let len = max(0, min(selection.length, ns.length - loc))
        let m = marker as NSString

        // already wrapped from both sides?
        let sel = NSRange(location: loc, length: len)
        let beforeStart = loc - m.length
        if len > 0, beforeStart >= 0, NSMaxRange(sel) + m.length <= ns.length {
            let before = ns.substring(with: NSRange(location: beforeStart, length: m.length))
            let after = ns.substring(with: NSRange(location: NSMaxRange(sel), length: m.length))
            if before == marker && after == marker {
                let inner = ns.substring(with: sel)
                return (ns.substring(to: beforeStart) + inner + ns.substring(from: NSMaxRange(sel) + m.length))
            }
        }
        let inner = ns.substring(with: sel)
        return ns.substring(to: loc) + marker + inner + marker + ns.substring(from: loc + len)
    }

    /// Toggle <u>…</u> around the selection. Markdown has no underline, so it is stored as inline HTML.
    public static func toggleUnderline(_ raw: String, selection: NSRange) -> String {
        toggleInlineMarkers(raw, selection: selection, marker: "<u>")
    }

    public static func insertLink(_ raw: String, selection: NSRange, url: String) -> String {
        let ns = raw as NSString
        let loc = max(0, min(selection.location, ns.length))
        let len = max(0, min(selection.length, ns.length - loc))
        let text = ns.substring(with: NSRange(location: loc, length: len))
        let label = text.isEmpty ? url : text
        let insertion = "[\(label)](\(url))"
        return ns.substring(to: loc) + insertion + ns.substring(from: loc + len)
    }

    // MARK: block

    /// Applies (or removes, when already active) a block marker to a range of lines.
    public static func applyBlock(_ raw: String, lineIndexes: Range<Int>, kind: BlockKind) -> String {
        let ns = raw as NSString
        let idx = LineIndex(raw)
        let first = max(0, min(lineIndexes.lowerBound, idx.count - 1))
        let last = max(first, min(lineIndexes.upperBound - 1, idx.count - 1))

        if kind == .codeBlock {
            return toggleCodeBlock(raw: raw, firstLine: first, lastLine: last)
        }

        var lines: [String] = []
        for i in first...last {
            lines.append(ns.substring(with: idx.range(ofLine: i)))
        }
        let allSame = lines.allSatisfy { detectKind($0) == kind }
        var out: [String] = []
        var orderedCounter = 1
        for (offset, line) in lines.enumerated() {
            let stripped = stripMarker(line)
            if allSame {
                out.append(stripped)
                continue
            }
            switch kind {
            case .heading1: out.append("# " + stripped)
            case .heading2: out.append("## " + stripped)
            case .heading3: out.append("### " + stripped)
            case .heading4: out.append("#### " + stripped)
            case .blockquote: out.append("> " + stripped)
            case .bulletList: out.append("- " + stripped)
            case .taskList: out.append("- [ ] " + stripped)
            case .orderedList: out.append("\(offset + 1). " + stripped)
            case .codeBlock: break
            case .none: out.append(stripped)
            }
            orderedCounter += 1
        }
        _ = orderedCounter

        // splice back
        let start = idx.range(ofLine: first).lowerBound
        let end = idx.range(ofLine: last).upperBound
        return (ns.substring(to: start) + out.joined(separator: "\n") + ns.substring(from: end))
    }

    public static func applyBlock(_ raw: String, lineIndex: Int, kind: BlockKind) -> String {
        applyBlock(raw, lineIndexes: lineIndex..<(lineIndex + 1), kind: kind)
    }

    public static func detectKind(_ line: String) -> BlockKind? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") {
            let n = t.prefix(while: { $0 == "#" }).count
            switch n {
            case 1: return .heading1
            case 2: return .heading2
            case 3: return .heading3
            case 4...: return .heading4
            default: break
            }
        }
        if t.hasPrefix("```") || t.hasPrefix("~~~") { return .codeBlock }
        if t.hasPrefix(">") { return .blockquote }
        if hasTaskMarker(t) { return .taskList }
        if isBullet(t) { return .bulletList }
        if isOrdered(t) { return .orderedList }
        return nil
    }

    private static func hasTaskMarker(_ t: String) -> Bool {
        t.contains("[ ]") || t.range(of: "\\[[xX]\\]", options: .regularExpression) != nil
    }
    private static func isBullet(_ t: String) -> Bool {
        ["- ", "* ", "+ "].contains { t.hasPrefix($0) }
    }
    private static func isOrdered(_ t: String) -> Bool {
        guard let first = t.first, first.isNumber else { return false }
        return t.contains(") ") || t.range(of: "^\\d+\\. ", options: .regularExpression) != nil
    }

    /// Removes any leading block marker and indentation.
    public static func stripMarker(_ line: String) -> String {
        var t = line.trimmingCharacters(in: .whitespaces)
        while t.hasPrefix("#") { t.removeFirst() }
        if t.hasPrefix(">") { t.removeFirst() }
        t = t.trimmingCharacters(in: .whitespaces)
        if hasTaskMarker(t) {
            t = t.replacingOccurrences(of: "[ ]", with: "", options: [], range: t.range(of: "[ ]"))
            if let r = t.range(of: "\\[[xX]\\]", options: .regularExpression) { t.removeSubrange(r) }
            t = t.trimmingCharacters(in: .whitespaces)
        }
        if isBullet(t) { t.removeFirst() }
        else if let r = t.range(of: "^\\d+[.)] ", options: .regularExpression) { t.removeSubrange(r) }
        t = t.trimmingCharacters(in: .whitespaces)
        // a thematic break is content, not a marker
        return t
    }

    private static func toggleCodeBlock(raw: String, firstLine: Int, lastLine: Int) -> String {
        let ns = raw as NSString
        let idx = LineIndex(raw)
        let firstText = ns.substring(with: idx.range(ofLine: firstLine))
        if firstText.trimmingCharacters(in: .whitespaces).hasPrefix("```") || firstText.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
            // find the closing fence after this line (the selection may cover just the fence)
            var close = firstLine + 1
            var found = false
            while close < idx.count {
                let t = ns.substring(with: idx.range(ofLine: close)).trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("```") || t.hasPrefix("~~~") { found = true; break }
                close += 1
            }
            let fenceEnd = found ? close + 1 : lastLine + 1
            let start = idx.range(ofLine: firstLine).lowerBound
            let end = (fenceEnd < idx.count) ? idx.starts[fenceEnd] : ns.length
            // keep only the lines between the two fences
            let innerStart = (firstLine + 1 < idx.count) ? idx.starts[firstLine + 1] : start
            let innerEnd = found ? idx.starts[close] : end
            let inner = innerEnd > innerStart
                ? ns.substring(with: NSRange(location: innerStart, length: innerEnd - innerStart))
                : ""
            return ns.substring(to: start) + inner + ns.substring(from: end)
        }
        let start = idx.range(ofLine: firstLine).lowerBound
        let end = (lastLine + 1 < idx.count) ? idx.starts[lastLine + 1] : ns.length
        let body = ns.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        return ns.substring(to: start) + "```\n" + body + "\n```\n" + ns.substring(from: end)
    }

    // MARK: tasks

    public static func toggleTask(_ line: String) -> String {
        let indent = prefixBeforeMarker(line)
        var t = String(line.dropFirst(indent.count))
        if let r = t.range(of: "[ ]") {
            t.replaceSubrange(r, with: "[x]")
        } else if let r = t.range(of: "\\[[xX]\\]", options: .regularExpression) {
            t.replaceSubrange(r, with: "[ ]")
        } else if let dot = t.firstIndex(of: " ") {
            t.insert(contentsOf: "[ ] ", at: t.index(after: dot))
        } else {
            t = "- [ ] " + t
        }
        return indent + t
    }

    private static func prefixBeforeMarker(_ line: String) -> String {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        return String(leading)
    }

    /// Flips `[ ]` / `[x]` at a known raw marker range.
    public static func toggleCheckbox(_ raw: String, markerRange: Range<Int>) -> String {
        let ns = raw as NSString
        let r = NSRange(location: max(0, markerRange.lowerBound), length: min(markerRange.count, max(0, ns.length - markerRange.lowerBound)))
        let current = ns.substring(with: r)
        let replacement = current.lowercased() == "[ ]" ? "[x]" : "[ ]"
        return ns.replacingCharacters(in: r, with: replacement)
    }

    // MARK: input rules

    public enum InputRule {

        /// Called when the user types a space. `lineBeforeSpace` is the current line content
        /// *before* that space. Returns the normalized line prefix (including the space).
        public static func normalize(lineBeforeSpace: String) -> String? {
            if lineBeforeSpace.range(of: "^#{1,6}$", options: .regularExpression) != nil {
                return lineBeforeSpace + " "
            }
            if ["-", "*", "+"].contains(lineBeforeSpace) {
                return lineBeforeSpace + " "
            }
            if lineBeforeSpace == "[]" || lineBeforeSpace == "[ ]" { return "- [ ] " }
            if lineBeforeSpace == "[x]" { return "- [x] " }
            if lineBeforeSpace.range(of: "^\\d+[.)]$", options: .regularExpression) != nil {
                return lineBeforeSpace + " "
            }
            if lineBeforeSpace == ">" { return "> " }
            if lineBeforeSpace == "```" || lineBeforeSpace == "~~~" { return lineBeforeSpace + " " }
            return nil
        }

        /// `---` on an empty line becomes a horizontal rule followed by a new line.
        public static func thematicBreak(lineBeforeSpace: String) -> String? {
            guard lineBeforeSpace.range(of: "^(-{3,}|\\*{3,}|_{3,})$", options: .regularExpression) != nil else { return nil }
            return "--- "
        }

        /// A closing bracket completes a task shortcut at the start of a line. Keep the saved
        /// form standard Markdown and leave the caret after its required content separator.
        public static func completeTask(raw: String, caret: Int) -> (raw: String, caret: Int)? {
            let ns = raw as NSString
            guard caret > 0, caret <= ns.length else { return nil }
            let index = LineIndex(raw)
            let range = index.range(ofLine: index.line(of: caret))
            let prefix = ns.substring(with: range.lowerBound..<caret)
            let indent = String(prefix.prefix { $0 == " " || $0 == "\t" })
            let marker = String(prefix.dropFirst(indent.count))
            guard marker.range(of: "^(?:[-*+] )?\\[(?: |[xX])?\\]$", options: .regularExpression) != nil,
                  !MarkdownParser.parse(raw).contains(where: {
                      if case .codeBlock = $0.kind { return $0.rawRange.contains(caret - 1) }
                      return false
                  }) else { return nil }
            let checked = marker.lowercased().contains("[x]")
            let normalized = indent + (checked ? "- [x] " : "- [ ] ")
            let suffix = ns.substring(from: caret)
            let tail = suffix.hasPrefix(" ") ? String(suffix.dropFirst()) : suffix
            return (ns.substring(to: range.lowerBound) + normalized + tail,
                    range.lowerBound + normalized.utf16.count)
        }

        /// Return key inside a list item: continue the list. Return on an empty item: drop the marker.
        public static func continuation(raw: String, caret: Int) -> (raw: String, caret: Int)? {
            let ns = raw as NSString
            let caret = min(max(0, caret), ns.length)
            guard let block = MarkdownParser.parse(raw).first(where: {
                      $0.rawRange.lowerBound <= caret && caret <= $0.rawRange.upperBound
                  }), case .listItem(let item) = block.kind,
                  caret >= block.contentRange.lowerBound else { return nil }
            let line = ns.substring(with: block.rawRange)
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            if block.contentRange.isEmpty {
                return (ns.replacingCharacters(in: NSRange(block.rawRange), with: ""), block.rawRange.lowerBound)
            }
            let marker = item.task != nil ? "- [ ] " : (item.ordered ? "\(item.index + 1). " : "- ")
            let insertion = "\n" + indent + marker
            return (ns.substring(to: caret) + insertion + ns.substring(from: caret), caret + insertion.utf16.count)
        }

        /// Tab inside a list item increases nesting, Shift-Tab decreases it.
        public static func changeIndent(raw: String, caret: Int, increase: Bool) -> String {
            let ns = raw as NSString
            let idx = LineIndex(raw)
            let lineIndex = idx.line(of: caret)
            let range = idx.range(ofLine: lineIndex)
            let line = ns.substring(with: range)
            guard detectKind(line) != nil else { return raw }
            let leading = String(line.prefix { $0 == " " || $0 == "\t" })
            let rest = String(line.dropFirst(leading.count))
            let newLeading: String
            if increase {
                newLeading = leading + "  "
            } else {
                if leading.isEmpty { return raw }
                newLeading = leading.count >= 2 ? String(leading.dropFirst(2)) : ""
            }
            return ns.substring(to: range.lowerBound) + newLeading + rest + ns.substring(from: range.upperBound)
        }
    }
}
