import Foundation

public enum ExportFormat: String, CaseIterable {
    case markdown = "Markdown"
    case plainText = "Plain Text"
    case html = "HTML"
}

public enum Exporter {

    public static func export(_ note: Note, as format: ExportFormat) -> String {
        switch format {
        case .markdown: return note.fileContents()
        case .plainText: return plainText(note.body)
        case .html: return html(note, body: note.body)
        }
    }

    public static func suggestedFilename(_ note: Note, format: ExportFormat) -> String {
        let base = Slug.make(note.displayTitle)
        switch format {
        case .markdown: return "\(base).md"
        case .plainText: return "\(base).txt"
        case .html: return "\(base).html"
        }
    }

    // MARK: plain text

    public static func plainText(_ raw: String) -> String {
        var out = ""
        let ns = raw as NSString
        let blocks = MarkdownParser.parse(raw)
        var cursor = 0
        for block in blocks {
            if block.rawRange.lowerBound > cursor {
                let gap = ns.substring(with: cursor..<min(block.rawRange.lowerBound, ns.length))
                if gap.contains("\n") { out += "\n" }
            }
            cursor = max(cursor, block.rawRange.upperBound)
            switch block.kind {
            case .heading(let level):
                let text = plain(ns.substring(with: block.contentRange))
                out += "\(String(repeating: "#", count: level)) \(text)\n"
            case .paragraph:
                out += plain(ns.substring(with: block.contentRange)) + "\n"
            case .blockquote:
                out += plain(ns.substring(with: block.contentRange)) + "\n"
            case .listItem(let item):
                let text = plain(ns.substring(with: block.contentRange))
                if let task = item.task {
                    out += "\(task == .checked ? "[x]" : "[ ]") \(text)\n"
                } else if item.ordered {
                    out += "\(item.index). \(text)\n"
                } else {
                    out += "• \(text)\n"
                }
            case .codeBlock:
                for (text, _) in block.codeLines { out += text + "\n" }
            case .thematicBreak:
                out += "\n"
            }
        }
        return out.trimmingCharacters(in: .newlines) + "\n"
    }

    private static func plain(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "__", with: "")
        t = t.replacingOccurrences(of: "~~", with: "")
        t = t.replacingOccurrences(of: "<u>", with: "").replacingOccurrences(of: "</u>", with: "")
        t = t.replacingOccurrences(of: "](", with: " (")
        t = t.replacingOccurrences(of: "[", with: "")
        t = t.replacingOccurrences(of: "*", with: "")
        t = t.replacingOccurrences(of: "_", with: "")
        return t
    }

    // MARK: html

    public static func html(_ note: Note, body: String? = nil) -> String {
        let content = body ?? note.body
        var bodyHTML = ""
        let blocks = MarkdownParser.parse(content)
        for block in blocks {
            switch block.kind {
            case .heading(let level):
                let tag = "h\(min(level, 6))"
                bodyHTML += "<\(tag)>\(inlineHTML(block.inlines, in: content))</\(tag)>\n"
            case .paragraph:
                bodyHTML += "<p>\(inlineHTML(block.inlines, in: content))</p>\n"
            case .blockquote:
                bodyHTML += "<blockquote>\(inlineHTML(block.inlines, in: content))</blockquote>\n"
            case .listItem(let item):
                let cls = item.task != nil ? " class=\"task\"" : ""
                let box = item.task.map { $0 == .checked ? "☑️ " : "⬜️ " } ?? ""
                bodyHTML += "<\(item.ordered ? "ol" : "ul")\(cls)><li>\(box)\(inlineHTML(block.inlines, in: content))</li></\(item.ordered ? "ol" : "ul")>\n"
            case .codeBlock(let lang):
                let l = lang.map { " class=\"language-\($0)\"" } ?? ""
                bodyHTML += "<pre><code\(l)>" + block.codeLines.map { escapeHTML($0.text) }.joined(separator: "\n") + "</code></pre>\n"
            case .thematicBreak:
                bodyHTML += "<hr>\n"
            }
        }
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>\(escapeHTML(note.displayTitle))</title>
        <style>
        body { font: -apple-system-body; font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 46em; margin: 3em auto; padding: 0 1.2em; line-height: 1.55; color: #1c1c1e; }
        code { font-family: ui-monospace, Menlo, monospace; background: rgba(0,0,0,.06); padding: .1em .35em; border-radius: 4px; font-size: .9em; }
        pre { background: rgba(0,0,0,.05); padding: .9em 1em; border-radius: 8px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { border-left: 3px solid rgba(0,0,0,.2); margin: 0; padding-left: 1em; color: #555; }
        a { color: #0a58ca; }
        hr { border: none; border-top: 1px solid rgba(0,0,0,.12); }
        </style>
        </head>
        <body>
        \(bodyHTML)</body>
        </html>
        """
    }

    private static func inlineHTML(_ nodes: [InlineNode], in raw: String) -> String {
        var out = ""
        for node in nodes {
            switch node.kind {
            case .text:
                out += escapeHTML(node.content)
            case .strong: out += "<strong>\(inlineHTML(node.children, in: raw))</strong>"
            case .em: out += "<em>\(inlineHTML(node.children, in: raw))</em>"
            case .strike: out += "<s>\(inlineHTML(node.children, in: raw))</s>"
            case .code: out += "<code>\(escapeHTML(node.content))</code>"
            case .link:
                let inner = node.children.isEmpty ? escapeHTML(node.url ?? "") : inlineHTML(node.children, in: raw)
                out += "<a href=\"\(escapeHTML(node.url ?? ""))\">\(inner)</a>"
            case .image:
                out += "<img alt=\"\(escapeHTML(node.content))\" src=\"\(escapeHTML(node.url ?? ""))\">"
            case .lineBreak: out += "<br>"
            }
        }
        return out
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}