#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/CommandTab"
ADAPTER="$APP/System/Windowing/SpaceIdentityAdapter.swift"

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

HOTKEY="$APP/System/Input/HotKeyEventTap.swift"
SWITCHER_ITEM="$APP/Features/Switcher/SwitcherItemView.swift"

if grep -q 'selectionFillLayer\.frame' "$SWITCHER_ITEM"; then
  echo 'FAIL: selection must not use manual CALayer frame positioning' >&2
  exit 1
fi

if grep -q 'imageView\.convert(imageView\.bounds, to: self)' "$SWITCHER_ITEM"; then
  echo 'FAIL: selection placement must not depend on imageView coordinate conversion' >&2
  exit 1
fi

if ! grep -q 'iconContainer' "$SWITCHER_ITEM" || ! grep -q 'selectionBackgroundView' "$SWITCHER_ITEM"; then
  echo 'FAIL: selection must be structurally anchored in a dedicated icon container' >&2
  exit 1
fi

if grep -q 'controlAccentColor' "$SWITCHER_ITEM"; then
  echo 'FAIL: selection presentation must not depend on NSColor.controlAccentColor' >&2
  exit 1
fi

if grep -R -n --include='*.swift' 'Process[[:space:]]*(\|NSTask\|/bin/sh\|/usr/bin/open\|open -a ' "$APP"; then
  echo 'FAIL: shell/subprocess quick-launch implementation detected' >&2
  exit 1
fi

if (( $(grep -R -h --include='*.swift' 'CGEvent\.tapCreate' "$APP" | wc -l | tr -d ' ') != 1 )); then
  echo 'FAIL: production must keep exactly one CGEvent tap' >&2
  exit 1
fi

# App owns feature composition; the low-level event tap must not depend on Quick Launch code.
if ! grep -q 'QuickLaunchShortcutPolicy\.slot' "$APP/App/AppDelegate.swift"; then
  echo 'FAIL: application composition must route Quick Launch through its shortcut policy' >&2
  exit 1
fi

if grep -E 'QuickLaunchController|QuickLaunchShortcutPolicy' "$HOTKEY"; then
  echo 'FAIL: System/Input must not depend directly on Quick Launch feature types' >&2
  exit 1
fi

if ! grep -q 'keyboardEventAutorepeat' "$HOTKEY"; then
  echo 'FAIL: quick launch must explicitly handle key repeat' >&2
  exit 1
fi

BUILD_SCRIPT="$ROOT/build.sh"
RELEASE_SCRIPT="$ROOT/release.sh"

if [[ ! -x "$RELEASE_SCRIPT" ]]; then
  echo 'FAIL: release.sh must exist and be executable' >&2
  exit 1
fi

if grep -E '[0-9A-F]{40}' "$BUILD_SCRIPT" "$RELEASE_SCRIPT"; then
  echo 'FAIL: personal certificate fingerprint detected in build/release scripts' >&2
  exit 1
fi

if ! grep -q 'SIGNING_IDENTITY' "$BUILD_SCRIPT"; then
  echo 'FAIL: build.sh must support dynamic or configured SIGNING_IDENTITY' >&2
  exit 1
fi

if ! grep -q 'Developer ID Application' "$RELEASE_SCRIPT"; then
  echo 'FAIL: release tooling must require Developer ID Application' >&2
  exit 1
fi

if ! grep -q -E 'options runtime|--options[ =]runtime' "$RELEASE_SCRIPT"; then
  echo 'FAIL: release tooling must enforce Hardened Runtime' >&2
  exit 1
fi

if ! grep -q -- '--timestamp' "$RELEASE_SCRIPT"; then
  echo 'FAIL: release tooling must enforce secure timestamp' >&2
  exit 1
fi

if grep -q -E -e '--sign[ =]-' "$RELEASE_SCRIPT"; then
  echo 'FAIL: release tooling must not use ad-hoc signing for distribution artifacts' >&2
  exit 1
fi

# All release tests run against a copied script and synthetic command stubs.
# The production release.sh and build.sh are NEVER executed against host signing tools.
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/commandtab-release-tests.XXXXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/CommandTab/App"
cp "$RELEASE_SCRIPT" "$TEST_ROOT/release.sh"
cp "$BUILD_SCRIPT" "$TEST_ROOT/real-build.sh"
cp "$ROOT/CommandTab/App/Info.plist" "$TEST_ROOT/CommandTab/App/Info.plist"

