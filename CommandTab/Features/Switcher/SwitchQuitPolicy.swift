import AppKit
import CoreGraphics

enum SwitchQuitPolicy {
    static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.finder"
    ]

    private static func normalizedIdentity(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func isProtected(bundleIdentifier: String?) -> Bool {
        guard let identity = normalizedIdentity(bundleIdentifier) else { return false }
        return excludedBundleIdentifiers.contains(identity)
    }

    static func canQuit(bundleIdentifier: String?) -> Bool {
        guard let identity = normalizedIdentity(bundleIdentifier) else { return false }
        return !excludedBundleIdentifiers.contains(identity)
    }

    // Snapshot and live process identity must agree before any destructive callback.
    private static func authorizedIdentity(
        target: WindowModel,
        verifiedBundleIdentifier: String?
    ) -> String? {
        guard target.pid > 0, target.id != 0,
              let snapshotID = normalizedIdentity(target.bundleIdentifier),
              let liveID = normalizedIdentity(verifiedBundleIdentifier),
              snapshotID == liveID else { return nil }
        return liveID
    }

    static func targetWindow(in windows: [WindowModel], selectedIndex: Int) -> WindowModel? {
        guard windows.indices.contains(selectedIndex) else { return nil }
        return windows[selectedIndex]
    }

    struct ExecutionResult: Equatable {
        let applicationTerminateRequested: Bool
        let finderCloseAttempted: Bool
        let finderWindowClosed: Bool
        let actionSucceeded: Bool
    }

    static func execute(
        target: WindowModel,
        verifiedBundleIdentifier: String?,
        permittedSpaceIDs: Set<UInt64>,
        terminate: (pid_t) -> Bool,
        closeFinderWindow: (WindowModel) -> Bool,
        finderCloseSucceeded: (CGWindowID) -> Void = { _ in }
    ) -> ExecutionResult {
        guard let identity = authorizedIdentity(
            target: target,
            verifiedBundleIdentifier: verifiedBundleIdentifier
        ) else {
            return ExecutionResult(
                applicationTerminateRequested: false,
                finderCloseAttempted: false,
                finderWindowClosed: false,
                actionSucceeded: false
            )
        }
        if excludedBundleIdentifiers.contains(identity) {
            guard !permittedSpaceIDs.isEmpty,
                  target.spaceIDs.contains(where: permittedSpaceIDs.contains) else {
                return ExecutionResult(
                    applicationTerminateRequested: false,
                    finderCloseAttempted: false,
                    finderWindowClosed: false,
                    actionSucceeded: false
                )
            }
            let closed = closeFinderWindow(target)
            if closed { finderCloseSucceeded(target.id) }
            return ExecutionResult(
                applicationTerminateRequested: false,
                finderCloseAttempted: true,
                finderWindowClosed: closed,
                actionSucceeded: closed
            )
        }
        let terminated = terminate(target.pid)
        return ExecutionResult(
            applicationTerminateRequested: true,
            finderCloseAttempted: false,
            finderWindowClosed: false,
            actionSucceeded: terminated
        )
    }

    struct ReconciliationResult: Equatable {
        let remainingWindows: [WindowModel]
        let newSelectedIndex: Int
        let shouldEndSession: Bool
    }

    static func reconcile(
        windows: [WindowModel],
        selectedIndex: Int,
        terminatedPID: pid_t
    ) -> ReconciliationResult {
        guard windows.contains(where: { $0.pid == terminatedPID }) else {
            let clampedIndex = windows.isEmpty ? 0 : min(max(0, selectedIndex), windows.count - 1)
            return ReconciliationResult(
                remainingWindows: windows,
                newSelectedIndex: clampedIndex,
                shouldEndSession: windows.isEmpty
            )
        }

        let currentlySelectedPID: pid_t? = (selectedIndex >= 0 && selectedIndex < windows.count)
            ? windows[selectedIndex].pid
            : nil

        let remaining = windows.filter { $0.pid != terminatedPID }
        if remaining.isEmpty {
            return ReconciliationResult(
                remainingWindows: [],
                newSelectedIndex: 0,
                shouldEndSession: true
            )
        }

        let newIndex: Int
        if let currentlySelectedPID, currentlySelectedPID != terminatedPID,
           let matchedIndex = remaining.firstIndex(where: { $0.pid == currentlySelectedPID }) {
            newIndex = matchedIndex
        } else {
            newIndex = min(max(0, selectedIndex), remaining.count - 1)
        }

        return ReconciliationResult(
            remainingWindows: remaining,
            newSelectedIndex: newIndex,
            shouldEndSession: false
        )
    }

    static func reconcileAfterFinderClose(
        previousWindows: [WindowModel],
        selectedIndex: Int,
        closedWindowID: CGWindowID,
        refreshedWindows: [WindowModel]
    ) -> ReconciliationResult {
        guard !refreshedWindows.isEmpty else {
            return ReconciliationResult(remainingWindows: [], newSelectedIndex: 0, shouldEndSession: true)
        }

        let previousSelected = previousWindows.indices.contains(selectedIndex)
            ? previousWindows[selectedIndex]
            : nil
        let newIndex: Int
        if let previousSelected, previousSelected.id != closedWindowID,
           let preserved = refreshedWindows.firstIndex(where: { $0.id == previousSelected.id }) {
            newIndex = preserved
        } else {
            newIndex = min(max(0, selectedIndex), refreshedWindows.count - 1)
        }

        return ReconciliationResult(
            remainingWindows: refreshedWindows,
            newSelectedIndex: newIndex,
            shouldEndSession: false
        )
    }
}
