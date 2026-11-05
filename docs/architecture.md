# Command Tab Architecture

## Source organization

Production source uses feature-first ownership with explicit operating-system boundaries:

- `App/` owns application composition and shell UI.
- `Features/Switcher/`, `Features/QuickLaunch/`, and `Features/Settings/` own feature orchestration, UI, and feature-local state. Switcher owns mode selection and PID deduplication; Settings owns persisted preferences and display labels. The presentation root and fallback view live in `SwitcherPresentationRootView.swift`.
- `System/Input/`, `System/Windowing/`, and `System/Accessibility/` isolate macOS adapters and platform-facing behavior shared by features. Windowing owns display-scope semantics and OS-filtered snapshots, never persisted settings or Switcher selection policy.
- `Diagnostics/` contains diagnostics-only infrastructure.

Keep the app as one target unless a real reuse or build-boundary need appears. Prefer feature ownership over file-type or catch-all directories; do not recreate generic `Input/`, `Windows/`, or `Support/` top-level buckets.

## Runtime model

Command Tab is a single-process `LSUIElement` AppKit application. It has no helper daemon, IPC service, network client, database, persistent Space state, or background Space polling loop.

A switch session starts with one authoritative window/Space snapshot. Navigation uses that frozen item list; an explicit application termination or exact Finder window close is the only supported bounded reconciliation. Stale identity or Space context cancels instead of retargeting.

The single existing `HotKeyEventTap` routes input into two independent paths. `AppDelegate` composes Quick Launch shortcut selection and handling through a callback, keeping the low-level input adapter independent of the Quick Launch feature:

`⌘Tab → SwitchSessionController`

`⌘1…⌘9 → QuickLaunchController → configured assignment → NSWorkspace / NSRunningApplication`

Quick Launch is disabled while a switcher session is active. It does not enumerate windows, inspect Spaces, or call the exact-window focus path. Key-repeat events for a valid configured slot are consumed without repeating the launch/activation action.

## Selection pipeline

Production selection follows this order exactly:

`CGWindowID → exact Space membership → visible Space intersection → optional PID grouping (Applications mode) → representative CGWindowID → exact AX identity → focus`

`WindowEnumerator` obtains WindowServer z-order with `CGWindowListCopyWindowInfo(.optionOnScreenOnly, .excludeDesktopElements)`, applies OS eligibility rules, resolves exact Space membership for each candidate and intersects against the currently visible Space set. It returns a WindowServer-ordered `WindowSessionSnapshot` without reading application settings or selecting a mode. `SwitchSessionController` passes the configured display scope, then applies feature-owned `SwitcherModePolicy` / `ApplicationWindowDedupePolicy`. Only Applications mode deduplicates by PID, and only after exact Space filtering.

In Applications mode, one running application instance (PID) produces one switcher item in the selected visible Desktop context. The representative is the first eligible window for that PID in the existing WindowServer order. There is no title, frame, or `CGWindowID` sorting.

If the representative disappears or becomes invalid, the operation fails closed. Another same-PID window is not substituted.

## Space identity

Current Space identity is resolved per active display. `kCGWindowIsOnscreen` is only an eligibility signal; it is not treated as proof of Desktop membership.

Unknown or empty Space membership is excluded. For all-visible-display mode, permitted Space IDs are the union of current Space IDs for active displays. Active-display mode restricts membership to the resolved keyboard-context display.
## Private read-only boundary

`SpaceIdentityAdapter.swift` runtime-resolves exactly these undocumented WindowServer symbols:

- `CGSMainConnectionID`
- `CGSManagedDisplayGetCurrentSpace`
- `CGSCopySpacesForWindows`

They are used only for read-only identity queries. Command Tab does not call `CGSSet*`, `SLS*`, Space switching APIs, or window-to-Space mutation APIs, and it does not persist WindowServer configuration or Space IDs.

Exact Accessibility window identity is resolved with runtime-resolved `_AXUIElementGetWindow`. Public title/frame matching is not used as a fallback.

Because these APIs are undocumented, compatibility can change with future macOS releases. Mac App Store compatibility is not claimed.

## Focus path

Before focus, Command Tab verifies that the session's display-to-Space mapping is unchanged, the representative `CGWindowID` still exists and belongs to the same PID, and its current authoritative Space membership still intersects the session's permitted Space set.

The owning application's AX windows are mapped to exact `CGWindowID` values. Exactly one AX element must match the representative. Focus raises that window, sets focused/main AX state where available, and activates the application without `.activateAllWindows`.

Any missing, ambiguous, stale, or changed identity fails closed. Window thumbnails have a separate capture-time ownership check: `SCWindow.owningApplication` PID and bundle ID must match the earlier WindowServer snapshot, even when the window ID matches; unknown owners or Photos are excluded.
## Session consistency

A session captures one immutable `WindowSessionSnapshot`. Current-Space context is revalidated while an active session is used and immediately before final focus. If the mapping changes, the session is invalidated rather than rebuilt around a different target.

There is no continuous Space tracker or background polling.

## Switcher UI

The UI reuses a single AppKit hierarchy across sessions:

