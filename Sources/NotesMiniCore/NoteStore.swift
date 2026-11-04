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
///
/// Confined to the main thread: saves are debounced on the main queue and the folder watcher reports
/// there too, so the editor and the store can never see each other half way through a change.
/// Files are small and written atomically, so this costs no perceptible time.
///
/// There is exactly one `Note` object per file for as long as the file exists. The editor holds that
/// object and types into it, and a reload updates it in place. A reload that built fresh objects left
/// the store holding a stale copy of the open note, which then replaced the text being typed.
public final class NoteStore {

    public private(set) var folder: URL
    public private(set) var notes: [Note] = []
    public var trashFolder: URL { folder.appendingPathComponent(".trash", isDirectory: true) }

    /// Called after any mutation of the note list or of a note's content.
    public var onChange: (() -> Void)?

    /// Called when someone else changed the file of a note with no unsaved edits. The note already
    /// holds the new text by then; whoever displays it has to redraw.
    public var onExternalChange: ((Note) -> Void)?

    /// Called when a save failed. The edit stays pending and is retried.
    public var onSaveFailure: ((Note, String) -> Void)?

    private var watcher: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    /// A note waiting to be saved. Only these are written by `flushAll()`: a note the user never
    /// touched must stay byte-identical on disk, frontmatter and all. Keyed by identity because a
    /// save can rename the file, and a key built from the path would then stop matching.
    private struct PendingSave {
        let note: Note
        let firstEdit: Date
        var work: DispatchWorkItem
    }
    private var pending: [ObjectIdentifier: PendingSave] = [:]

    private let saveDelay: DispatchTimeInterval
    private let maxSaveDelay: DispatchTimeInterval
    private static let retryDelay: DispatchTimeInterval = .seconds(2)
    private static let reloadDelay: DispatchTimeInterval = .milliseconds(250)

    /// What the file of each note held the last time this store read or wrote it, by path. A file
    /// that differs from this was changed by someone else.
    private var lastKnownContents: [String: Data] = [:]

    public init(folder: URL,
                saveDelay: DispatchTimeInterval = .milliseconds(450),
                maxSaveDelay: DispatchTimeInterval = .seconds(4)) {
        // Standardised so that a note's URL compares equal however the path was spelled: on macOS
        // `/var` and `/private/var` are the same directory but different strings, and the store
        // compares URLs to find notes.
        self.folder = folder.resolvingSymlinksInPath()
        self.saveDelay = saveDelay
        self.maxSaveDelay = maxSaveDelay
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
    }

    // MARK: loading

    /// Brings the list in line with the folder, keeping every known note's object.
    @discardableResult
    public func reload() -> [Note] {
        let fm = FileManager.default
        var known: [String: Note] = [:]
        for note in notes { known[note.url.path] = note }
        var result: [Note] = []
        var seen = Set<String>()
        let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in entries where Self.isNoteFile(url) {
            let path = folder.appendingPathComponent(url.lastPathComponent).path
            guard let data = try? Data(contentsOf: url) else {
                // Unreadable right now, perhaps mid-write. Dropping a known note here would make it
                // vanish from the list for one reload.
                if let note = known[path] { result.append(note); seen.insert(path) }
                continue
            }
            if let note = known[path] {
                refresh(note, from: data)
                result.append(note)
            } else if let note = Self.parse(data, url: folder.appendingPathComponent(url.lastPathComponent)) {
                result.append(note)
            }
            lastKnownContents[path] = data
            seen.insert(path)
        }
        // A note whose file is gone stays listed while it has edits waiting: the save recreates it.
        for note in notes where !seen.contains(note.url.path) && isPending(note) { result.append(note) }
        lastKnownContents = lastKnownContents.filter { seen.contains($0.key) }
        notes = sorted(result)
        onChange?()
        return notes
    }

