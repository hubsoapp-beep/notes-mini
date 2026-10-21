# Notes Mini

An ultra-light floating notes panel for macOS. Summon it with a hotkey from anywhere, type, get
out of the way. Notes are plain Markdown files in a folder you choose — no database, no lock-in, no
cloud.

Built as a single small AppKit app with no third-party dependencies: `swift build` and a script that
assembles the `.app`.

## What it does

- **Always on top.** The panel sits at the overlay window level, above the menu bar and above
  full-screen apps, on every Space.
- **Markdown that stays out of the way.** Bold, italic, underline, strike-through, inline code,
  links, three heading levels, bulleted, numbered and task lists, quotes, code blocks, rules,
  checkboxes — with the markup hidden while you type over it. The file on disk is ordinary Markdown.
  Heading shortcuts wait for a space: `##` stays visible, then `## ` activates H2. At the start
  of a line, `[]`, `[ ]`, `- []`, and `- [ ]` become checkboxes as soon as `]` is typed.
  Return continues a list at the caret, a second Return leaves an empty item, and Backspace
  at the start of formatted content removes its block format. Inline shortcuts stay literal in code blocks.
- **Notes are files.** One `.md` per note, YAML frontmatter, named after the title. Open the folder
  in Obsidian, grep it, sync it with whatever you already use.
- **A command palette** (`⌘P`) to search and switch notes, and an action list (`⌘K`) for everything
  else.
- **An emoji picker** that lives inside the note: type `:` at the start of a line, search, `↩`.
- **Resizable, with real window chrome**: traffic lights, edge resizing, and a green button that
  fills the screen edge to edge and hides itself while it does.
- **Menu bar item**, **launch at login**, **trash folder** instead of deletion.
- **Glass-ish surface** built from the system's own materials.

## Requirements

- macOS 14 or newer
- Command Line Tools (Xcode is not required — everything builds with `swift build`)
- No third-party packages

## Build and run

```sh
Scripts/build.sh            # assembles ./dist/Notes Mini.app
Scripts/build.sh --install  # also copies it to /Applications and launches it
```

The app is an accessory app with no Dock icon. Launching or reopening it shows the notes panel.
It also lives in the menu bar and on the global hotkey, `⌥N` by default.

## Checks

Command Line Tools ships neither XCTest nor swift-testing, so the regression suite is a plain
executable target:

```sh
swift run NotesMiniChecks
swift run -c release NotesMiniChecks
bash Scripts/check-editor.sh release # real NSTextView input, undo, IME, and layout checks
```

It covers the note model and file format, the Markdown parser and the renderer's raw/display
mapping, the store (dirty tracking, renames, trash), the emoji catalogue and trigger, and the
performance budgets for large documents.

## Shortcuts

| | |
|---|---|
| `⌥N` | show / hide the panel |
| `⌘N` | new note |
| `⌘P` | browse and search notes |
| `⌘K` | actions (pin, export, copy, reveal, trash, settings) |
| `⇧⌘P` | pin / unpin |
| `⌘B` `⌘I` `⌘U` `⇧⌘X` `⌘E` | bold, italic, underline, strike, inline code |
| `⌥⌘1..3` | heading levels |
| `⇧⌘7` `⇧⌘8` `⌥⌘9` | task, bulleted, numbered list |
| `⇧⌘'` `⇧⌘9` `⇧⌘-` | quote, code block, rule |
| `⌘⌫` | move the note to trash |
| `⌃⌘F` | fill the screen |
| `Esc` | leave full screen, then hide the panel |

## Note format

```markdown
---
created: 2026-10-17T10:42:37+02:00
updated: 2026-10-19T08:06:12+02:00
pinned: false
---

# A title

Anything Markdown, plus `- [ ]` / `- [x]` tasks.
```

The file name follows the note's first line; a note without a title stays `note.md` until it has one.
Deleted notes go to `.trash/` inside the notes folder.

## How it is put together

| target | what lives there |
|---|---|
| `NotesMiniCore` | Note model, Markdown parser, renderer, store, commands, emoji catalogue. No AppKit. |
| `NotesMini` | The AppKit app: panel, editor, overlays, picker, preferences. |
| `NotesMiniChecks` | The regression suite. |

The renderer keeps the raw Markdown as the source of truth and renders a *display* string with the
markers removed, plus a bidirectional mapping between the two offsets. Typing therefore never edits
Markdown syntax you cannot see.

Settings live in `UserDefaults` under the app's bundle identifier.

## License

MIT — see [LICENSE](LICENSE).
