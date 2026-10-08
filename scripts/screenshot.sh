#!/bin/sh
# Renders docs/screenshot-light.png and docs/screenshot-dark.png from the real app views.
# It compiles the app's sources with scripts/screenshot.swift in place of the @main file,
# into an app with its own bundle ID, so the real app's settings stay untouched.
# The name, bundle ID and deployment target come from project.yml.
# Usage: scripts/screenshot.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
NAME="Number Pantry"
TARGET="Calculum"
BUNDLE_ID=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *//p' project.yml | head -1).screenshot
MACOS=$(sed -n 's/^ *macOS: *"\(.*\)"$/\1/p' project.yml | head -1)
APP="$ROOT/build/screenshot/$NAME Screenshot.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" docs
find "$TARGET" -name '*.swift' ! -exec grep -q '^@main' {} \; -exec \
  swiftc -O -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macos$MACOS" \
  -o "$APP/Contents/MacOS/Screenshot" scripts/screenshot.swift {} +

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Screenshot</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
open -g -n "$APP" --args "$ROOT/docs" -AppleLocale en_US -AppleLanguages '(en)'
sleep 1
while pgrep -f "$NAME Screenshot.app/Contents/MacOS" >/dev/null; do sleep 1; done
ls -la docs/*.png
