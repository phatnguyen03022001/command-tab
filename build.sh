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

# Callers must select the intended certificate; never use a developer-specific default.
SIGNING_IDENTITY="${SIGNING_IDENTITY-}"
if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
  print -u2 'FAIL: Set SIGNING_IDENTITY to an explicit, non-ad-hoc code-signing identity.'
  exit 1
fi
if [[ "$SIGNING_IDENTITY" == *$'\n'* || "$SIGNING_IDENTITY" == *$'\r'* ]]; then
  print -u2 'FAIL: Invalid SIGNING_IDENTITY.'
  exit 1
fi
if [[ -L "$BUILD_DIR" || -L "$APP" || -L "$ICONSET" ]]; then
  print -u2 'FAIL: Build output must not traverse symlinks.'
  exit 1
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
rm -rf "$APP" "$ICONSET"
mkdir -p "$MACOS" "$RESOURCES" "$ICONSET" "$BUILD_DIR/swift-cache"
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

# Native zsh recursive glob preserves paths containing spaces.
SOURCES=("$ROOT"/CommandTab/**/*.swift(N))
if (( ${#SOURCES[@]} == 0 )); then
  print -u2 'FAIL: No Swift production sources found.'
  exit 1
fi
xcrun swiftc \
  -swift-version 5 \
  -O \
  -module-cache-path "$BUILD_DIR/swift-cache" \
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
codesign --verify --deep --strict "$APP"
print -r -- "$APP"
