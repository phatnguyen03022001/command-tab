# Command Tab

A lightweight, native macOS ⌘Tab switcher scoped strictly to applications and windows in the currently visible Mission Control Desktop context.

## Why Command Tab

The default macOS application switcher surfaces every running application across all Mission Control Spaces. Switching to an app whose windows reside on another Desktop forces macOS to animate across Spaces, breaking your active workspace flow.

Command Tab solves this by restricting the switcher to the current visible Desktop. If an application has windows only on other Spaces, it does not appear in your switcher until you navigate to that Space.

## How it works

Command Tab runs locally as an AppKit menu-bar agent (`LSUIElement`). When you invoke ⌘Tab:

1. **Snapshot**: It captures eligible on-screen windows in WindowServer z-order at session start; the list is reconciled only after an explicit quit/close action.
2. **Space filtering**: It queries exact Space membership using a read-only private API connection and intersects it against the active visible Space(s).
3. **Deduplication / Scoping**: Depending on configured Switcher Mode, it groups windows by PID (one icon per running app) or displays individual windows.
4. **Presentation**: It immediately displays a native Liquid Glass switcher overlay (`NSGlassEffectView` on macOS 26+, `NSVisualEffectView` fallback on macOS 15), reusing pooled views. Windows mode shows small window cards and asynchronously fills their thumbnails when Screen Recording permission was already granted.
5. **Exact focus**: Upon releasing ⌘, it raises and focuses the exact target window via macOS Accessibility (`_AXUIElementGetWindow`). If the target window has moved or closed, it fails closed without substituting arbitrary windows.

## Requirements

- **Runtime requirement**: macOS 15.0 or later on Apple Silicon (`arm64`), with macOS Accessibility permission granted.
- **Source build requirement**: An Apple Silicon Mac with an Xcode toolchain providing a sufficiently recent macOS SDK capable of compiling the macOS 26/27 AppKit APIs used in the source (specifically SDK 27 for `NSViewCornerConfiguration` and `NSGlassEffectView`). Availability guards preserve runtime execution on macOS 15+.

## Install / Build

> [!NOTE]
> This repository supplies source and build tooling, not an approved notarized binary release. Signing requires a local valid certificate; the source build is not an unsigned or ad-hoc path.

### Source / Developer Install (Available Today)

Run the following commands in Terminal:

```sh
git clone https://github.com/phatnguyen03022001/command-tab.git
cd command-tab
SIGNING_IDENTITY="Apple Development: <certificate name> (<team-id>)" ./build.sh
# Optional user-initiated installation (not required for testing):
./install.sh
```

- `./build.sh` requires an explicitly selected `SIGNING_IDENTITY` (full certificate name or unambiguous SHA-1 identity). There is no embedded personal or automatic default. It rejects empty/ad-hoc identity values before touching build outputs, builds `build/Command Tab.app`, signs it for development and verifies the signature. It does **not** notarize.
- `./install.sh` copies the application directly into `/Applications/Command Tab.app`.

### Official Release Artifacts (Distribution Roadmap)

Official binary distribution will be packaged as a signed, notarized archive:
`Command-Tab-<version>-macOS-arm64.zip`

For maintainers producing official distribution releases:
- `./release.sh` requires an explicit `DEVELOPER_ID` certificate name and `NOTARY_KEYCHAIN_PROFILE` created outside this repository. It demands exactly one matching valid Developer ID Application identity, signs with Hardened Runtime (`--options runtime`) and secure timestamp, and submits via `xcrun notarytool --wait`. Only an accepted submission and successful stapling, signature, and Gatekeeper checks produce a versioned archive under `build/releases/`. An existing archive is not overwritten.
- Gatekeeper verification (`spctl --assess --type execute -vv`) and stapling validation (`xcrun stapler validate`) are mandatory before any public GitHub Release publication.
- Source metadata version `0.3.0` (build `4`) is not a release authorization or Git tag. Gatekeeper behavior depends on code signing, notarization and download quarantine; don't treat an unnotarized copy as an official distribution.

## First launch

