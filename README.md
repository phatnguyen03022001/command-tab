# Command Tab

Command Tab is a lightweight native macOS ⌘Tab switcher scoped to applications in the currently visible Desktop context.

It exists for one narrow job: keep keyboard app switching inside the current Mission Control Desktop/Space context instead of surfacing applications represented only by windows on other Spaces.

## Behavior

- One running application instance (PID) becomes one switcher item within the visible Desktop context.
- Exact Space membership is resolved before PID dedupe.
- The first eligible window for each PID in WindowServer z-order is the representative window.
- A representative that becomes stale is rejected; Command Tab does not substitute another same-PID window.
- Focus targets the exact representative `CGWindowID` through Accessibility.
- The switcher UI is native AppKit and reuses its panel and item views between sessions.

## Quick Launch

Command Tab also provides nine configurable application shortcuts: `⌘1` through `⌘9`. Assignments are managed in Settings with the native macOS application picker. A configured slot launches or activates that app and consumes the shortcut; an unconfigured or invalid slot passes the original shortcut through to the foreground application.

Quick Launch uses `NSWorkspace` / `NSRunningApplication` directly. It does not use shell commands, subprocesses, application indexing, polling, networking, or additional permissions. The current event-tap API exposes Command as an aggregate modifier, so v0.2.0 does not distinguish left Command from right Command.

## Requirements

- macOS 15 or later.
- Apple silicon (`arm64`) for the supplied build scripts.
- Xcode Command Line Tools.
- Accessibility permission for Command Tab.

## Build and install

```sh
./test.sh
./build.sh
./install.sh
```

The installed application is `/Applications/Command Tab.app`.
## Accessibility

Command Tab installs a keyboard event tap only when Accessibility permission is available. If permission is missing, the event tap is not installed and native macOS ⌘Tab remains untouched. Grant access in System Settings > Privacy & Security > Accessibility, then relaunch Command Tab.

## Privacy

Command Tab has no network client, telemetry, analytics, account service, cloud dependency, screenshot capture, ScreenCaptureKit integration, or Photos access. It does not crawl arbitrary filesystem content. Runtime window focus uses macOS Accessibility APIs.

## Architecture

The core selection path is:

`CGWindowID → exact Space membership → visible Space intersection → PID grouping → representative CGWindowID → exact AX identity → focus`

Each switch session uses an immutable snapshot. Unknown or stale Space/window identity fails closed. There is no background Space polling. See [`docs/architecture.md`](docs/architecture.md) for the production invariants.

## Private API disclosure

macOS public APIs do not expose enough authoritative Mission Control Space/window identity for this behavior. Command Tab therefore runtime-resolves a narrow undocumented API boundary:

- Space identity: `CGSMainConnectionID`, `CGSManagedDisplayGetCurrentSpace`, `CGSCopySpacesForWindows`
- AX window identity: `_AXUIElementGetWindow`

The Space calls are read-only. Command Tab performs no Space mutation, Space switching, or persistent WindowServer configuration changes. These APIs may change in future macOS releases, and Mac App Store compatibility is not claimed.
## Known limitations

- Undocumented macOS APIs create compatibility risk across future macOS releases.
- Accessibility permission is required for interception and exact window focus.
- Ordering follows the eligible WindowServer snapshot; Command Tab does not implement cross-application per-window MRU history.
- The supplied build scripts target Apple silicon macOS 15+.
- Quick Launch currently treats left and right Command identically because the event tap uses the aggregate Command modifier.

## License

MIT. See [`LICENSE`](LICENSE).
