#!/usr/bin/env bash
# Build LubbyBar.app from the Swift package. No Xcode project needed: compile
# the executable with SwiftPM, then assemble a minimal .app bundle (LSUIElement
# so it lives only in the menu bar).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="LubbyBar"
BUNDLE_ID="tech.lubby.bar"
VERSION="${LUBBY_BAR_VERSION:-0.1.0}"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
APP_DIR="build/$APP_NAME.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>           <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>    <string>Lubby Bar</string>
    <key>CFBundleExecutable</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>     <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>    <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>        <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key> <string>13.0</string>
    <key>LSUIElement</key>            <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "Built $APP_DIR"
