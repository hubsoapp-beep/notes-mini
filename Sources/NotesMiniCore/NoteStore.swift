import Foundation

public enum StoreError: LocalizedError {
    case folderUnavailable
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .folderUnavailable: return "Folder notatek jest niedostępny."
        case .writeFailed(let s): return "Nie udało się zapisać: \(s)"
        }
    }
}

/// Notes as files in a single folder. One markdown file per note, frontmatter for metadata.
public final class NoteStore {

    public private(set) var folder: URL
    public private(set) var notes: [Note] = []
    public var trashFolder: URL { folder.appendingPathComponent(".trash", isDirectory: true) }

    /// Called after any mutation of the note list or of a note's content.
    public var onChange: (() -> Void)?

    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: CInt = -1
    private var pendingSaves: [URL: DispatchWorkItem] = [:]
    private let saveDelay: DispatchTimeInterval = .milliseconds(450)
    private let queue = DispatchQueue(label: "notesmini.store", qos: .utility)
    private var lastSelfWriteTimestamps: [URL: Date] = [:]
    private var suppressUntil: [URL: Date] = [:]

    public init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: loading

    @discardableResult
    public func reload() -> [Note] {
        let fm = FileManager.default
        var result: [Note] = []
        if let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for url in entries where url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
                if let note = loadNote(at: url) { result.append(note) }
            }
        }
        notes = sorted(result)
        onChange?()
        return notes
    }

    public func loadNote(at url: URL) -> Note? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let (fm, body) = Frontmatter.parse(text)
        return Note(url: url, meta: fm, body: body)
    }

    private func sorted(_ list: [Note]) -> [Note] {
        list.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.updated > b.updated
        }
    }

    public func note(withURL url: URL) -> Note? { notes.first { $0.url == url } }

    // MARK: create / delete

    public func createNote(title: String = "", body: String = "") -> Note {
        let now = Date()
        var meta = Frontmatter(created: now, updated: now, pinned: false)
        meta.title = title.isEmpty ? nil : title
        let note = Note(url: folder.appendingPathComponent(placeholderName(for: now)), meta: meta, body: body)
        note.move(to: uniqueURL(slug: Slug.make(title.isEmpty ? "note" : title)))
        writeNow(note)
        notes.insert(note, at: 0)
        onChange?()
        return note
    }

    private func placeholderName(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "\(Slug.make(f.string(from: date))).md"
    }

    /// Picks a free filename for a slug, ignoring the note's current file (`excluding`) so
    /// saving a note never renames it into a `name-2.md` collision with itself.
    private func uniqueURL(slug: String, excluding: URL? = nil) -> URL {
        var candidate = folder.appendingPathComponent("\(slug).md")
        var n = 2
        var names = Set(notes.map { $0.url.lastPathComponent })
        if let excluding { names.remove(excluding.lastPathComponent) }
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
            if excluding?.lastPathComponent == name { continue }
            names.insert(name)
        }
        let existing = names
        while existing.contains(candidate.lastPathComponent) {
            candidate = folder.appendingPathComponent("\(slug)-\(n).md")
            n += 1
        }
        return candidate
    }

    /// Moves the note to `.trash/`, returns the trashed URL.
    @discardableResult
    public func trash(_ note: Note) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        let stamp = Self.timestamp()
        let dest = trashFolder.appendingPathComponent("\(stamp)-\(note.url.lastPathComponent)")
        do {
            if fm.fileExists(atPath: note.url.path) { try fm.moveItem(at: note.url, to: dest) }
            notes.removeAll { $0 === note }
            onChange?()
            return dest
        } catch {
            return nil
        }
    }

    public func trashedNotes() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: trashFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return entries.filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    @discardableResult
    public func restore(fromTrash url: URL) -> Note? {
        let fm = FileManager.default
        var name = url.lastPathComponent
        // strip the `yyyyMMdd-HHmmss-` prefix added when the note was trashed
        if let r = name.range(of: "^\\d{8}-\\d{6}-", options: .regularExpression) {
            name = String(name[r.upperBound...])
        }
        var dest = folder.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(name.dropLast(4))-\(n).md")
            n += 1
        }
        do {
            try fm.moveItem(at: url, to: dest)
            let note = loadNote(at: dest)
            reload()
            onChange?()
            return note
        } catch { return nil }
    }

    public func deleteForever(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        onChange?()
    }

    public func deleteAllNotes() {
        for note in notes {
            _ = trash(note)
        }
        onChange?()
    }

    // MARK: saving

    public func scheduleSave(_ note: Note) {
        let url = note.url
        pendingSaves[url]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.writeNow(note)
        }
        pendingSaves[url] = item
        queue.asyncAfter(deadline: .now() + saveDelay, execute: item)
    }

    public func flush(_ note: Note) {
        pendingSaves[note.url]?.cancel()
        pendingSaves[note.url] = nil
        writeNow(note)
    }

    public func flushAll() {
        for note in notes { flush(note) }
    }

    public func writeNow(_ note: Note) {
        note.meta.updated = Date()
        if note.meta.created == nil { note.meta.created = note.meta.updated }
        let desired = uniqueURL(slug: Slug.make(note.title), excluding: note.url)
        let currentName = note.url.lastPathComponent
        let desiredName = desired.lastPathComponent
        let fm = FileManager.default
        if desiredName != currentName && Slug.make(note.title) != "note" {
            do {
                if fm.fileExists(atPath: note.url.path) { try fm.moveItem(at: note.url, to: desired) }
                note.move(to: desired)
                suppressUntil[desired] = Date().addingTimeInterval(1.5)
            } catch {
                // keep old name on failure
            }
        }
        let data = Data(note.fileContents().utf8)
        do {
            try data.write(to: note.url, options: .atomic)
            suppressUntil[note.url] = Date().addingTimeInterval(1.2)
            notes = sorted(notes)
            onChange?()
        } catch {
            onChange?()
        }
    }

    public func togglePinned(_ note: Note) {
        note.meta.pinned = !(note.meta.pinned ?? false)
        writeNow(note)
    }

    // MARK: watcher

    public func startWatching() {
        stopWatching()
        let fm = FileManager.default
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            // ignore the writes we caused ourselves
            let now = Date()
            let relevant = self.suppressUntil.filter { $0.value > now }.keys
            self.suppressUntil = self.suppressUntil.filter { $0.value > now }
            _ = relevant
            self.queue.asyncAfter(deadline: .now() + .milliseconds(350)) { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.reload()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
        _ = fm
    }

    public func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedFD = -1
    }

    public func changeFolder(_ newFolder: URL) {
        stopWatching()
        folder = newFolder
        try? FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        reload()
        startWatching()
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    // MARK: search

    public func search(_ query: String, includePinnedFirst: Bool = true) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return notes }
        let folded = Self.fold(q)
        let matches = notes.filter { note in
            Self.fold(note.title).contains(folded) || Self.fold(note.body).contains(folded)
        }
        return includePinnedFirst ? sorted(matches) : matches.sorted { $0.updated > $1.updated }
    }

    public static func fold(_ s: String) -> String {
        let transliterated = s.replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "L")
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "ø", with: "o")
        return transliterated.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
    }
}