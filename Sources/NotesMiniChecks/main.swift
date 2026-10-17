import AppKit
import Foundation
import NotesMiniCore

// CommandLineTools ships neither XCTest nor swift-testing, so the regression suite is a
// plain executable: `swift run NotesMiniChecks`.

var totalChecks = 0
var failures: [String] = []

func check(_ condition: Bool, _ label: String) {
    totalChecks += 1
    if !condition {
        failures.append(label)
        print("✗ \(label)")
    }
}

func eq<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    totalChecks += 1
    if actual != expected {
        failures.append(label)
        print("✗ \(label)\n    got:      \(actual)\n    expected: \(expected)")
    }
}

func tempFolder() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notesmini-checks-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Frontmatter

func testFrontmatter() {
    let text = """
    ---
    title: Spotkanie z Petrem
    created: 2026-10-17T12:00:00Z
    updated: 2026-10-17T12:30:00Z
    pinned: true
    ---

    # Spotkanie z Petrem
    body text
    """
    let (fm, body) = Frontmatter.parse(text)
    eq(fm.title, "Spotkanie z Petrem", "frontmatter title")
    eq(fm.pinned, true, "frontmatter pinned")
    check(fm.created != nil, "frontmatter created")
    eq(body, "# Spotkanie z Petrem\nbody text", "frontmatter body")

    let note = Note(url: URL(fileURLWithPath: "/tmp/a.md"), meta: fm, body: body)
    let (fm2, body2) = Frontmatter.parse(note.fileContents())
    // `title` is carried by the first body line, so it must round-trip through the note, not
    // through the frontmatter — writing it in both places duplicated it inside the file.
    eq(note.title, "Spotkanie z Petrem", "title round-trips through the body")
    check(fm2.title == nil, "body title is not duplicated into frontmatter")
    eq(note.fileContents().components(separatedBy: "# Spotkanie z Petrem").count - 1, 1,
       "title appears exactly once in the file")
    eq(fm2.pinned, fm.pinned, "frontmatter roundtrip pinned")
    eq(body2, body, "frontmatter roundtrip body")

    let (fm3, body3) = Frontmatter.parse("# Title\n\ntext")
    check(fm3.title == nil, "no frontmatter")
    eq(body3, "# Title\n\ntext", "no frontmatter body")

    let unterminated = "---\ntitle: x\n\nbody"
    let (fm4, body4) = Frontmatter.parse(unterminated)
    check(fm4.title == nil, "unterminated frontmatter ignored")
    eq(body4, unterminated, "unterminated frontmatter keeps file")

    let quoted = Frontmatter(title: "Re: prośba", created: Date(), updated: Date(), pinned: false).serialize() ?? ""
    check(quoted.contains("title: \"Re: prośba\""), "title with colon is quoted: \(quoted)")
    eq(Frontmatter.parse(quoted).frontmatter.title, "Re: prośba", "quoted title roundtrip")
}

// MARK: - Slug

func testSlug() {
    eq(Slug.make("Zażółć gęślą jaźń — 100%!"), "zazolc-gesla-jazn-100", "slug polish")
    eq(Slug.make("  spaces  everywhere  "), "spaces-everywhere", "slug spaces")
    eq(Slug.make("!!!"), "note", "slug fallback")
    eq(Slug.make("Notatka z 2026-10-17"), "notatka-z-2026-10-17", "slug keeps digits")
}

// MARK: - Parser

