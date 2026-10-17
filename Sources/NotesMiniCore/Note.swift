import Foundation

// MARK: - Slug

public enum Slug {
    /// Lowercase ASCII slug with Polish diacritics transliterated.
    public static func make(_ text: String, maxLength: Int = 60) -> String {
        let folded = fold(text)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        var out = String()
        var lastDash = false
        for ch in folded.lowercased() {
            let isAllowed = ch.unicodeScalars.contains { allowed.contains($0) }
            if isAllowed && ch != "-" {
                out.append(ch)
                lastDash = false
            } else if !lastDash && !out.isEmpty {
                out.append("-")
                lastDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        while out.hasPrefix("-") { out.removeFirst() }
        if out.count > maxLength {
            out = String(out.prefix(maxLength))
            while out.hasSuffix("-") { out.removeLast() }
        }
        return out.isEmpty ? "note" : out
    }

    private static func fold(_ s: String) -> String {
        let map: [Character: String] = [
            "ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z",
            "Ą": "a", "Ć": "c", "Ę": "e", "Ł": "l", "Ń": "n", "Ó": "o", "Ś": "s", "Ź": "z", "Ż": "z",
        ]
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if let r = map[ch] { out += r } else { out.append(ch) }
        }
        return out
    }
}

// MARK: - Frontmatter

public struct Frontmatter: Equatable {
    public var title: String?
    public var created: Date?
    public var updated: Date?
    public var pinned: Bool?

    public init(title: String? = nil, created: Date? = nil, updated: Date? = nil, pinned: Bool? = nil) {
        self.title = title
        self.created = created
        self.updated = updated
        self.pinned = pinned
    }

    nonisolated(unsafe) public static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    /// Serializes to `---\nkey: value\n---\n\n`. Returns nil when there is nothing to write.
    public func serialize(includeBodySeparator: Bool = true) -> String? {
        var lines: [String] = []
        if let title, !title.isEmpty { lines.append("title: \(yamlEscape(title))") }
        if let created { lines.append("created: \(Frontmatter.formatter.string(from: created))") }
        if let updated { lines.append("updated: \(Frontmatter.formatter.string(from: updated))") }
        if let pinned { lines.append("pinned: \(pinned)") }
        guard !lines.isEmpty else { return nil }
        let sep = includeBodySeparator ? "\n\n" : "\n"
        return "---\n" + lines.joined(separator: "\n") + "\n---" + sep
    }

    private func yamlEscape(_ s: String) -> String {
        if s.contains(": ") || s.hasSuffix(":") || s.hasPrefix(" ") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ") + "\""
        }
        return s
    }

    /// Parses a leading frontmatter block from a markdown file. Returns the block and the body
    /// (everything after the closing fence, leading blank lines removed).
    public static func parse(_ fileContents: String) -> (frontmatter: Frontmatter, body: String) {
        let ns = fileContents as NSString
        guard ns.length >= 3, ns.substring(with: NSRange(location: 0, length: 3)) == "---" else {
            return (Frontmatter(), fileContents)
        }
        // closing fence must be on its own line
        var cursor = 3
        var sawNewlineAfterOpen = false
        while cursor < ns.length {
            let ch = ns.substring(with: NSRange(location: cursor, length: 1))
            if ch == "\n" { sawNewlineAfterOpen = true; cursor += 1; break }
            if ch == "-" || ch == "\u{0}" { return (Frontmatter(), fileContents) }
            cursor += 1
        }
        guard sawNewlineAfterOpen else { return (Frontmatter(), fileContents) }

        // find closing "---" line
        var search = cursor
        var closeStart = -1
        var bodyStart = -1
        while search <= ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: search, length: 0))
            let line = ns.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" || trimmed == "..." {
                closeStart = lineRange.location
                bodyStart = NSMaxRange(lineRange)
                break
            }
            if NSMaxRange(lineRange) >= ns.length { break }
            search = NSMaxRange(lineRange)
        }
        guard closeStart >= 0, bodyStart >= 0 else { return (Frontmatter(), fileContents) }

        let blockRange = NSRange(location: cursor, length: closeStart - cursor)
        let block = ns.substring(with: blockRange)
        var fm = Frontmatter()
        for rawLine in block.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
                value = value.replacingOccurrences(of: "\\\"", with: "\"")
            }
            switch key {
            case "title": fm.title = value
            case "created": fm.created = formatter.date(from: value)
            case "updated": fm.updated = formatter.date(from: value)
            case "pinned": fm.pinned = ["true", "yes", "1"].contains(value.lowercased())
            default: break
            }
        }
        let body = bodyStart < ns.length
            ? ns.substring(from: bodyStart).drop(while: { $0 == "\n" || $0 == "\r" }).description
            : ""
        return (fm, body)
    }
}

// MARK: - Note

/// One markdown file on disk. `url` is the file location and the identity of the note;
/// it changes when the note is renamed (title edited).
public final class Note {
    public private(set) var url: URL
    public var meta: Frontmatter
    public var body: String

    /// First line of the body, stripped of markdown heading markers — Raycast's note title.
    public var title: String {
        let first = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        var t = first.trimmingCharacters(in: .whitespaces)
        while t.hasPrefix("#") { t.removeFirst() }
        t = t.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "~", with: "")
        return t
    }

    public var isPinned: Bool { meta.pinned == true }

    public var displayTitle: String {
        let t = title
        return t.isEmpty ? "Untitled Note" : t
    }

    public init(url: URL, meta: Frontmatter, body: String) {
        self.url = url
        self.meta = meta
        self.body = body
    }

    public var created: Date { meta.created ?? meta.updated ?? Date.distantPast }
    public var updated: Date { meta.updated ?? meta.created ?? Date.distantPast }

    /// Full file contents (frontmatter + body).
    public func fileContents() -> String {
        var fm = meta
        fm.title = title.isEmpty ? nil : title
        return (fm.serialize() ?? "") + body
    }

    public func move(to newURL: URL) { url = newURL }

    /// Single-line preview used in the browse list.
    public func preview(maxLength: Int = 220) -> String {
        var lines: [String] = []
        body.split(separator: "\n", omittingEmptySubsequences: false).forEach { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return }
            guard !s.hasPrefix("```"), !s.hasPrefix("#") else {
                if s.hasPrefix("#") { lines.append(cleanMarkdown(s)) }
                return
            }
            lines.append(cleanMarkdown(s))
        }
        var joined = lines.joined(separator: "  ")
        if joined.count > maxLength { joined = String(joined.prefix(maxLength)) + "…" }
        return joined
    }

    private func cleanMarkdown(_ s: String) -> String {
        s
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "~~", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "](", with: " ")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}