1. Open `/Applications/Command Tab.app`.
2. Command Tab starts as a menu-bar accessory.
3. If macOS Accessibility permission has not yet been granted, Command Tab automatically opens Settings showing the live Accessibility status and leaves native macOS ⌘Tab intact.
4. Click **Open Accessibility Settings** in the Settings window (or open **System Settings > Privacy & Security > Accessibility**), enable **Command Tab**, then return to the app.

## Usage

- **Switch forward**: Hold **⌘** and press **Tab** (or the **Right Arrow** / **Down Arrow** key) to open the switcher and cycle forward through items.
- **Switch backward**: Hold **⌘** + **Shift** and press **Tab** (or the **Left Arrow** / **Up Arrow** key) to cycle backward.
- **Commit switch**: Release the **⌘** key to bring the selected window or application to the foreground.
- **Cancel switcher**: Press **Escape** while holding ⌘ to cancel the switch session without changing window focus.
- **Quit selected application**: While holding **⌘** with the switcher open, press **Q** to request graceful termination (`NSRunningApplication.terminate()`) of the currently selected application. Finder itself is never terminated; for a selected Finder window, **Q** requests the close action on that exact window only (if its close button is available and the window remains in the permitted Space). In Windows mode, **Q** operates at the owning application level, closing all windows belonging to that process upon termination.
- **Instant switch vs. Visual overlay**: The default reveal delay is **Instant**, so pressing ⌘Tab immediately shows the switcher. You can choose 80 ms or 150 ms to hide the overlay on very quick taps.

## Quick Launch

Command Tab provides fast application switching via **⌘1** through **⌘9**:

- Press **⌘1** through **⌘9** to immediately launch or switch to your assigned favorite apps.
- Configured slots activate the target app directly via `NSWorkspace` / `NSRunningApplication`. Key-repeat events on a configured slot are consumed without re-triggering activation.
- Unassigned slots pass through transparently to the active foreground application.
- Quick Launch is suspended while the ⌘Tab switcher panel is open.

## Settings

Click the Command Tab menu bar icon (or open Settings from the app menu) to configure:

- **General**:
  - **Launch at Login**: Native toggle (`NSSwitch`) to automatically start Command Tab when you log into your Mac (managed via `SMAppService`).
  - **Show Menu Bar Icon**: Native toggle (`NSSwitch`) to show or hide the menu bar icon. When hidden, Settings can be opened by launching `/Applications/Command Tab.app` again.
- **Appearance**: Choose between System, Light, or Dark theme appearance.
- **Switcher Mode**:
  - **Applications**: Groups windows by application PID, showing one tile per app (classic macOS ⌘Tab behavior, Space-scoped).
  - **Windows**: Shows individual window cards with real thumbnails when macOS has already granted Screen Recording permission. Otherwise, each window remains a separate compact icon-and-title entry with no empty thumbnail box; Command Tab does not prompt for new permissions.
- **Display Scope**:
  - **Active Display**: Scoped to the display associated with the first eligible WindowServer-ordered window (falling back to pointer display context when no window display is resolved).
  - **All Displays**: Includes windows on all currently visible Mission Control Spaces across all monitors.
- **Reveal Delay**: Adjust the delay before the visual switcher overlay appears (**Instant**, **80 ms**, or **150 ms**).
- **Quick Launch (⌘1–⌘9)**: Assign favorite apps to slots 1–9 using native macOS application pickers.
- **Accessibility Status**: Live verification of Accessibility permissions with a direct shortcut to macOS System Settings.

## Privacy & security

- **Ephemeral window previews**: Only in Windows mode, Command Tab uses Apple's ScreenCaptureKit to capture small still thumbnails of eligible windows after Screen Recording permission has already been granted. It never requests the permission, never captures the Photos app, and never saves thumbnails to files. If permission is absent, Windows mode hides the preview region entirely instead of displaying empty squares.
- **Zero network requests**: No network clients, telemetry, analytics, remote crash reporting, or external API calls.
- **Local preferences only**: No tracking, databases, document inspection or thumbnail persistence. Captured thumbnails remain in memory during the switch session; settings and Quick Launch app assignments are stored locally in `UserDefaults`.
- **Completely local**: Operates entirely offline on your Mac.