func testParser() {
    let raw = "# Title\n\nsome **bold** and *em* and `code`\n\n- one\n- [ ] task\n- [x] done\n\n1. first\n\n> quote\n\n```swift\nlet x = 1\n```\n\n---\n"
    let blocks = MarkdownParser.parse(raw)
    eq(blocks.count, 9, "block count")
    if case .heading(1) = blocks[0].kind {} else { check(false, "block 0 heading") }
    if case .paragraph = blocks[1].kind {} else { check(false, "block 1 paragraph") }
    if case .listItem(let i) = blocks[2].kind {
        check(!i.ordered, "bullet unordered")
        check(i.task == nil, "bullet has no task")
        eq(i.indent, 0, "bullet indent")
    } else { check(false, "block 2 list item") }
    if case .listItem(let i) = blocks[3].kind {
        eq(i.task, .unchecked, "unchecked task")
    } else { check(false, "block 3 task item") }
    if case .listItem(let i) = blocks[4].kind {
        eq(i.task, .checked, "checked task")
    } else { check(false, "block 4 checked task") }
    if case .listItem(let i) = blocks[5].kind {
        check(i.ordered, "ordered item")
        eq(i.index, 1, "ordered index")
    } else { check(false, "block 5 ordered item") }
    if case .blockquote = blocks[6].kind {} else { check(false, "block 6 quote") }
    if case .codeBlock(let lang) = blocks[7].kind {
        eq(lang, "swift", "code fence language")
        eq(blocks[7].codeLines.first?.text, "let x = 1", "code fence content")
    } else { check(false, "block 7 code block") }
    if case .thematicBreak = blocks[8].kind {} else { check(false, "block 8 hr") }

    let inlineRaw = "a **b** *c* ~~d~~ `e` [f](https://x.com) <https://y.com> https://z.com"
    let kinds = MarkdownParser.parse(inlineRaw)[0].inlines.map { $0.kind }
    check(kinds.contains(.strong), "inline strong")
    check(kinds.contains(.em), "inline em")
    check(kinds.contains(.strike), "inline strike")
    check(kinds.contains(.code), "inline code")
    eq(kinds.filter { $0 == .link }.count, 3, "inline links")

    check(!MarkdownParser.parse("some_var_name here")[0].inlines.contains { $0.kind == .em }, "intra-word underscore")

    let nested = MarkdownParser.parse("- a\n  - b\n    - c\n")
    let indents = nested.compactMap { block -> Int? in if case .listItem(let i) = block.kind { return i.indent } else { return nil } }
    eq(indents, [0, 1, 2], "nested list indents")
}

// MARK: - Renderer