# The real build script must reject missing or ad-hoc identity before doing any work.
for invalid_identity in "" "-"; do
  if env SIGNING_IDENTITY="$invalid_identity" "$TEST_ROOT/real-build.sh" >/dev/null 2>&1; then
    print -u2 "FAIL: build.sh accepted an absent/ad-hoc signing identity"
    exit 1
  fi
  [[ ! -d "$TEST_ROOT/build" ]] || {
    print -u2 "FAIL: build.sh touched outputs before validating identity"
    exit 1
  }
done

cat > "$TEST_ROOT/build.sh" <<'STUB'
#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
print -r -- "build:$SIGNING_IDENTITY" >> "$MOCK_LOG"
mkdir -p "$ROOT/build/Command Tab.app/Contents/MacOS"
cp "$ROOT/CommandTab/App/Info.plist" "$ROOT/build/Command Tab.app/Contents/Info.plist"
print -r -- synthetic > "$ROOT/build/Command Tab.app/Contents/MacOS/CommandTab"
STUB
chmod +x "$TEST_ROOT/build.sh"

cat > "$TEST_ROOT/bin/security" <<'STUB'
#!/bin/zsh
print -r -- 'security:synthetic' >> "$MOCK_LOG"
print '  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Developer ID Application: Synthetic Example (TESTTEAM)"'
if [[ "${MOCK_DUPLICATE_IDENTITY:-0}" == "1" ]]; then
  print '  2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Developer ID Application: Synthetic Example (TESTTEAM)"'
fi
STUB
cat > "$TEST_ROOT/bin/codesign" <<'STUB'
#!/bin/zsh
print -r -- "codesign:$*" >> "$MOCK_LOG"
[[ "${MOCK_FAIL_STAGE:-}" != "codesign" ]]
STUB
cat > "$TEST_ROOT/bin/xcrun" <<'STUB'
#!/bin/zsh
print -r -- "xcrun:$*" >> "$MOCK_LOG"
if [[ "$1" == "notarytool" ]]; then
  [[ "${MOCK_FAIL_STAGE:-}" != "notarytool" ]] || exit 4
  if [[ "${MOCK_FAIL_STAGE:-}" == "notary-rejected" ]]; then
    print '{"status":"Rejected","id":"synthetic"}'
  else
    print '{"status":"Accepted","id":"synthetic"}'
  fi
elif [[ "${MOCK_FAIL_STAGE:-}" == "stapler" ]]; then
  exit 5
fi
STUB
cat > "$TEST_ROOT/bin/ditto" <<'STUB'
#!/bin/zsh
print -r -- "ditto:$*" >> "$MOCK_LOG"
[[ "${MOCK_FAIL_STAGE:-}" != "ditto" ]] || exit 6
if [[ "${MOCK_FAIL_STAGE:-}" == "corrupt-archive" ]]; then
  print -r -- "invalid ZIP data" > "${@[-1]}"
else
  source_path="${@[-2]}"
  archive_path="${@[-1]}"
  ( cd "${source_path:h}" && /usr/bin/zip -qr "$archive_path" "${source_path:t}" )
fi
STUB
cat > "$TEST_ROOT/bin/spctl" <<'STUB'
#!/bin/zsh
print -r -- "spctl:$*" >> "$MOCK_LOG"
[[ "${MOCK_FAIL_STAGE:-}" != "spctl" ]]
STUB
chmod +x "$TEST_ROOT/bin/"*

MOCK_PATH="$TEST_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin"
for tool in security codesign xcrun ditto spctl; do
  [[ "$(PATH="$MOCK_PATH" whence -p "$tool")" == "$TEST_ROOT/bin/$tool" ]] || {
    print -u2 "FAIL: isolated mock not active for $tool"
    exit 1
  }
done
SYNTHETIC_ID='Developer ID Application: Synthetic Example (TESTTEAM)'

run_offline_release() {
  : > "$TEST_ROOT/mock.log"
  rm -rf "$TEST_ROOT/build"
  env PATH="$MOCK_PATH" MOCK_LOG="$TEST_ROOT/mock.log" \
    DEVELOPER_ID="$SYNTHETIC_ID" NOTARY_KEYCHAIN_PROFILE="synthetic-test-profile" \
    "$TEST_ROOT/release.sh" >"$TEST_ROOT/last.stdout" 2>"$TEST_ROOT/last.stderr"
}

