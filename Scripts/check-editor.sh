#!/bin/bash
# Exercise the real AppKit editor without opening or changing the user's notes.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-debug}"
swift build -c "$MODE"
BIN_DIR="$(swift build -c "$MODE" --show-bin-path)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notesmini-editor-checks.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
SOURCES=()
for source in Sources/NotesMini/*.swift; do
    [[ "$source" == Sources/NotesMini/main.swift ]] || SOURCES+=("$source")
done
swiftc -swift-version 5 -O -I "$BIN_DIR/Modules" \
    "${SOURCES[@]}" Tests/EditorChecks/main.swift \
    "$BIN_DIR"/NotesMiniCore.build/*.swift.o -o "$TEMP_DIR/checks"
"$TEMP_DIR/checks"