func testRenderer() {
    let raw = "# Title\n\n- item one\n- [ ] task\n\n**bold** and `code` and [link](https://x.com)\n"
    let r = NoteRenderer.render(raw)
    let d = r.display.string
    check(!d.contains("# "), "heading marker hidden")
    check(!d.contains("**"), "bold marker hidden")
    check(!d.contains("`"), "code marker hidden")
    check(d.contains("Title") && d.contains("item one") && d.contains("bold") && d.contains("code") && d.contains("link"), "content visible")
    check(d.contains("•"), "bullet rendered")

    let layoutRaw = "# A\n\n\ntext\n\n- x\n- y\n\n```\ncode\n```\n\nend\n"
    let lr = NoteRenderer.render(layoutRaw)
    let rawLines = (layoutRaw as NSString).components(separatedBy: "\n").count
    let displayLines = lr.display.string.components(separatedBy: "\n").count
    eq(rawLines, displayLines, "display line count equals raw line count")

    let mapRaw = "# Title\n\n- item **one**\n- [ ] task item\n\n```\nlet a = 1\n```\n\ntext with `code`\n"
    let mr = NoteRenderer.render(mapRaw)
    var mappingWorst = 0
    var mappingBad = ""
    for rawOffset in 0...(mapRaw as NSString).length {
        let dOff = mr.displayOffsetForCaret(rawOffset)
        if dOff < 0 || dOff > mr.displayLength {
            mappingBad = "raw \(rawOffset) -> display \(dOff) out of bounds"
            break
        }
        let back = mr.rawOffsetForCaret(dOff)
        let delta = abs(back - rawOffset)
        if delta > mappingWorst { mappingWorst = delta; }
        if delta > 4 { mappingBad = "raw \(rawOffset) -> display \(dOff) -> raw \(back)" }
    }
    check(mappingBad.isEmpty, "mapping round trip: \(mappingBad)")

    let taskRaw = "- [ ] buy milk\n"
    let tr = NoteRenderer.render(taskRaw)
    let milkRange = tr.rawRange(forDisplayRange: (tr.display.string as NSString).range(of: "milk"))
    eq((taskRaw as NSString).substring(with: milkRange), "milk", "selection maps to raw content")
    let marker = CheckboxImages.taskMarkerRawRange(containingRawOffset: milkRange.location, raw: taskRaw)
    eq(marker.map { (taskRaw as NSString).substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }, "[ ]", "task marker lookup")

    let headingRaw = "# Heading\n"
    let hr = NoteRenderer.render(headingRaw)
    eq((headingRaw as NSString).substring(to: hr.rawOffsetForCaret(0)), "# ", "caret at line start is after marker")

    let empty = NoteRenderer.render("")
    eq(empty.displayLength, 0, "empty display length")
    eq(empty.rawLength, 0, "empty raw length")
    eq(empty.rawOffsetForCaret(0), 0, "empty caret mapping")

    // Polish counts take three forms, and 12–14 is the irregular range.
    eq(CountText.characters(1), "1 znak", "singular count")
    eq(CountText.characters(3), "3 znaki", "few count")
    eq(CountText.characters(13), "13 znaków", "teens take the plural form")
    eq(CountText.characters(22), "22 znaki", "22 takes the few form")
    eq(CountText.characters(21), "21 znaków", "21 takes the plural form")
    eq(CountText.characters(101), "101 znaków", "101 takes the plural form")
    eq(CountText.characters(0), "0 znaków", "zero count")

    // A finished task is dimmed so the outstanding ones stand out.
    let tasks = NoteRenderer.render("- [x] zrobione\n- [ ] otwarte\n")
    var checkedIsDim = false
    var openIsDim = false
    tasks.display.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: tasks.display.length)) { value, range, _ in
        guard let color = value as? NSColor else { return }
        let text = (tasks.display.string as NSString).substring(with: range)
        if text.contains("zrobione") { checkedIsDim = color == NSColor.secondaryLabelColor }
        if text.contains("otwarte") { openIsDim = color == NSColor.secondaryLabelColor }
    }
    check(checkedIsDim, "a checked task is dimmed")
    check(!openIsDim, "an open task keeps the body colour")

    let uni = NoteRenderer.render("# Zażółć gęślą jaźń 😀\n\ntekst: ąćęłńóśźż\n")
    check(uni.display.string.contains("Zażółć gęślą jaźń 😀"), "emoji + polish headline")
    check(uni.display.string.contains("ąćęłńóśźż"), "polish body")

    let deco = NoteRenderer.render("text `code`\n\n> quoted\n\n```\nblock\n```\n")
    check(deco.decorations.contains { $0.kind == .inlineCode }, "inline code decoration")
    check(deco.decorations.contains { $0.kind == .codeBlock }, "code block decoration")
    // The `>` marker is hidden, so the rule that makes a quote readable has to be a decoration.
    let quoteBar = deco.decorations.first { $0.kind == .quoteBar }
    check(quoteBar != nil, "quote bar decoration")
    if let quoteBar {
        eq((deco.display.string as NSString).substring(with: quoteBar.range), "quoted", "quote bar covers the quote text")
    }

    // A fenced block must keep exactly one display line per source line. The fences own a line
    // break but no text, so a bug that emits the break twice inserts a blank line between every
    // pair of code lines — which reads as double-spaced code.
    let fenced = "before\n\n```swift\nlet a = 1\nlet b = 2\n```\n\nafter\n"
    let fencedOut = NoteRenderer.render(fenced)
    check(fencedOut.display.string.contains("let a = 1\nlet b = 2"),
          "code lines are not separated by blank lines")
    eq(fencedOut.display.string.components(separatedBy: "\n").count,
       fenced.components(separatedBy: "\n").count, "code block keeps the line count")

    // A genuinely blank line inside a block is still preserved.
    let fencedGap = NoteRenderer.render("```\na\n\nb\n```\n")
    check(fencedGap.display.string.contains("a\n\nb"), "a blank code line survives")
    eq(fencedGap.display.string.components(separatedBy: "\n").count, 6, "blank code line keeps the count")

    let endRaw = "# Title\n"
    let er = NoteRenderer.render(endRaw)
    eq(er.rawOffsetForCaret(er.displayLength), (endRaw as NSString).length, "caret at end maps to raw end")

    var big = ""
    for i in 0..<600 {
        big += "## Section \(i)\n\nSome **bold** text with `code` and a [link](https://example.com).\n\n- item\n- [ ] task\n\n> quote\n\n```\ncode block\n```\n\n"
    }
    // Perf. Absolute budgets are mode-aware (debug builds run ~15x slower than release),
    // and the scaling check is the real regression guard: it fails if rendering ever
    // becomes quadratic again (4x the text must not cost anywhere near 16x the time).
    func renderMillis(_ text: String, iterations: Int) -> Double {
        let start = Date()
        for _ in 0..<iterations { _ = NoteRenderer.render(text) }
        return Date().timeIntervalSince(start) / Double(iterations) * 1000
    }
    #if DEBUG
    let bigBudget = 1500.0, smallBudget = 40.0
    #else
    let bigBudget = 150.0, smallBudget = 3.0
    #endif

    let small = String(repeating: "## Nagłówek\n\nTekst z **pogrubieniem** i `kodem`.\n\n- punkt\n- [ ] zadanie\n\n> cytat\n\n", count: 12)
    let smallMs = renderMillis(small, iterations: 50)
    check(smallMs < smallBudget, String(format: "small render %.2fms (< %.0fms)", smallMs, smallBudget))

    let quarter = String(big.prefix(big.count / 4))
    let quarterMs = renderMillis(quarter, iterations: 20)
    let bigMs = renderMillis(big, iterations: 10)
    check(bigMs < bigBudget, String(format: "big render %.1fms (< %.0fms)", bigMs, bigBudget))
    let factor = bigMs / max(quarterMs, 0.001)
    check(factor < 8, String(format: "render scales linearly (4x doc = %.1fx cost)", factor))
}

