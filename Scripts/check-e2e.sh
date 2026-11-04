#!/bin/bash
# Drives the real app with real keystrokes and mouse drags. See Tests/E2E/main.swift.
# Uses a temporary notes folder and its own defaults domain, so it cannot touch real notes.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-release}"
swift build -c "$MODE" --product NotesMini
BIN_DIR="$(swift build -c "$MODE" --show-bin-path)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notesmini-e2e.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"; defaults delete NotesMini >/dev/null 2>&1 || true' EXIT
defaults delete NotesMini >/dev/null 2>&1 || true
mkdir -p "$TEMP_DIR/notes"
swiftc -swift-version 5 Tests/E2E/main.swift -o "$TEMP_DIR/e2e"
"$TEMP_DIR/e2e" "$BIN_DIR/NotesMini" "$TEMP_DIR/notes"
