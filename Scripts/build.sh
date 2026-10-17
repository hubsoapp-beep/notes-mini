#!/bin/bash
# Builds Notes Mini.app: release binary + Info.plist + icon + ad-hoc signature.
#
#   Scripts/build.sh              build into ./dist
#   Scripts/build.sh --install    also copy to /Applications and launch
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Notes Mini"
BUNDLE_ID="pl.milosz.notesmini"
VERSION="1.0"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/NotesMini" "$APP/Contents/MacOS/NotesMini"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>NotesMini</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Accessory app: no Dock icon, the panel and the menu bar item are the whole UI. -->
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Notes Mini</string>
</dict>
</plist>
PLIST

echo "==> icon"
ICON="$DIST/AppIcon.icns"
if [ ! -f "$ICON" ] || [ Scripts/make-icon.swift -nt "$ICON" ]; then
    swift Scripts/make-icon.swift "$DIST/icon.png" >/dev/null
    ICONSET="$DIST/AppIcon.iconset"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512 1024; do
        sips -z $size $size "$DIST/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
    done
    # Retina variants Apple's iconutil expects.
    cp "$ICONSET/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"
    cp "$ICONSET/icon_64x64.png"   "$ICONSET/icon_32x32@2x.png"
    cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
    cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
    cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" -o "$ICON"
    rm -rf "$ICONSET"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

echo "==> codesign (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "==> done: $APP"
du -sh "$APP" | awk '{print "   size: " $1}'

if [ "${1:-}" = "--install" ]; then
    echo "==> installing to /Applications"
    osascript -e 'quit app "Notes Mini"' 2>/dev/null || true
    sleep 0.4
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    echo "==> launching"
    open "/Applications/$APP_NAME.app"
fi