## Private API disclosure

Standard public macOS APIs do not provide authoritative Mission Control Space identity or the connection between Accessibility elements and WindowServer window IDs. Command Tab dynamically resolves a minimal set of read-only private symbols:

- `CGSMainConnectionID`, `CGSManagedDisplayGetCurrentSpace`, `CGSCopySpacesForWindows`: Read-only queries to determine which Space a window and display belong to.
- `_AXUIElementGetWindow`: Resolves exact `CGWindowID` for an Accessibility window element to ensure fail-closed focus targeting.

Command Tab does not modify Spaces, perform synthetic window-space moves, or call private mutation APIs (`CGSSet*`, `SLS*`). Because these APIs are private, Apple does not guarantee their behavior across future macOS versions, and Mac App Store compatibility is not claimed.

## Known limitations

- Requires Accessibility permission to intercept keyboard shortcuts and raise windows.
- Does not maintain a global cross-application per-window MRU history; ordering reflects WindowServer z-order on the current Space.
- The `CGEvent` tap treats left and right Command modifiers identically.
- Targets Apple Silicon (`arm64`) macOS 15.0 and newer. Source is checked against Xcode's macOS 27 SDK in Swift 5 mode; this is **not** a runtime compatibility claim. macOS 15, 26 and 27 each need manual permissions, event-tap, window focus, thumbnail and UI smoke checks. Private CGS/AX symbols remain a cross-version risk.

## Troubleshooting

- **⌘Tab does not trigger Command Tab**:
  1. Open **System Settings > Privacy & Security > Accessibility**.
  2. Ensure **Command Tab** is present and toggled ON.
  3. If it is already ON but not working (e.g. after a rebuild), toggle it OFF and ON again, or remove it with the `-` button and re-add it.
  4. Relaunch `/Applications/Command Tab.app`.
- **Menu bar icon disappeared**:
  - If you disabled "Show Menu Bar Icon" in Settings, you can open Settings at any time by launching `/Applications/Command Tab.app` from Finder, Spotlight, or Terminal.
- **An application on the current Space is missing from the switcher**:
  - Windows minimized to the Dock, hidden windows, or windows without standard window levels (`kCGNormalWindowLevel`) are excluded by design to prevent focusing invisible targets.

## Uninstall

1. Click the Command Tab menu bar icon and select **Quit Command Tab** (or terminate via Activity Monitor).
2. If you enabled "Launch at Login", disable it in Settings before quitting, or remove Command Tab from **System Settings > General > Login Items & Extensions**.
3. Delete `/Applications/Command Tab.app`:
   ```sh
   rm -rf "/Applications/Command Tab.app"
   ```
4. (Optional) Remove local user preferences:
   ```sh
   defaults delete com.picmao.commandtab
   ```
5. (Optional) Remove Command Tab from **System Settings > Privacy & Security > Accessibility**.

## Development

Detailed architecture invariants and design documents can be found in [`docs/architecture.md`](docs/architecture.md).

Run locally safe suites (the live desktop probe is skipped; release assertions use isolated synthetic command stubs and never access Keychain):
```sh
./test.sh
```

Explicitly enabling `COMMANDTAB_LIVE_TESTS=1` requires separate permission to inspect desktop windows; do not enable it in unattended verification. Running `./build.sh` **signs**, and running `./release.sh` **signs and submits to Apple**. Neither is part of ordinary tests. Source typecheck and isolated compile/link can instead use `xcrun swiftc` with matching `-swift-version 5`, target, SDK and frameworks; see `AGENTS.md`.

Build developer bundle (explicit certificate required):
```sh
SIGNING_IDENTITY="Apple Development: <certificate name> (<team-id>)" ./build.sh
```

Install to `/Applications`:
```sh
./install.sh
```

Produce a **release candidate archive** only when separately authorized (requires real Developer ID, notarization credentials, and network access; this is **not** a GitHub Release):
```sh
DEVELOPER_ID="Developer ID Application: <certificate name> (<team-id>)" \
NOTARY_KEYCHAIN_PROFILE="<locally configured profile>" ./release.sh
```

## License

MIT. See [`LICENSE`](LICENSE).
