import AppKit
import ApplicationServices
import CoreGraphics

final class WindowFocusController {
    private struct ResolvedWindow {
        let element: AXUIElement
    }

    private enum Resolution {
        case resolved(ResolvedWindow)
        case ambiguous
        case notFound
    }

    private var sessionCache: [CGWindowID: ResolvedWindow] = [:]

    func beginSession() {
        sessionCache.removeAll(keepingCapacity: true)
    }

    func endSession() {
        sessionCache.removeAll(keepingCapacity: true)
    }

    func focus(_ target: WindowModel, permittedSpaceIDs: Set<UInt64>) -> Bool {
        guard AccessibilityPermission.isTrusted() else {
            Log.focus.error("Accessibility permission missing while focusing window")
            return false
        }
        guard isStillVisible(target) else {
            Log.focus.error("Selected CGWindowID is no longer visible: \(target.id)")
            return false
        }
        guard hasPermittedSpaceMembership(target.id, permittedSpaceIDs: permittedSpaceIDs) else {
            Log.focus.error("Selected CGWindowID is no longer in the permitted Space context: \(target.id)")
            return false
        }
        guard let app = NSRunningApplication(processIdentifier: target.pid) else {
            Log.focus.error("Target application no longer exists for pid \(target.pid)")
            return false
        }

        let resolved: ResolvedWindow
        switch resolveAndCache(target) {
        case .resolved(let value): resolved = value
        case .ambiguous:
            Log.focus.error("AX identity is ambiguous for CGWindowID \(target.id); refusing focus")
            return false
        case .notFound:
            Log.focus.error("No AX window resolved for CGWindowID \(target.id); refusing focus")
            return false
        }

        guard validate(resolved, target: target) else {
            Log.focus.error("Resolved AX identity became stale for CGWindowID \(target.id)")
            return false
        }
        guard hasPermittedSpaceMembership(target.id, permittedSpaceIDs: permittedSpaceIDs) else {
            Log.focus.error("Space membership became stale before focus for CGWindowID \(target.id)")
            return false
        }

        let axApp = AXUIElementCreateApplication(target.pid)
        let axWindow = resolved.element
        let firstRaise = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        let focusError = AXUIElementSetAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            axWindow
        )
        _ = AXUIElementSetAttributeValue(
            axWindow,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )

        let activated = app.activate(options: [])
        let secondRaise = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            axWindow
        )

        let axSucceeded = firstRaise == .success || focusError == .success || secondRaise == .success
        if !activated && !axSucceeded {
            Log.focus.error("Exact single-window focus failed for CGWindowID \(target.id)")
        }
        return activated || axSucceeded
    }

    #if DEBUG
    func debugIdentityStatus(for target: WindowModel) -> String {
        switch resolveAndCache(target) {
        case .resolved: return "exact-private"
        case .ambiguous: return "ambiguous"
        case .notFound: return "not-found"
        }
    }
    #endif

    private func resolveAndCache(_ target: WindowModel) -> Resolution {
        if let cached = sessionCache[target.id], validate(cached, target: target) {
            return .resolved(cached)
        }
        sessionCache[target.id] = nil
        let resolution = resolveAXWindow(for: target)
        if case .resolved(let value) = resolution {
            sessionCache[target.id] = value
        }
        return resolution
    }

    private func resolveAXWindow(for target: WindowModel) -> Resolution {
        let axApp = AXUIElementCreateApplication(target.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success, let windows = value as? [AXUIElement] else {
            return .notFound
        }

        let candidates = windows.enumerated().map { index, window in
            WindowIdentityCandidate(
                index: index,
                exactWindowID: AXWindowIDAdapter.windowID(for: window)
            )
        }

        switch WindowIdentityMatcher.resolve(target: target, candidates: candidates) {
        case .exact(let index):
            guard windows.indices.contains(index) else { return .notFound }
            return .resolved(ResolvedWindow(element: windows[index]))
        case .ambiguous:
            return .ambiguous
        case .notFound:
            return .notFound
        }
    }

    private func validate(_ resolved: ResolvedWindow, target: WindowModel) -> Bool {
        AXWindowIDAdapter.windowID(for: resolved.element) == target.id
    }

    private func isStillVisible(_ target: WindowModel) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { dictionary in
            guard let number = dictionary[kCGWindowNumber as String] as? NSNumber,
                  let pid = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                  let onscreen = dictionary[kCGWindowIsOnscreen as String] as? NSNumber else {
                return false
            }
            return number.uint32Value == target.id
                && pid.int32Value == target.pid
                && onscreen.boolValue
        }
    }

    private func hasPermittedSpaceMembership(
        _ windowID: CGWindowID,
        permittedSpaceIDs: Set<UInt64>
    ) -> Bool {
        guard !permittedSpaceIDs.isEmpty,
              let spaceIDs = SpaceIdentityAdapter.spaceIDs(for: windowID),
              !spaceIDs.isEmpty else {
            return false
        }
        return spaceIDs.contains { permittedSpaceIDs.contains($0) }
    }
}
