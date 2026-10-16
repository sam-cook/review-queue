#!/bin/bash
# Builds "Review Queue.app" (universal: Apple silicon + Intel) into ./dist.
# Needs only the Xcode Command Line Tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Review Queue"
EXE="ReviewQueue"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="dist/$NAME.app"

for arch in arm64 x86_64; do
  echo "Building ${arch}..."
  swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path ".build/$arch" --product "$EXE" >/dev/null
done

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun lipo -create ".build/arm64/release/$EXE" ".build/x86_64/release/$EXE" -output "$APP/Contents/MacOS/$EXE"
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
# Ad-hoc signature: enough to run locally and for login items; not notarised.
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
