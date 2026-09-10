#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Command Tab.app"
DEST="/Applications/Command Tab.app"
OLD_DEST="/Applications/CommandTab.app"

if [[ ! -d "$APP" ]]; then
  "$ROOT/build.sh" >/dev/null
fi

rm -rf "$DEST"
ditto "$APP" "$DEST"
codesign --verify --deep --strict "$DEST"

if [[ "$OLD_DEST" != "$DEST" && -d "$OLD_DEST" ]]; then
  rm -rf "$OLD_DEST"
fi

printf '%s\n' "$DEST"