- **Modern supported path (macOS 26.0+)**:
  `NSPanel` → `SwitcherPresentationRootView` (outer corner radius 28) containing:
  - `backingVisualEffect` (`NSVisualEffectView`, hudWindow, behindWindow, active, inset 2pt)
  - `smokedUnderlay` (`NSView` with neutral black alpha, inset 2pt)
  - `NSGlassEffectView` (clear style, full material alpha, outer corner radius 28; interactive glass enabled where the public API is available) whose `contentView` owns the reusable content hierarchy → `NSStackView` → `SwitcherItemView` pool
- **Compatibility path (macOS 15.0+)**:
  `NSPanel` → `SwitcherPresentationRootView` → `SwitcherPanelFallbackRootView` (`NSVisualEffectView`, popover material, continuous corner radius 28, separator border) → reusable content hierarchy → `NSStackView` → `SwitcherItemView` pool

The modern path does not fade `NSGlassEffectView` to simulate opacity. `Show Background` toggles the material as a binary surface: when off, the reusable content is temporarily reparented above the hidden glass; when on, it is restored to `NSGlassEffectView.contentView`. Darkness and Background Blur remain separate backing treatments. Clear glass uses a minimal default Darkness of 10 (3% Light / 1.8% Dark smoke alpha) for legibility; Background Blur defaults to zero.

Item views in the pool configure selection highlights using container-concentric corners (`NSViewCornerConfiguration.uniformCorners(radius: .containerConcentric(12))` on macOS 27+ with continuous rounded rect fallback on earlier versions).

AppKit display preferences are read from `NSWorkspace` and refreshed on `accessibilityDisplayOptionsDidChangeNotification`. Reduce Motion suppresses selected-item zoom and neighbor displacement; Reduce Transparency temporarily substitutes a semantic opaque backing for glass/material (including when the user's Show Background option is off); Increase Contrast strengthens the selection boundary and title hierarchy. The user's appearance settings are not changed. Transparent mode otherwise protects only label bounds with semantic window-background backing instead of darkening the entire panel. Windows-mode tile stacks are top-anchored so title visibility does not move icon/thumbnail baselines. A missing individual thumbnail remains hidden rather than allocating an empty preview placeholder.

`SwitcherItemView` instances are retained to a high-water mark and reconfigured or hidden instead of rebuilt every session. Application icons are cached by stable app key for the process lifetime.

A configurable reveal delay preserves the quick-switch path: a short ⌘Tab interaction can commit before the panel is shown, while continued navigation reveals and updates the reused panel.

## Quick Launch

`QuickLaunchSettings` stores at most nine local UserDefaults dictionaries keyed by slot. Each assignment contains the application path, display name, and bundle identifier when available. Bundle identifier is the primary logical identity; the stored URL is preferred when it is still a valid matching application bundle, otherwise LaunchServices resolves the current URL for that bundle identifier.

`QuickLaunchApplicationService` activates an already-running application or asks `NSWorkspace` to open it. No shell command, subprocess, helper daemon, additional event tap, polling loop, filesystem crawl, or Space mutation is involved. Invalid assignments fail safe and leave the original shortcut unconsumed.

The public CGEvent modifier flags expose Command as an aggregate modifier, so Quick Launch intentionally does not maintain fragile left/right modifier state. Both Command keys therefore share the same configured 1–9 semantics.

## Diagnostics

Regression and live diagnostic probes live under `CommandTabTests/`. They may observe runtime identifiers and latency during tests, but those values are diagnostic only and are not persisted as product state.

## Swift engineering references

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) for clear, role-based naming and value semantics.
- Use the [official Swift 6 migration guide](https://www.swift.org/migration/) when deliberately changing compiler concurrency settings; production currently builds in Swift 5 language mode, so do not silently switch language modes or add actors to synchronous AppKit paths.
- Optional, read-only ECC guidance: `rules/swift/{coding-style,patterns,testing,security}.md`, `skills/swift-protocol-di-testing/SKILL.md`, and `skills/swift-concurrency-6-2/SKILL.md` in the upstream ECC checkout. Apply only relevant guidance; do not vendor skill copies into this project.
- Run `./test.sh` (live desktop probe is opt-in; release policy uses mocked offline fixtures) and a full-source Swift typecheck before claiming a safe refactor. `build.sh` requires explicit `SIGNING_IDENTITY`; `release.sh` requires `DEVELOPER_ID` and `NOTARY_KEYCHAIN_PROFILE`, rejects ambiguous identities, and publishes an archive only after accepted notarization, stapling, signature and Gatekeeper checks. Signing, installing and releasing remain separately authorized operations.
- Cross-version runtime behavior (macOS 15, 26 and 27) is not established by macOS 27 SDK compilation; test exact focus, Spaces/private symbols, ScreenCaptureKit consent/Photos exclusion, input tap, menu-bar handling and glass/fallback UI on each OS before distribution.

A Finder close is permitted only for an exact AX-identified window still visible in the session's allowed Space set; ordinary application quit requests still use graceful process termination. An unused foreground-app activation notification observer was removed because it performed no session work.
