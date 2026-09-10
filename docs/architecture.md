# Command Tab Architecture

## Runtime model

Command Tab is a single-process `LSUIElement` AppKit application. It has no helper daemon, IPC service, network client, database, persistent Space state, or background Space polling loop.

A switch session is immutable: input creates one authoritative window/Space snapshot, navigation uses that frozen item list, and stale identity or Space context cancels rather than retargeting.

The single existing `HotKeyEventTap` routes input into two independent paths:

`⌘Tab → SwitchSessionController`

`⌘1…⌘9 → QuickLaunchController → configured assignment → NSWorkspace / NSRunningApplication`

Quick Launch is disabled while a switcher session is active. It does not enumerate windows, inspect Spaces, or call the exact-window focus path. Key-repeat events for a valid configured slot are consumed without repeating the launch/activation action.

## Selection pipeline

Production selection follows this order exactly:

`CGWindowID → exact Space membership → visible Space intersection → PID grouping → representative CGWindowID → exact AX identity → focus`

`WindowEnumerator` obtains WindowServer z-order with `CGWindowListCopyWindowInfo(.optionOnScreenOnly, .excludeDesktopElements)`, applies eligibility rules, resolves exact Space membership for each candidate, intersects against the currently visible Space set, and only then deduplicates by PID.

One running application instance (PID) therefore produces one switcher item in the selected visible Desktop context. The representative is the first eligible window for that PID in the existing WindowServer order. There is no title, frame, or `CGWindowID` sorting.

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

Any missing, ambiguous, stale, or changed identity fails closed.
## Session consistency

A session captures one immutable `WindowSessionSnapshot`. Current-Space context is revalidated while an active session is used and immediately before final focus. If the mapping changes, the session is invalidated rather than rebuilt around a different target.

There is no continuous Space tracker or background polling.

## Switcher UI

The UI reuses a single AppKit hierarchy:

`NSPanel → NSVisualEffectView → NSStackView → SwitcherItemView pool`

`SwitcherItemView` instances are retained to a high-water mark and reconfigured or hidden instead of rebuilt every session. Application icons are cached by stable app key for the process lifetime.

A configurable reveal delay preserves the quick-switch path: a short ⌘Tab interaction can commit before the panel is shown, while continued navigation reveals and updates the reused panel.

## Quick Launch

`QuickLaunchSettings` stores at most nine local UserDefaults dictionaries keyed by slot. Each assignment contains the application path, display name, and bundle identifier when available. Bundle identifier is the primary logical identity; the stored URL is preferred when it is still a valid matching application bundle, otherwise LaunchServices resolves the current URL for that bundle identifier.

`QuickLaunchApplicationService` activates an already-running application or asks `NSWorkspace` to open it. No shell command, subprocess, helper daemon, additional event tap, polling loop, filesystem crawl, or Space mutation is involved. Invalid assignments fail safe and leave the original shortcut unconsumed.

The public CGEvent modifier flags expose Command as an aggregate modifier, so Quick Launch intentionally does not maintain fragile left/right modifier state. Both Command keys therefore share the same configured 1–9 semantics.

## Diagnostics

Regression and live diagnostic probes live under `CommandTabTests/`. They may observe runtime identifiers and latency during tests, but those values are diagnostic only and are not persisted as product state.
