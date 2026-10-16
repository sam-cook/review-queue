#!/bin/bash
# Builds Review Queue.app (universal: Apple silicon + Intel), installs it to ~/Applications and starts it.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Review Queue"
EXE="ReviewQueue"
APP="$HOME/Applications/$NAME.app"
BUILD="build/$NAME.app"
MIN_MACOS="14.0"

rm -rf build && mkdir -p "$BUILD/Contents/MacOS"
for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" ReviewQueue.swift -o "build/$EXE-$arch"
done
xcrun lipo -create "build/$EXE-arm64" "build/$EXE-x86_64" -output "$BUILD/Contents/MacOS/$EXE"

cat > "$BUILD/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>io.github.sam-cook.review-queue</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$BUILD"

pkill -x "$EXE" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP" && mv "$BUILD" "$APP" && rm -rf build
open "$APP"
echo "Installed $APP"
