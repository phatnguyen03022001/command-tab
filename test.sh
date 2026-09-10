#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build/tests"
mkdir -p "$BUILD_DIR"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC=(
  xcrun swiftc
  -parse-as-library
  -swift-version 5
  -target arm64-apple-macos15.0
  -sdk "$SDK"
  -framework AppKit
  -framework ApplicationServices
  -framework CoreGraphics
  -framework ColorSync
  -framework ServiceManagement
  -framework OSLog
  -framework UniformTypeIdentifiers
)

run_test() {
  local name="$1"
  shift
  "${SWIFTC[@]}" "$@" -o "$BUILD_DIR/$name"
  "$BUILD_DIR/$name"
}

run_test WindowEligibilityTests \
  "$ROOT/CommandTab/Windows/WindowModel.swift" \
  "$ROOT/CommandTab/Windows/WindowEligibility.swift" \
  "$ROOT/CommandTabTests/WindowEligibilityTests.swift"

run_test WindowIdentityMatcherTests \
  "$ROOT/CommandTab/Windows/WindowModel.swift" \
  "$ROOT/CommandTab/Windows/WindowIdentityMatcher.swift" \
  "$ROOT/CommandTabTests/WindowIdentityMatcherTests.swift"

run_test AXWindowIDAdapterTests \
  "$ROOT/CommandTab/Windows/AXWindowIDAdapter.swift" \
  "$ROOT/CommandTabTests/AXWindowIDAdapterTests.swift"

run_test DisplayResolverTests \
  "$ROOT/CommandTab/Windows/WindowModel.swift" \
  "$ROOT/CommandTab/Windows/DisplayResolver.swift" \
  "$ROOT/CommandTabTests/DisplayResolverTests.swift"

run_test SpaceIdentityPolicyTests \
  "$ROOT/CommandTab/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Windows/WindowModel.swift" \
  "$ROOT/CommandTab/Windows/SpaceIdentityPolicy.swift" \
  "$ROOT/CommandTabTests/SpaceIdentityPolicyTests.swift"

run_test SpaceIdentityAdapterTests \
  "$ROOT/CommandTab/Windows/WindowModel.swift" \
  "$ROOT/CommandTab/Windows/DisplayResolver.swift" \
  "$ROOT/CommandTab/Windows/SpaceIdentityAdapter.swift" \
  "$ROOT/CommandTabTests/SpaceIdentityAdapterTests.swift"

run_test AppDedupePolicyTests \
  "$ROOT/CommandTab/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Windows/WindowModel.swift" \
  "$ROOT/CommandTab/Windows/SpaceIdentityPolicy.swift" \
  "$ROOT/CommandTabTests/AppDedupePolicyTests.swift"

run_test SwitcherReuseTests \
  "$ROOT/CommandTab/Windows/WindowModel.swift" \
  "$ROOT/CommandTab/Windows/DisplayResolver.swift" \
  "$ROOT/CommandTab/Switcher/SwitcherItemView.swift" \
  "$ROOT/CommandTab/Switcher/SwitcherPanelController.swift" \
  "$ROOT/CommandTabTests/SwitcherReuseTests.swift"

run_test WindowSpaceSnapshotLiveTests \
  "$ROOT/CommandTab/Support/Logger.swift" \
  "$ROOT/CommandTab/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Windows/WindowModel.swift" \
  "$ROOT/CommandTab/Windows/WindowEligibility.swift" \
  "$ROOT/CommandTab/Windows/DisplayResolver.swift" \
  "$ROOT/CommandTab/Windows/SpaceIdentityPolicy.swift" \
  "$ROOT/CommandTab/Windows/SpaceIdentityAdapter.swift" \
  "$ROOT/CommandTab/Windows/WindowEnumerator.swift" \
  "$ROOT/CommandTabTests/WindowSpaceSnapshotLiveTests.swift"

run_test QuickLaunchSettingsTests \
  "$ROOT/CommandTab/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTabTests/QuickLaunchSettingsTests.swift"

run_test QuickLaunchControllerTests \
  "$ROOT/CommandTab/Support/Logger.swift" \
  "$ROOT/CommandTab/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTab/QuickLaunch/QuickLaunchController.swift" \
  "$ROOT/CommandTab/QuickLaunch/QuickLaunchApplicationService.swift" \
  "$ROOT/CommandTabTests/QuickLaunchControllerTests.swift"

run_test QuickLaunchApplicationResolverTests \
  "$ROOT/CommandTab/Support/Logger.swift" \
  "$ROOT/CommandTab/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTab/QuickLaunch/QuickLaunchController.swift" \
  "$ROOT/CommandTab/QuickLaunch/QuickLaunchApplicationService.swift" \
  "$ROOT/CommandTabTests/QuickLaunchApplicationResolverTests.swift"

chmod +x "$ROOT/CommandTabTests/SourcePolicyTests.sh"
"$ROOT/CommandTabTests/SourcePolicyTests.sh"
