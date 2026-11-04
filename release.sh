#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
RELEASE_DIR="$BUILD_DIR/releases"
APP="$BUILD_DIR/Command Tab.app"
SOURCE_PLIST="$ROOT/CommandTab/App/Info.plist"

fail() { print -u2 -- "FAIL: $*"; exit 1; }

# Explicit credentials and identity are mandatory; do not discover an arbitrary first match.
DEVELOPER_ID="${DEVELOPER_ID-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE-}"
[[ "$DEVELOPER_ID" == "Developer ID Application:"* ]] ||
  fail 'DEVELOPER_ID must be an explicit Developer ID Application certificate name.'
[[ -n "$NOTARY_KEYCHAIN_PROFILE" ]] ||
  fail 'Set NOTARY_KEYCHAIN_PROFILE to an existing notarytool keychain profile.'
[[ "$DEVELOPER_ID" != *$'\n'* && "$DEVELOPER_ID" != *$'\r'* ]] ||
  fail 'Invalid DEVELOPER_ID.'
[[ "$NOTARY_KEYCHAIN_PROFILE" != *$'\n'* && "$NOTARY_KEYCHAIN_PROFILE" != *$'\r'* ]] ||
  fail 'Invalid NOTARY_KEYCHAIN_PROFILE.'
[[ ! -L "$BUILD_DIR" && ! -L "$RELEASE_DIR" && ! -L "$APP" ]] ||
  fail 'Release paths must not traverse symlinks.'

for tool in security codesign xcrun ditto spctl shasum unzip; do
  command -v "$tool" >/dev/null || fail "Required tool unavailable: $tool"
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST")" ||
  fail 'Unable to read source version.'
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_PLIST")" ||
  fail 'Unable to read build number.'
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$BUILD_NUMBER" =~ '^[0-9]+$' ]] ||
  fail 'Invalid application version metadata.'
ZIP_NAME="Command-Tab-${VERSION}-macOS-arm64.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
[[ ! -e "$ZIP_PATH" && ! -L "$ZIP_PATH" ]] ||
  fail "Existing release artifact must not be overwritten: $ZIP_PATH"

# Exactly one valid identity of the requested name must exist. Use its unique SHA for codesign.
VALID_IDENTITIES="$(security find-identity -v -p codesigning)" ||
  fail 'Unable to validate Developer ID identity.'
IDENTITY_HASH="$(print -r -- "$VALID_IDENTITIES" | /usr/bin/awk -F '"' -v identity="$DEVELOPER_ID" '
  NF >= 3 && $2 == identity {
    sub(/[[:space:]]+$/, "", $1)
    n = split($1, fields, /[[:space:]]+/)
    print fields[n]
  }
')" || fail 'Unable to parse code-signing identities.'
[[ -n "$IDENTITY_HASH" && "$IDENTITY_HASH" != *$'\n'* &&
   "$IDENTITY_HASH" =~ '^[0-9a-fA-F]{40}$' ]] ||
  fail 'Developer ID identity not found, invalid or ambiguous; select a unique identity.'

# No externally visible release artifact exists until every validation succeeds.
SIGNING_IDENTITY="$IDENTITY_HASH" "$ROOT/build.sh"
[[ -d "$APP" && ! -L "$APP" && -f "$APP/Contents/MacOS/CommandTab" ]] ||
  fail 'Build did not produce the expected application.'
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILT_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" && "$BUILT_NUMBER" == "$BUILD_NUMBER" ]] ||
  fail 'Built bundle version differs from source.'

# Re-sign the local development build for distribution using the same exact Developer ID.
codesign --force --options runtime --timestamp --sign "$IDENTITY_HASH" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$RELEASE_DIR"
WORK_DIR="$(mktemp -d "$BUILD_DIR/.release.XXXXXXXX")" ||
  fail 'Cannot allocate temporary release workspace.'
cleanup() { [[ -n "${WORK_DIR-}" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto -c -k --keepParent "$APP" "$WORK_DIR/notarize.zip"
xcrun notarytool submit "$WORK_DIR/notarize.zip" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait --output-format json \
  > "$WORK_DIR/notary-result.json"
NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - "$WORK_DIR/notary-result.json")" ||
  fail 'Notarization response could not be parsed.'
[[ "$NOTARY_STATUS" == "Accepted" ]] ||
  fail "Notarization status is not Accepted: $NOTARY_STATUS"

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute -vv "$APP"

# Final archive contains the stapled app; publish atomically, without replacing prior output.
ditto -c -k --keepParent "$APP" "$WORK_DIR/$ZIP_NAME"
[[ -s "$WORK_DIR/$ZIP_NAME" && ! -e "$ZIP_PATH" && ! -L "$ZIP_PATH" ]] ||
  fail 'Final archive missing or release destination already occupied.'
unzip -tqq "$WORK_DIR/$ZIP_NAME" || fail 'Final ZIP failed integrity validation.'
mv -n "$WORK_DIR/$ZIP_NAME" "$ZIP_PATH"
[[ ! -e "$WORK_DIR/$ZIP_NAME" ]] || fail 'Release destination became occupied before publish.'
print -r -- "Verified release archive: $ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
