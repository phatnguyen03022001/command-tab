#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/CommandTab"
ADAPTER="$APP/Windows/SpaceIdentityAdapter.swift"

if grep -R -n --include='*.swift' '\.activateAllWindows' "$APP"; then
  echo 'FAIL: activateAllWindows must be completely absent' >&2
  exit 1
fi

if grep -R -n --include='*.swift' 'CGSSet\|SLSSet\|SLS[A-Za-z0-9_]*' "$APP"; then
  echo 'FAIL: private Space mutation/SLS API detected' >&2
  exit 1
fi

private_files=($(grep -R -l --include='*.swift' 'CGS[A-Z][A-Za-z0-9_]*' "$APP" || true))
if (( ${#private_files[@]} != 1 )) || [[ "${private_files[1]:-}" != "$ADAPTER" ]]; then
  print -u2 'FAIL: CGS private API must be isolated to SpaceIdentityAdapter.swift'
  printf '%s\n' "${private_files[@]:-}" >&2
  exit 1
fi

symbols=($(grep -o 'CGS[A-Z][A-Za-z0-9_]*' "$ADAPTER" | sort -u))
expected=(CGSCopySpacesForWindows CGSMainConnectionID CGSManagedDisplayGetCurrentSpace)
if [[ "${(j: :)symbols}" != "${(j: :)expected}" ]]; then
  print -u2 "FAIL: unexpected CGS symbols: ${(j: :)symbols}"
  exit 1
fi

if grep -R -n --include='*.swift' 'public-fallback\|case fallback' "$APP"; then
  echo 'FAIL: public title/frame focus fallback must be absent' >&2
  exit 1
fi

HOTKEY="$APP/Input/HotKeyEventTap.swift"

if grep -R -n --include='*.swift' 'Process[[:space:]]*(\|NSTask\|/bin/sh\|/usr/bin/open\|open -a ' "$APP"; then
  echo 'FAIL: shell/subprocess quick-launch implementation detected' >&2
  exit 1
fi

if (( $(grep -R -h --include='*.swift' 'CGEvent\.tapCreate' "$APP" | wc -l | tr -d ' ') != 1 )); then
  echo 'FAIL: production must keep exactly one CGEvent tap' >&2
  exit 1
fi

if ! grep -q 'QuickLaunchShortcutPolicy\.slot' "$HOTKEY"; then
  echo 'FAIL: existing event tap is not routing quick-launch shortcuts through policy' >&2
  exit 1
fi

if ! grep -q 'keyboardEventAutorepeat' "$HOTKEY"; then
  echo 'FAIL: quick launch must explicitly handle key repeat' >&2
  exit 1
fi

print 'SourcePolicyTests passed'
