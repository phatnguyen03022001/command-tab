#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build/tests"
mkdir -p "$BUILD_DIR"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
  mkdir -p /tmp/swift-cache
  SWIFTC=(
    xcrun swiftc
    -parse-as-library
    -module-cache-path /tmp/swift-cache
    -swift-version 5
    -target arm64-apple-macos15.0
    -sdk "$SDK"
    -framework AppKit
    -framework ApplicationServices
    -framework CoreGraphics
    -framework ScreenCaptureKit
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
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowEligibility.swift" \
  "$ROOT/CommandTabTests/WindowEligibilityTests.swift"

run_test WindowRoleFilterTests \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/AXWindowIDAdapter.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowRoleFilter.swift" \
  "$ROOT/CommandTabTests/WindowRoleFilterTests.swift"

run_test WindowIdentityMatcherTests \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowIdentityMatcher.swift" \
  "$ROOT/CommandTabTests/WindowIdentityMatcherTests.swift"

run_test AXWindowIDAdapterTests \
  "$ROOT/CommandTab/System/Windowing/AXWindowIDAdapter.swift" \
  "$ROOT/CommandTabTests/AXWindowIDAdapterTests.swift"

run_test DisplayResolverTests \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTabTests/DisplayResolverTests.swift"

run_test SpaceIdentityPolicyTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/SpaceIdentityPolicy.swift" \
  "$ROOT/CommandTabTests/SpaceIdentityPolicyTests.swift"

run_test SpaceIdentityAdapterTests \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTab/System/Windowing/SpaceIdentityAdapter.swift" \
  "$ROOT/CommandTabTests/SpaceIdentityAdapterTests.swift"

run_test AppDedupePolicyTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/SpaceIdentityPolicy.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherModePolicy.swift" \
  "$ROOT/CommandTabTests/AppDedupePolicyTests.swift"

run_test SwitcherModeSettingsTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTabTests/SwitcherModeSettingsTests.swift"

run_test SwitcherReuseTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationMetrics.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherItemView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationRootView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPanelController.swift" \
  "$ROOT/CommandTabTests/SwitcherReuseTests.swift"

run_test SwitcherPresentationTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationMetrics.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherItemView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationRootView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPanelController.swift" \
  "$ROOT/CommandTabTests/SwitcherPresentationTests.swift"

run_test WindowThumbnailPresentationTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationMetrics.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherItemView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationRootView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPanelController.swift" \
  "$ROOT/CommandTabTests/WindowThumbnailPresentationTests.swift"

run_test AppearanceCustomizationTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationMetrics.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherItemView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationRootView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPanelController.swift" \
  "$ROOT/CommandTabTests/AppearanceCustomizationTests.swift"

run_test MaterialIsolationTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationMetrics.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherItemView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationRootView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPanelController.swift" \
  "$ROOT/CommandTabTests/MaterialIsolationTests.swift"

run_test SwitcherAdaptiveFitTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationMetrics.swift" \
  "$ROOT/CommandTabTests/SwitcherAdaptiveFitTests.swift"

# Live desktop probes inspect real window metadata. Never run them by default.
if [[ "${COMMANDTAB_LIVE_TESTS:-0}" == "1" ]]; then
  run_test WindowSpaceSnapshotLiveTests \
    "$ROOT/CommandTab/Diagnostics/Logger.swift" \
    "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
    "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
    "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
    "$ROOT/CommandTab/System/Windowing/WindowEligibility.swift" \
    "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
    "$ROOT/CommandTab/System/Windowing/SpaceIdentityPolicy.swift" \
    "$ROOT/CommandTab/Features/Switcher/SwitcherModePolicy.swift" \
    "$ROOT/CommandTab/System/Windowing/SpaceIdentityAdapter.swift" \
    "$ROOT/CommandTab/System/Windowing/AXWindowIDAdapter.swift" \
    "$ROOT/CommandTab/System/Windowing/WindowRoleFilter.swift" \
    "$ROOT/CommandTab/System/Windowing/WindowEnumerator.swift" \
    "$ROOT/CommandTabTests/WindowSpaceSnapshotLiveTests.swift"
else
  print 'SKIP: WindowSpaceSnapshotLiveTests (set COMMANDTAB_LIVE_TESTS=1 for explicit desktop access)'
fi

run_test QuickLaunchSettingsTests \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTabTests/QuickLaunchSettingsTests.swift"

run_test QuickLaunchControllerTests \
  "$ROOT/CommandTab/Diagnostics/Logger.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchController.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchApplicationService.swift" \
  "$ROOT/CommandTabTests/QuickLaunchControllerTests.swift"

run_test QuickLaunchApplicationResolverTests \
  "$ROOT/CommandTab/Diagnostics/Logger.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchController.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchApplicationService.swift" \
  "$ROOT/CommandTabTests/QuickLaunchApplicationResolverTests.swift"

run_test SettingsLayoutTests \
  "$ROOT/CommandTab/Diagnostics/Logger.swift" \
  "$ROOT/CommandTab/System/Accessibility/AccessibilityPermission.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettingsView.swift" \
  "$ROOT/CommandTab/Features/Settings/SettingsWindowController.swift" \
  "$ROOT/CommandTabTests/SettingsLayoutTests.swift"

run_test SwitchSessionQuitTests \
  "$ROOT/CommandTab/Diagnostics/Logger.swift" \
  "$ROOT/CommandTab/System/Accessibility/AccessibilityPermission.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchApplicationService.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchController.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowEligibility.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTab/System/Windowing/SpaceIdentityPolicy.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherModePolicy.swift" \
  "$ROOT/CommandTab/System/Windowing/SpaceIdentityAdapter.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowIdentityMatcher.swift" \
  "$ROOT/CommandTab/System/Windowing/AXWindowIDAdapter.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowFocusController.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowRoleFilter.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowEnumerator.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationMetrics.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherItemView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationRootView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPanelController.swift" \
  "$ROOT/CommandTab/System/Input/HotKeyEventTap.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitchQuitPolicy.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitchSessionController.swift" \
  "$ROOT/CommandTabTests/SwitchSessionQuitTests.swift"

run_test HotKeyEventRoutingTests \
  "$ROOT/CommandTab/Diagnostics/Logger.swift" \
  "$ROOT/CommandTab/System/Accessibility/AccessibilityPermission.swift" \
  "$ROOT/CommandTab/System/Input/HotKeyEventTap.swift" \
  "$ROOT/CommandTabTests/HotKeyEventRoutingTests.swift"

run_test SwitcherAccessibilityTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationMetrics.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherItemView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationRootView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPanelController.swift" \
  "$ROOT/CommandTabTests/SwitcherAccessibilityTests.swift"

run_test AccessibilityPermissionRecoveryTests \
  "$ROOT/CommandTab/Diagnostics/Logger.swift" \
  "$ROOT/CommandTab/System/Accessibility/AccessibilityPermission.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettingsView.swift" \
  "$ROOT/CommandTab/Features/Settings/SettingsWindowController.swift" \
  "$ROOT/CommandTabTests/AccessibilityPermissionRecoveryTests.swift"

run_test SwitcherVisualAccessibilityTests \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationMetrics.swift" \
  "$ROOT/CommandTab/System/Windowing/WindowModel.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayResolver.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherItemView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPresentationRootView.swift" \
  "$ROOT/CommandTab/Features/Switcher/SwitcherPanelController.swift" \
  "$ROOT/CommandTabTests/SwitcherVisualAccessibilityTests.swift"

run_test SettingsAccessibilityTests \
  "$ROOT/CommandTab/Diagnostics/Logger.swift" \
  "$ROOT/CommandTab/System/Accessibility/AccessibilityPermission.swift" \
  "$ROOT/CommandTab/System/Windowing/DisplayScope.swift" \
  "$ROOT/CommandTab/Features/Settings/CommandTabSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettings.swift" \
  "$ROOT/CommandTab/Features/QuickLaunch/QuickLaunchSettingsView.swift" \
  "$ROOT/CommandTab/Features/Settings/SettingsWindowController.swift" \
  "$ROOT/CommandTabTests/SettingsAccessibilityTests.swift"

"$ROOT/CommandTabTests/SourcePolicyTests.sh"