    /// Takes in the file's current contents if someone else changed them.
    private func refresh(_ note: Note, from data: Data) {
        let path = note.url.path
        guard let last = lastKnownContents[path] else { return }
        guard last != data else { return }
        if isPending(note) {
            keepConflictCopy(of: data, for: note)
            return
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        let (meta, body) = Frontmatter.parse(text)
        note.meta = meta
        note.body = body
        onExternalChange?(note)
    }

    private static func isNoteFile(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    private static func parse(_ data: Data, url: URL) -> Note? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let (meta, body) = Frontmatter.parse(text)
        return Note(url: url, meta: meta, body: body)
    }

    public func loadNote(at url: URL) -> Note? {
        if let listed = note(withURL: url) { return listed }
        guard let data = try? Data(contentsOf: url), let note = Self.parse(data, url: url) else { return nil }
        lastKnownContents[url.path] = data
        return note
    }

    private func sorted(_ list: [Note]) -> [Note] {
        list.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.updated > b.updated
        }
    }

    /// By path: two `URL`s for one file need not compare equal, and a directory listing and
    /// `appendingPathComponent` do not always produce the same spelling.
    public func note(withURL url: URL) -> Note? { notes.first { $0.url.path == url.path } }

    // MARK: create / delete

    public func createNote(title: String = "", body: String = "") -> Note {
        let now = Date()
        var meta = Frontmatter(created: now, updated: now, pinned: false)
        meta.title = title.isEmpty ? nil : title
        let note = Note(url: folder.appendingPathComponent(placeholderName(for: now)), meta: meta, body: body)
        note.move(to: uniqueURL(slug: Slug.make(title.isEmpty ? "note" : title)))
        notes.insert(note, at: 0)
        writeNow(note)
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
        // Save first: the words typed just before trashing belong in the trash too. It also takes
        // the note off the pending list, so no late save can bring the file back.
        if isPending(note) { flush(note) }
        try? fm.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        let stamp = Self.timestamp()
        let dest = trashFolder.appendingPathComponent("\(stamp)-\(note.url.lastPathComponent)")
        do {
            if fm.fileExists(atPath: note.url.path) { try fm.moveItem(at: note.url, to: dest) }
            lastKnownContents[note.url.path] = nil
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
            reload()
            return note(withURL: dest)
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

    /// Saves once typing pauses, and in any case before an edit gets older than `maxSaveDelay`.
    public func scheduleSave(_ note: Note) {
        let id = ObjectIdentifier(note)
        let firstEdit = pending[id]?.firstEdit ?? Date()
        pending[id]?.work.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeNow(note) }
        pending[id] = PendingSave(note: note, firstEdit: firstEdit, work: work)
        let budget = Self.seconds(maxSaveDelay) - Date().timeIntervalSince(firstEdit)
        let delay = max(0, min(Self.seconds(saveDelay), budget))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func seconds(_ interval: DispatchTimeInterval) -> TimeInterval {
        switch interval {
        case .seconds(let v): return TimeInterval(v)
        case .milliseconds(let v): return TimeInterval(v) / 1_000
        case .microseconds(let v): return TimeInterval(v) / 1_000_000
        case .nanoseconds(let v): return TimeInterval(v) / 1_000_000_000
        default: return 0
        }
    }

    public func flush(_ note: Note) {
        writeNow(note)
    }

    /// Writes only the notes that are actually waiting to be saved.
    public func flushAll() {
        for entry in pending.values { writeNow(entry.note) }
    }

    public var hasPendingSaves: Bool { !pending.isEmpty }

    public func isPending(_ note: Note) -> Bool { pending[ObjectIdentifier(note)] != nil }

    private func clearPending(_ note: Note) {
        pending.removeValue(forKey: ObjectIdentifier(note))?.work.cancel()
    }

    public func writeNow(_ note: Note) {
        let fm = FileManager.default
        clearPending(note)

        // Writing a file whose contents would not change is pure noise: it bumps the modification
        // date, wakes the watcher and makes the note jump to the top of a "recently updated" list.
        // Compared before `updated` moves, which would otherwise make every save look like a change.
        let onDisk = try? Data(contentsOf: note.url)
        if let onDisk, onDisk == Data(note.fileContents().utf8) {
            lastKnownContents[note.url.path] = onDisk
            return
        }

        // Whatever is in the file now is about to be replaced. If it is not what this store last
        // saw, it is someone else's work that nothing has picked up yet.
        if let onDisk, let last = lastKnownContents[note.url.path], last != onDisk {
            keepConflictCopy(of: onDisk, for: note)
        }

        note.meta.updated = Date()
        if note.meta.created == nil { note.meta.created = note.meta.updated }
        let data = Data(note.fileContents().utf8)
        let originalURL = note.url
        let inNotesFolder = note.url.deletingLastPathComponent().path == folder.path

        // The filename follows the title, so a note stays findable by name in Finder or Obsidian.
        // A note with no title yet keeps its placeholder name rather than becoming `note.md`.
        // Files opened from elsewhere stay where they are and keep their names.
        let stem = note.url.deletingPathExtension().lastPathComponent
        let slug = Slug.make(note.title)
        if inNotesFolder, !slug.isEmpty, slug != "note", slug != stem {
            let desired = uniqueURL(slug: slug, excluding: note.url)
            if desired.lastPathComponent != note.url.lastPathComponent,
               fm.fileExists(atPath: note.url.path),
               (try? fm.moveItem(at: note.url, to: desired)) != nil {
                note.move(to: desired)
            }
        }

        do {
            try data.write(to: note.url, options: .atomic)
            lastKnownContents[originalURL.path] = nil
            lastKnownContents[note.url.path] = data
            // Re-listed here for a note whose file disappeared while it was open.
            if inNotesFolder, !notes.contains(where: { $0 === note }) { notes.append(note) }
            notes = sorted(notes)
            onChange?()
        } catch {
            NSLog("[NotesMini] save failed for %@: %@", note.url.path, String(describing: error))
            retrySave(note)
            onSaveFailure?(note, error.localizedDescription)
        }
    }

    /// A failed save must not forget the edit: the folder may simply be on a disk that came back.
    private func retrySave(_ note: Note) {
        let work = DispatchWorkItem { [weak self] in self?.writeNow(note) }
        pending[ObjectIdentifier(note)] = PendingSave(note: note, firstEdit: Date(), work: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay, execute: work)
    }

    /// Keeps someone else's version of a note next to it, instead of overwriting it.
    private func keepConflictCopy(of data: Data, for note: Note) {
        let stem = note.url.deletingPathExtension().lastPathComponent
        let directory = note.url.deletingLastPathComponent()
        let base = "\(stem) (konflikt \(Self.timestamp()))"
        var copy = directory.appendingPathComponent("\(base).md")
        var n = 2
        while FileManager.default.fileExists(atPath: copy.path) {
            copy = directory.appendingPathComponent("\(base) \(n).md")
            n += 1
        }
        do {
            try data.write(to: copy, options: .atomic)
            // Treated as seen: the next reload lists the copy as a note of its own.
            lastKnownContents[note.url.path] = data
        } catch {
            NSLog("[NotesMini] could not keep conflict copy at %@: %@", copy.path, String(describing: error))
        }
    }

    public func togglePinned(_ note: Note) {
        note.meta.pinned = !(note.meta.pinned ?? false)
        writeNow(note)
    }

    // MARK: watcher

    /// Watches the folder's entries. Atomic saves show up here, which covers most editors; a program
    /// that writes into an existing file does not, which is why the app reloads whenever the panel
    /// takes focus and why `writeNow` checks the file again before replacing it.
    public func startWatching() {
        stopWatching()
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[NotesMini] cannot watch %@", folder.path)
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Coalesces a burst of folder events into one reload.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reloadDelay, execute: work)
    }

    public func stopWatching() {
        pendingReload?.cancel()
        pendingReload = nil
        watcher?.cancel()
        watcher = nil
    }

    public func changeFolder(_ newFolder: URL) {
        let resolved = newFolder.resolvingSymlinksInPath()
        guard resolved.path != folder.path else { return }
        flushAll()
        stopWatching()
        folder = resolved
        notes = []
        lastKnownContents = [:]
        try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
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
        TextFold.fold(s)
    }
}