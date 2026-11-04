#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Command Tab.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="$ROOT/icon/android-chrome-512x512.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SIGNING_IDENTITY="2ED0AA003671554164365D5204DE3996AB3F9F1E"

rm -rf "$APP" "$ICONSET"
mkdir -p "$MACOS" "$RESOURCES" "$ICONSET"
cp "$ROOT/CommandTab/App/Info.plist" "$CONTENTS/Info.plist"

cp "$ROOT/icon/favicon-16x16.png" "$ICONSET/icon_16x16.png"
cp "$ROOT/icon/favicon-32x32.png" "$ICONSET/icon_16x16@2x.png"
cp "$ROOT/icon/favicon-32x32.png" "$ICONSET/icon_32x32.png"
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET/icon_256x256@2x.png"
cp "$ICON_SOURCE" "$ICONSET/icon_512x512.png"
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
rm -rf "$ICONSET"
SOURCES=($(find "$ROOT/CommandTab" -name '*.swift' | sort))
xcrun swiftc \
  -swift-version 5 \
  -O \
  -target arm64-apple-macos15.0 \
  -sdk "$SDK" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -framework CoreGraphics \
  -framework ScreenCaptureKit \
  -framework UniformTypeIdentifiers \
  "${SOURCES[@]}" \
  -o "$MACOS/CommandTab"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP" >/dev/null
printf '%s\n' "$APP"