expect_release_failure() {
  local reason="$1"
  if run_offline_release; then
    print -u2 "FAIL: release mock accepted failure scenario: $reason"
    exit 1
  fi
  if [[ -d "$TEST_ROOT/build/releases" ]] &&
      [[ -n "$(find "$TEST_ROOT/build/releases" -type f -print -quit)" ]]; then
    print -u2 "FAIL: release failure left a published artifact: $reason"
    exit 1
  fi
}

# Prerequisite failures must occur before probing signing or building anything.
if env PATH="$MOCK_PATH" MOCK_LOG="$TEST_ROOT/mock.log" \
  DEVELOPER_ID='' NOTARY_KEYCHAIN_PROFILE='' \
  "$TEST_ROOT/release.sh" >/dev/null 2>&1; then
  print -u2 'FAIL: release permitted missing signing/notarization configuration'
  exit 1
fi
if env PATH="$MOCK_PATH" MOCK_LOG="$TEST_ROOT/mock.log" \
  DEVELOPER_ID='Apple Development: Synthetic (TESTTEAM)' \
  NOTARY_KEYCHAIN_PROFILE='synthetic-test-profile' \
  "$TEST_ROOT/release.sh" >/dev/null 2>&1; then
  print -u2 'FAIL: release accepted development certificate name'
  exit 1
fi

MOCK_DUPLICATE_IDENTITY=1 expect_release_failure 'duplicate certificate names'
MOCK_FAIL_STAGE=codesign expect_release_failure 'codesign failure'
MOCK_FAIL_STAGE=notarytool expect_release_failure 'notarization submission failure'
MOCK_FAIL_STAGE=notary-rejected expect_release_failure 'notarization rejection with exit zero'
MOCK_FAIL_STAGE=stapler expect_release_failure 'stapler failure'
MOCK_FAIL_STAGE=spctl expect_release_failure 'Gatekeeper failure'
MOCK_FAIL_STAGE=corrupt-archive expect_release_failure 'final ZIP CRC failure'
run_offline_release || { print -u2 'FAIL: synthetic release success path failed'; cat "$TEST_ROOT/last.stderr" >&2; exit 1; }
test_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TEST_ROOT/CommandTab/App/Info.plist")"
EXPECTED_ARCHIVE="$TEST_ROOT/build/releases/Command-Tab-${test_version}-macOS-arm64.zip"
[[ -s "$EXPECTED_ARCHIVE" ]] || { print -u2 'FAIL: synthetic final artifact absent'; exit 1; }
/usr/bin/unzip -tqq "$EXPECTED_ARCHIVE" || { print -u2 'FAIL: synthetic archive invalid'; exit 1; }
archive_hash="$(/usr/bin/shasum -a 256 "$EXPECTED_ARCHIVE")"
if env PATH="$MOCK_PATH" MOCK_LOG="$TEST_ROOT/mock.log" \
  DEVELOPER_ID="$SYNTHETIC_ID" NOTARY_KEYCHAIN_PROFILE="synthetic-test-profile" \
  "$TEST_ROOT/release.sh" >/dev/null 2>&1; then
  print -u2 'FAIL: a preexisting release archive was silently overwritten'
  exit 1
fi
[[ "$(/usr/bin/shasum -a 256 "$EXPECTED_ARCHIVE")" == "$archive_hash" ]] || {
  print -u2 'FAIL: preexisting release artifact changed after rejected retry'
  exit 1
}
grep -q 'codesign:.*--options runtime --timestamp --sign AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' "$TEST_ROOT/mock.log" ||
  { print -u2 'FAIL: Hardened Runtime, timestamp, exact certificate hash missing'; exit 1; }
grep -q 'xcrun:notarytool submit .*--wait --output-format json' "$TEST_ROOT/mock.log" ||
  { print -u2 'FAIL: synchronous notarization not requested'; exit 1; }
grep -q 'xcrun:stapler validate' "$TEST_ROOT/mock.log" ||
  { print -u2 'FAIL: staple validation missing'; exit 1; }
grep -q 'spctl:--assess' "$TEST_ROOT/mock.log" ||
  { print -u2 'FAIL: Gatekeeper assessment missing'; exit 1; }
print 'SourcePolicyTests passed (static checks + isolated mocked release scenarios)'
