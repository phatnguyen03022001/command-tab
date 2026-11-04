import AppKit
import ApplicationServices
import CoreGraphics

enum ExactAXWindowCloseResult: Equatable {
    case missingCloseButton
    case unsupportedPressAction
    case pressFailed
    case success
}

enum ExactAXWindowCloseAction {
    static func perform(
        on exactWindow: AXUIElement,
        closeButton: (AXUIElement) -> AXUIElement?,
        supportedActions: (AXUIElement) -> [String]?,
        press: (AXUIElement) -> AXError
    ) -> ExactAXWindowCloseResult {
        guard let button = closeButton(exactWindow) else { return .missingCloseButton }
        guard supportedActions(button)?.contains(kAXPressAction as String) == true else {
            return .unsupportedPressAction
        }
        return press(button) == .success ? .success : .pressFailed
    }
}

struct ExactWindowFocusEvidence {
    let targetWindowID: CGWindowID
    let focusedWindowID: CGWindowID?
    let activationAccepted: Bool
    let axFocusAccepted: Bool
    let targetStillVisible: Bool
    let spaceStillPermitted: Bool
    let sessionContextStillCurrent: Bool

    // Activation and AX write success alone never prove the selected window is focused.
    var isConfirmed: Bool {
        focusedWindowID == targetWindowID && targetStillVisible
            && spaceStillPermitted && sessionContextStillCurrent
    }
}

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

    func focus(
        _ target: WindowModel,
        permittedSpaceIDs: Set<UInt64>,
        spaceContextIsCurrent: () -> Bool
    ) -> Bool {
        guard spaceContextIsCurrent() else {
            Log.focus.error("Session Space mapping changed before exact focus")
            return false
        }
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
        let finalFocusError = AXUIElementSetAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            axWindow
        )

        var focusedValue: CFTypeRef?
        let readError = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        )
        let focusedWindowID: CGWindowID?
        if readError == .success, let value = focusedValue,
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            focusedWindowID = AXWindowIDAdapter.windowID(for: unsafeBitCast(value, to: AXUIElement.self))
        } else {
            focusedWindowID = nil
        }

        let evidence = ExactWindowFocusEvidence(
            targetWindowID: target.id,
            focusedWindowID: focusedWindowID,
            activationAccepted: activated,
            axFocusAccepted: firstRaise == .success || focusError == .success
                || secondRaise == .success || finalFocusError == .success,
            targetStillVisible: isStillVisible(target) && validate(resolved, target: target),
            spaceStillPermitted: hasPermittedSpaceMembership(target.id, permittedSpaceIDs: permittedSpaceIDs),
            sessionContextStillCurrent: spaceContextIsCurrent()
        )
        if !evidence.isConfirmed {
            Log.focus.error(
                "Exact focus unconfirmed wid=\(target.id) activated=\(activated) axAccepted=\(evidence.axFocusAccepted)"
            )
        }
        return evidence.isConfirmed
    }

    func closeExactWindow(_ target: WindowModel, permittedSpaceIDs: Set<UInt64>) -> Bool {
        guard AccessibilityPermission.isTrusted() else {
            Log.focus.error("Accessibility permission missing while closing Finder window")
            return false
        }
        guard hasPermittedSpaceMembership(target.id, permittedSpaceIDs: permittedSpaceIDs) else {
            Log.focus.error("Finder window is outside the permitted Space context: \(target.id)")
            return false
        }
        guard isStillVisible(target) else {
            Log.focus.error("Selected Finder CGWindowID is no longer visible: \(target.id)")
            return false
        }

        let resolved: ResolvedWindow
        switch resolveAndCache(target) {
        case .resolved(let value): resolved = value
        case .ambiguous:
            Log.focus.error("AX identity is ambiguous for Finder CGWindowID \(target.id); refusing close")
            return false
        case .notFound:
            Log.focus.error("No exact AX window resolved for Finder CGWindowID \(target.id); refusing close")
            return false
        }
        guard validate(resolved, target: target) else {
            Log.focus.error("Resolved Finder AX identity became stale for CGWindowID \(target.id)")
            return false
        }
        guard hasPermittedSpaceMembership(target.id, permittedSpaceIDs: permittedSpaceIDs) else {
            Log.focus.error("Finder window Space membership changed before close: \(target.id)")
            return false
        }

        let result = ExactAXWindowCloseAction.perform(
            on: resolved.element,
            closeButton: { exactWindow in
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    exactWindow,
                    kAXCloseButtonAttribute as CFString,
                    &value
                ) == .success,
                let value,
                CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
                return unsafeBitCast(value, to: AXUIElement.self)
            },
            supportedActions: { closeButton in
                var names: CFArray?
                guard AXUIElementCopyActionNames(closeButton, &names) == .success else { return nil }
                return names as? [String]
            },
            press: { closeButton in
                AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
            }
        )

        switch result {
        case .success:
            return true
        case .missingCloseButton:
            Log.focus.notice("Exact Finder AX window has no usable close button for CGWindowID \(target.id)")
        case .unsupportedPressAction:
            Log.focus.notice("Exact Finder close button does not support AXPress for CGWindowID \(target.id)")
        case .pressFailed:
            Log.focus.error("Exact Finder AX close-button press failed for CGWindowID \(target.id)")
        }
        return false
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

    static func allowsSpaceMembership(_ spaceIDs: [UInt64]?, permittedSpaceIDs: Set<UInt64>) -> Bool {
        guard !permittedSpaceIDs.isEmpty, let spaceIDs, !spaceIDs.isEmpty else {
            return false
        }
        return spaceIDs.contains(where: permittedSpaceIDs.contains)
    }

    private func hasPermittedSpaceMembership(
        _ windowID: CGWindowID,
        permittedSpaceIDs: Set<UInt64>
    ) -> Bool {
        Self.allowsSpaceMembership(
            SpaceIdentityAdapter.spaceIDs(for: windowID),
            permittedSpaceIDs: permittedSpaceIDs
        )
    }
}
