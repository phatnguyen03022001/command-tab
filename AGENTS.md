# Command Tab — Repository Agent Instructions

These instructions apply only to this repository, in addition to `/Users/tienphat/Developer/AGENTS.md`. Read `README.md` and `docs/architecture.md` before changing source. Follow the workspace SDLC Mini at `../sdlc-standard/{SDLC,TASKS,REPOSITORY}.md`.

## Code boundaries

- Single-target, AppKit-first macOS application. `CommandTab/App/` composes the application; `Features/{Switcher,QuickLaunch,Settings}/` own feature behavior/UI; `System/{Input,Windowing,Accessibility}/` own OS-facing adapters; `Diagnostics/` owns logging. Prefer the smallest cohesive feature-local change; do not create generic layers, packages, actors or protocols without demonstrated need.
- Preserve the runtime contract described in `docs/architecture.md`: exactly one event tap; Space-scoped switching; exact CGWindowID-to-AX matching; fail closed on unknown/stale Space or window identity; no title/frame fallback or private Space mutations; Quick Launch never enumerates windows; Finder is not terminated; no unauthorized shortcut consumption.
- Preserve macOS 15.0+ arm64 compatibility and `-swift-version 5`. Any Swift 6 mode change, private API replacement, AppKit-to-SwiftUI rewrite, permission change, network/telemetry addition or persistence change needs separate approval.
- Names: Swift API Design Guidelines; `UpperCamelCase` types, `lowerCamelCase` members, meaningful roles, existing four-space indentation. Keep source filenames aligned with primary Swift types and feature ownership.

## ECC routing (read only)

- Existing local reference checkout: `/Users/tienphat/Developer/third-party/ECC`. Verify it exists and record its current Git revision. Never clone, vendor or silently install anything.
- For Swift work, first read only the relevant files among `rules/swift/{coding-style,patterns,security,testing}.md`. Consult common ECC rules only when needed. Repository invariants and the current language mode override optional ECC patterns.
- Load `skills/swift-protocol-di-testing/SKILL.md` **only** for a demonstrated external-API test seam; `skills/swift-concurrency-6-2/SKILL.md` **only** when reviewing concurrency or an authorized migration. `skills/liquid-glass-design/SKILL.md` primarily targets iOS/SwiftUI/UIKit, so verify macOS AppKit API availability before using any guidance. Optional on-demand: `skills/security-review/SKILL.md` and `skills/verification-loop/SKILL.md`. Do not preload the ECC catalog.

## Authoritative references and verification

- Official: [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/), [Swift language/concurrency](https://docs.swift.org/latest/documentation/the-swift-programming-language/concurrency/), [Swift 6 migration](https://www.swift.org/migration/), [Swift Testing](https://docs.swift.org/latest/documentation/testing/), [AppKit](https://developer.apple.com/documentation/appkit), [Core Graphics](https://developer.apple.com/documentation/coregraphics), [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [ServiceManagement](https://developer.apple.com/documentation/servicemanagement), [macOS HIG](https://developer.apple.com/design/human-interface-guidelines/).
- `build.sh` is the canonical signed build (not a harmless typecheck): its `xcrun swiftc` flags define the deployment target, SDK and frameworks. For read-only compile verification, run `xcrun swiftc -typecheck -parse-as-library` with the same source list, `-swift-version 5`, target, SDK and frameworks. Run `git diff --check`.
- `test.sh` is the canonical test driver, **but is not side-effect-free**: `WindowSpaceSnapshotLiveTests` queries real desktop windows; its final `SourcePolicyTests.sh` invokes `release.sh`, which probes signing identities via Keychain and may perform release actions if configured. Do not run these paths when privacy, Keychain or release access is unauthorized. Run safe independent suite commands and static source-policy assertions only, explicitly report skipped checks, and never claim an unrestricted suite PASS.
- Keep pre-existing worktree changes intact. Do not reset, stash, clean, silently stage unrelated files, sign, install, release, notarize, alter macOS permissions or touch personal data without explicit authorization.
