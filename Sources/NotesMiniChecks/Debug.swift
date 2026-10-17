import AppKit
import Foundation
import NotesMiniCore

/// `swift run NotesMiniChecks debug` prints intermediate renderer state for eyeballing.
func runDebug() {
    let text = """
    ---
    title: Spotkanie z Petrem
    pinned: true
    ---

    # Spotkanie
    body
    """
    let (fm, body) = Frontmatter.parse(text)
    print("frontmatter title=\(String(describing: fm.title)) body=\(body.debugDescription)")

    let raw = "# Title\n\n- [ ] task\n\ntext with `code` and **bold**\n"
    let r = NoteRenderer.render(raw)
    print("display=\(r.display.string.debugDescription)")

    let mapRaw = "# Title\n\n- item **one**\n- [ ] task item\n\n```\nlet a = 1\n```\n\ntext with `code`\n"
    let mr = NoteRenderer.render(mapRaw)
    print("map display=\(mr.display.string.debugDescription)")
    print("map blocks=\(mr.blocks.map { "\($0.kind) raw\($0.rawRange) disp\($0.displayRange)" })")
    print("raw around 18..40=\((mapRaw as NSString).substring(with: NSRange(location: 18, length: 20)).debugDescription)")
    print("r2d=\(mr.rawToDisplay)")

    let layoutRaw = "# A\n\n\ntext\n\n- x\n- y\n\n```\ncode\n```\n\nend\n"
    let lr = NoteRenderer.render(layoutRaw)
    print("layout display lines=\(lr.display.string.components(separatedBy: "\n").count) raw lines=\((layoutRaw as NSString).components(separatedBy: "\n").count)")
    print("layout display=\(lr.display.string.debugDescription)")
    print("layout blocks=\(lr.blocks.map { "\($0.kind) raw\($0.rawRange) disp\($0.displayRange)" })")
    print("layout raw=\(layoutRaw.debugDescription)")

    let fence = "```\ntext\n```\n"
    print("fence off=\(EditorCommands.applyBlock(fence, lineIndex: 0, kind: .codeBlock).debugDescription)")
    let li = LineIndex(fence)
    print("fence starts=\(li.starts) count=\(li.count) len=\(li.length)")

    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notesmini-dbg-\(UUID().uuidString)")
    let store = NoteStore(folder: folder)
    let a = store.createNote(body: "# Alpha\n")
    _ = store.createNote(body: "# Beta\n")
    store.togglePinned(a)
    store.trash(a)
    print("after trash notes=\(store.notes.map { $0.title })")
    print("trashed=\(store.trashedNotes().map { $0.lastPathComponent })")
    let restored = store.restore(fromTrash: store.trashedNotes()[0])
    print("restored=\(restored?.title ?? "nil") notes=\(store.notes.map { $0.title })")
    print("files=\((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])")
    print("pin order=\(store.notes.map { "\($0.title):\($0.isPinned)" })")
}
func profile() {
    var big = ""
    for i in 0..<600 {
        big += "## Section \(i)\n\nSome **bold** text with `code` and a [link](https://example.com).\n\n- item\n- [ ] task\n\n> quote\n\n```\ncode block\n```\n\n"
    }
    print("doc chars=\(big.utf16.count)")

    func time(_ label: String, _ n: Int, _ body: () -> Void) {
        let t0 = Date()
        for _ in 0..<n { body() }
        print(String(format: "%@ %.2f ms", label, Date().timeIntervalSince(t0) / Double(n) * 1000))
    }

    time("parse only", 10) { _ = MarkdownParser.parse(big) }
    time("full render", 10) { _ = NoteRenderer.render(big) }

    // small, realistic note
    var small = ""
    for i in 0..<12 {
        small += "## Heading \(i)\n\nSome **bold** text with `code`.\n\n- item\n- [ ] task\n\n"
    }
    print("small chars=\(small.utf16.count)")
    time("small render", 50) { _ = NoteRenderer.render(small) }
}