// MARK: - Store

func testStore() {
    let folder = tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let store = NoteStore(folder: folder)
    let note = store.createNote()
    eq(store.notes.count, 1, "note created")
    note.body = "# Notatka testowa\n\ntreść"
    store.writeNow(note)
    check(FileManager.default.fileExists(atPath: note.url.path), "file written")
    eq(note.url.lastPathComponent, "notatka-testowa.md", "file named from title")

    let reopened = NoteStore(folder: folder)
    reopened.reload()
    eq(reopened.notes.count, 1, "reload finds note")
    eq(reopened.notes[0].title, "Notatka testowa", "reload title")
    eq(reopened.notes[0].body, "# Notatka testowa\n\ntreść", "reload body")
    eq(reopened.notes[0].meta.pinned, false, "reload pinned flag")

    // pin / trash / restore
    let folder2 = tempFolder()
    defer { try? FileManager.default.removeItem(at: folder2) }
    let s2 = NoteStore(folder: folder2)
    let a = s2.createNote(body: "# Alpha\n")
    _ = s2.createNote(body: "# Beta\n")
    s2.togglePinned(a)
    eq(s2.notes.first?.title, "Alpha", "pinned note first")
    eq(s2.notes.first?.isPinned, true, "pinned flag set")
    s2.trash(a)
    eq(s2.notes.count, 1, "trashed note removed from list")
    eq(s2.notes[0].title, "Beta", "remaining note")
    let trashed = s2.trashedNotes()
    eq(trashed.count, 1, "one file in .trash")
    s2.restore(fromTrash: trashed[0])
    eq(s2.notes.count, 2, "restore brings note back")
    check(s2.notes.contains { $0.title == "Alpha" }, "restored note present")

    // search
    let folder3 = tempFolder()
    defer { try? FileManager.default.removeItem(at: folder3) }
    let s3 = NoteStore(folder: folder3)
    _ = s3.createNote(body: "# Zażółć Gęślą\n")
    _ = s3.createNote(body: "# inne\n")
    eq(s3.search("zazolc").count, 1, "search ignores diacritics")
    eq(s3.search("GESL").count, 1, "search ignores case")
    eq(s3.search("").count, 2, "empty query returns all")

    // external file
    let folder4 = tempFolder()
    defer { try? FileManager.default.removeItem(at: folder4) }
    try? "# Ręczny\n\nz dysku\n".write(to: folder4.appendingPathComponent("reczny.md"), atomically: true, encoding: .utf8)
    let s4 = NoteStore(folder: folder4)
    s4.reload()
    eq(s4.notes.count, 1, "external file picked up")
    eq(s4.notes[0].title, "Ręczny", "external file title")

    // rename keeps one file per note
    let folder5 = tempFolder()
    defer { try? FileManager.default.removeItem(at: folder5) }
    let s5 = NoteStore(folder: folder5)
    let renamed = s5.createNote()
    renamed.body = "# Pierwsza nazwa\n"
    s5.writeNow(renamed)
    let firstURL = renamed.url
    renamed.body = "# Druga nazwa\n"
    s5.writeNow(renamed)
    check(renamed.url != firstURL, "note file renamed after title change")
    check(!FileManager.default.fileExists(atPath: firstURL.path), "old file gone")
    check(FileManager.default.fileExists(atPath: renamed.url.path), "new file exists")
    eq(s5.notes.count, 1, "still one note")

    func fileText(_ url: URL) -> String {
        (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // Looking at a note must not change the file. This was a real bug: hiding the panel called
    // flushAll(), which rewrote and renamed every note in the folder.
    let folder6 = tempFolder()
    defer { try? FileManager.default.removeItem(at: folder6) }
    let importedURL = folder6.appendingPathComponent("moja-notatka.md")
    let importedText = "# Moja notatka\n\nTekst z **pogrubieniem**.\n"
    try? importedText.write(to: importedURL, atomically: true, encoding: .utf8)
    let s6 = NoteStore(folder: folder6)
    s6.reload()
    s6.flushAll()
    eq(fileText(importedURL), importedText, "an untouched note stays byte-identical")
    eq(s6.notes.count, 1, "untouched note still listed")

    // Editing it writes frontmatter — but never a `title` that repeats the first body line.
    s6.notes[0].body = "# Moja notatka\n\nTekst z **pogrubieniem**.\n\nNowy akapit.\n"
    s6.flush(s6.notes[0])
    let rewritten = fileText(importedURL)
    check(rewritten.hasPrefix("---\n"), "an edited note gains frontmatter")
    check(!rewritten.contains("title:"), "frontmatter does not duplicate the body title")
    eq(s6.notes[0].url.lastPathComponent, "moja-notatka.md", "filename already matches the title")
    eq(s6.notes[0].title, "Moja notatka", "title still read from the body")
    eq(s6.notes[0].body, "# Moja notatka\n\nTekst z **pogrubieniem**.\n\nNowy akapit.\n", "body round-trips")

    // A retitled note moves to the matching filename, and leaves nothing behind.
    let before = s6.notes[0].url
    s6.notes[0].body = "# Inny tytuł\n\ntreść\n"
    s6.flush(s6.notes[0])
    eq(s6.notes[0].url.lastPathComponent, "inny-tytul.md", "filename follows the new title")
    check(!FileManager.default.fileExists(atPath: before.path), "old filename is gone")
    check(fileText(s6.notes[0].url).contains("treść"), "renamed file holds the content")

    // A title that lives only in frontmatter must survive a rewrite.
    let folder7 = tempFolder()
    defer { try? FileManager.default.removeItem(at: folder7) }
    let fmOnly = folder7.appendingPathComponent("tylko-frontmatter.md")
    try? "---\ntitle: Tylko z frontmatter\n---\n".write(to: fmOnly, atomically: true, encoding: .utf8)
    let s7 = NoteStore(folder: folder7)
    s7.reload()
    eq(s7.notes[0].title, "Tylko z frontmatter", "title falls back to frontmatter")
    s7.flush(s7.notes[0])
    check(fileText(s7.notes[0].url).contains("title: Tylko z frontmatter"),
          "frontmatter-only title survives a rewrite")

    // flushAll writes the notes with pending edits, and only those.
    let folder8 = tempFolder()
    defer { try? FileManager.default.removeItem(at: folder8) }
    let bystanderURL = folder8.appendingPathComponent("obok.md")
    let bystanderText = "# Obok\n\n- jedno\n"
    try? bystanderText.write(to: bystanderURL, atomically: true, encoding: .utf8)
    let s8 = NoteStore(folder: folder8)
    s8.reload()
    let edited = s8.createNote(title: "Zmieniona", body: "# Zmieniona\n\ntreść\n")
    edited.body = "# Zmieniona\n\ninna treść\n"
    s8.scheduleSave(edited)
    check(s8.hasPendingSaves, "pending save registered")
    s8.flushAll()
    check(fileText(edited.url).contains("inna treść"), "flushAll writes the pending note")
    check(!s8.hasPendingSaves, "pending save cleared")
    eq(fileText(bystanderURL), bystanderText, "flushAll leaves the other notes alone")
}

// MARK: - Export

func testExport() {
    let plain = Exporter.plainText("# Title\n\n**bold** and [link](https://x.com)\n\n- [x] task\n")
    check(plain.contains("# Title"), "plaintext keeps heading text")
    check(plain.contains("bold"), "plaintext keeps bold text")
    check(!plain.contains("**"), "plaintext strips markers")
    check(plain.contains("[x] task"), "plaintext keeps checkbox")

    let note = Note(url: URL(fileURLWithPath: "/tmp/x.md"), meta: Frontmatter(), body: "# T\n\n**b** `c`\n")
    let html = Exporter.html(note)
    check(html.contains("<h1>T</h1>"), "html heading")
    check(html.contains("<strong>b</strong>"), "html strong")
    check(html.contains("<code>c</code>"), "html inline code")
}

// MARK: - Editor commands (pure transformations)

func testEditorCommands() {
    eq(EditorCommands.toggleInlineMarkers("some text", selection: NSRange(location: 0, length: 4), marker: "**"), "**some** text", "bold wraps selection")
    eq(EditorCommands.toggleInlineMarkers("**some** text", selection: NSRange(location: 2, length: 4), marker: "**"), "some text", "bold unwraps selection")
    eq(EditorCommands.toggleInlineMarkers("ab", selection: NSRange(location: 1, length: 0), marker: "`"), "a``b", "empty selection inserts pair")
    eq(EditorCommands.insertLink("see here now", selection: NSRange(location: 4, length: 4), url: "https://x.com"), "see [here](https://x.com) now", "link wraps selection")
    eq(EditorCommands.insertLink("", selection: NSRange(location: 0, length: 0), url: "https://x.com"), "[https://x.com](https://x.com)", "link with no selection")

    eq(EditorCommands.applyBlock("plain line", lineIndex: 0, kind: .heading1), "# plain line", "heading 1 applied")
    eq(EditorCommands.applyBlock("# plain line", lineIndex: 0, kind: .heading1), "plain line", "heading 1 toggled off")
    eq(EditorCommands.applyBlock("### deep", lineIndex: 0, kind: .heading1), "# deep", "heading 1 replaces heading 3")
    eq(EditorCommands.applyBlock("text", lineIndex: 0, kind: .blockquote), "> text", "blockquote applied")
    eq(EditorCommands.applyBlock("> text", lineIndex: 0, kind: .blockquote), "text", "blockquote toggled off")
    eq(EditorCommands.applyBlock("text", lineIndex: 0, kind: .bulletList), "- text", "bullet applied")
    eq(EditorCommands.applyBlock("- text", lineIndex: 0, kind: .bulletList), "text", "bullet toggled off")
    eq(EditorCommands.applyBlock("text", lineIndex: 0, kind: .orderedList), "1. text", "ordered applied")
    eq(EditorCommands.applyBlock("text", lineIndex: 0, kind: .taskList), "- [ ] text", "task list applied")
    eq(EditorCommands.applyBlock("text", lineIndex: 0, kind: .codeBlock), "```\ntext\n```\n", "code block applied")
    eq(EditorCommands.applyBlock("```\ntext\n```\n", lineIndex: 0, kind: .codeBlock), "text\n", "code block toggled off")

    eq(EditorCommands.applyBlock("one\ntwo\ntwo", lineIndexes: 0..<3, kind: .bulletList), "- one\n- two\n- two", "multi-line bullet")
    eq(EditorCommands.applyBlock("1. one\n2. two", lineIndexes: 0..<2, kind: .orderedList), "one\ntwo", "multi-line ordered toggled off")

    eq(EditorCommands.toggleTask("- buy milk"), "- [ ] buy milk", "task created")
    eq(EditorCommands.toggleTask("- [ ] buy milk"), "- [x] buy milk", "task checked")
    eq(EditorCommands.toggleTask("- [x] buy milk"), "- [ ] buy milk", "task unchecked")
    eq(EditorCommands.toggleTask("- [ ] a\n- [ ] b"), "- [x] a\n- [ ] b", "checkbox toggled on first line only")
    eq(EditorCommands.toggleCheckbox("- [ ] buy milk", markerRange: 2..<5), "- [x] buy milk", "toggleCheckbox by marker range")

    eq(EditorCommands.InputRule.normalize(lineBeforeSpace: "#"), "# ", "space after # normalizes heading")
    eq(EditorCommands.InputRule.normalize(lineBeforeSpace: "###"), "### ", "space after ### normalizes heading")
    eq(EditorCommands.InputRule.normalize(lineBeforeSpace: "-"), "- ", "space after - normalizes bullet")
    eq(EditorCommands.InputRule.normalize(lineBeforeSpace: "[]"), "[ ] ", "task marker normalized")
    eq(EditorCommands.InputRule.normalize(lineBeforeSpace: "1."), "1. ", "space after 1. normalizes ordered list")
    eq(EditorCommands.InputRule.normalize(lineBeforeSpace: ">"), "> ", "space after > normalizes quote")
    eq(EditorCommands.InputRule.normalize(lineBeforeSpace: "```"), "``` ", "space after fence normalizes")
    check(EditorCommands.InputRule.normalize(lineBeforeSpace: "hello") == nil, "no rule for plain word")
    eq(EditorCommands.InputRule.thematicBreak(lineBeforeSpace: "---"), "--- ", "three dashes make a rule")

    let cont = EditorCommands.InputRule.continuation(raw: "- item", caret: 6)
    eq(cont?.raw, "- item\n- ", "return continues bullet")
    eq(cont?.caret, 9, "caret after continued bullet")
    let contTask = EditorCommands.InputRule.continuation(raw: "- [x] done", caret: 11)
    eq(contTask?.raw, "- [x] done\n- [ ] ", "return continues task with unchecked box")
    let contOrdered = EditorCommands.InputRule.continuation(raw: "3. item", caret: 8)
    eq(contOrdered?.raw, "3. item\n4. ", "return increments ordered list")
    let exitList = EditorCommands.InputRule.continuation(raw: "- ", caret: 2)
    eq(exitList?.raw, "", "return on empty item leaves the list")
    check(EditorCommands.InputRule.continuation(raw: "plain text", caret: 10) == nil, "return in paragraph does nothing special")

    eq(EditorCommands.InputRule.changeIndent(raw: "- item", caret: 3, increase: true), "  - item", "tab indents list item")
    eq(EditorCommands.InputRule.changeIndent(raw: "  - item", caret: 5, increase: false), "- item", "shift-tab outdents list item")
    eq(EditorCommands.InputRule.changeIndent(raw: "plain", caret: 2, increase: true), "plain", "tab does nothing outside blocks")
}

// MARK: - emoji picker

func testEmoji() {
    let all = EmojiCatalog.all
    check(all.count >= 150, "emoji catalogue is a real list (\(all.count) entries)")

    var seen = Set<String>()
    var duplicates: [String] = []
    for emoji in all where !seen.insert(emoji.char).inserted {
        duplicates.append(emoji.char)
    }
    check(duplicates.isEmpty, "no emoji appears twice in the catalogue (found \(duplicates.joined()))")

    let malformed = all.filter { $0.char.count != 1 }
    check(malformed.isEmpty, "every entry is exactly one grapheme (found \(malformed.map(\.char).joined()))")

    // Search compares the query against the stored keywords, so the two must agree on folding.
    let unfolded = all.filter { $0.keywords != TextFold.fold($0.keywords) }
    check(unfolded.isEmpty, "keywords are stored folded, just like the query that looks for them")

    eq(EmojiCatalog.search("").count, EmojiCatalog.pageSize, "an empty query fills exactly one page")

    eq(EmojiCatalog.search("serce").first?.char, "❤️", "serce finds the red heart first")
    eq(EmojiCatalog.search("serc").first?.char, "❤️", "a partial word still finds the red heart")
    eq(EmojiCatalog.search("serce czarne").first?.char, "🖤", "two words narrow it to the black heart")
    eq(EmojiCatalog.search("uśmiech").first?.char, "😀", "uśmiech finds the grinning face")
    eq(EmojiCatalog.search("usmiech").first?.char, EmojiCatalog.search("uśmiech").first?.char,
       "the same query without diacritics picks the same emoji")
    eq(EmojiCatalog.search("kawa").first?.char, "☕", "kawa finds the coffee")
    eq(EmojiCatalog.search("kot").first?.char, "🐱", "kot finds the cat rather than a grinning cat face")
    eq(EmojiCatalog.search("laptop").first?.char, "💻", "laptop finds the laptop")
    eq(EmojiCatalog.search("zadne-takie-slowo").count, 0, "a query that matches nothing returns nothing")
    eq(EmojiCatalog.search("serce", limit: 3).count, 3, "the page limit is honoured")
    eq(EmojiCatalog.search("serce").map(\.char), EmojiCatalog.search("serce").map(\.char),
       "search is deterministic across calls")
}

// MARK: - emoji trigger

func testEmojiTrigger() {
    eq(EmojiTrigger.query(in: ":", caret: 1), "", "a bare colon is a trigger with an empty query")
    eq(EmojiTrigger.query(in: ":ser", caret: 4), "ser", "the query is what follows the colon")
    eq(EmojiTrigger.query(in: "notatka\n:kot", caret: 12), "kot", "a colon on any line triggers")

    check(EmojiTrigger.query(in: ": ser", caret: 5) == nil, "a colon followed by a space is prose")
    check(EmojiTrigger.query(in: "::x", caret: 3) == nil, "a double colon is prose")
    check(EmojiTrigger.query(in: "tekst: ser", caret: 6) == nil, "a colon mid-line is prose")
    check(EmojiTrigger.query(in: ":ser", caret: 2) == nil, "a caret inside the query does not trigger")
    check(EmojiTrigger.query(in: "", caret: 0) == nil, "an empty note has no trigger")
    check(EmojiTrigger.query(in: "abc", caret: 3) == nil, "plain text has no trigger")
    check(EmojiTrigger.query(in: "x", caret: 99) == nil, "a caret past the end has no trigger")

    let trigger = EmojiTrigger.range(in: ":ser", caret: 4)
    eq(trigger?.location, 0, "the trigger range starts at the colon")
    eq(trigger?.length, 4, "the trigger range covers the colon and the query typed after it")

    let inserted = EmojiTrigger.insert("❤️", in: ":ser", caret: 4)
    eq(inserted?.raw, "❤️", "picking replaces the whole trigger, not only the colon")
    eq(inserted?.caret, 2, "the caret lands behind the two-unit heart")

    let scoped = EmojiTrigger.insert("😀", in: "notatka\n:ser", caret: 12)
    eq(scoped?.raw, "notatka\n😀", "only the trigger line is touched")
    eq(scoped?.caret, 10, "the caret keeps its place relative to the line start")

    check(EmojiTrigger.insert("😀", in: "bez triggera", caret: 4) == nil, "nothing happens without a trigger")
}

// MARK: - run

if CommandLine.arguments.contains("debug") {
    runDebug()
    exit(0)
}
if CommandLine.arguments.contains("profile") {
    profile()
    exit(0)
}

let started = Date()
testFrontmatter()
testSlug()
testParser()
testRenderer()
testStore()
testExport()
testEditorCommands()
testEmoji()
testEmojiTrigger()

let elapsed = Date().timeIntervalSince(started)
if failures.isEmpty {
    print("✅ \(totalChecks) checks passed in \(String(format: "%.2f", elapsed))s")
    exit(0)
} else {
    print("❌ \(failures.count)/\(totalChecks) checks failed:")
    for f in failures { print("   - \(f)") }
    exit(1)
}