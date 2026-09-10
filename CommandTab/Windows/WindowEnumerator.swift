import AppKit
import CoreGraphics

struct WindowSessionSnapshot {
    let visibleSpaceContext: VisibleSpaceContext
    let displayScope: DisplayScope
    let activeDisplayID: CGDirectDisplayID?
    let windows: [WindowModel]
    let currentSpaceLatencyMs: Double
    let membershipLatencyMs: Double
    let totalLatencyMs: Double
}

final class WindowEnumerator {
    private let currentPID = ProcessInfo.processInfo.processIdentifier

    func currentWindows(settings: CommandTabSettings) -> [WindowModel] {
        currentSnapshot(settings: settings)?.windows ?? []
    }

    func currentSnapshot(settings: CommandTabSettings) -> WindowSessionSnapshot? {
        let totalStart = DispatchTime.now().uptimeNanoseconds
        let displays = DisplayResolver.activeDisplayIDs()

        let spaceStart = DispatchTime.now().uptimeNanoseconds
        guard let currentSpaces = SpaceIdentityAdapter.currentSpaceByDisplay(displayIDs: displays) else {
            Log.windows.error("Authoritative current Space resolution failed; refusing window snapshot")
            return nil
        }
        let currentSpaceLatencyMs = elapsedMs(since: spaceStart)
        let context = VisibleSpaceContext(currentSpaceByDisplay: currentSpaces)

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let dictionaries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            Log.windows.error("CGWindowListCopyWindowInfo returned no window list")
            return nil
        }

        var seen = Set<CGWindowID>()
        var candidates: [WindowModel] = []
        candidates.reserveCapacity(dictionaries.count)

        let membershipStart = DispatchTime.now().uptimeNanoseconds
        for dictionary in dictionaries {
            guard let raw = makeRawWindow(from: dictionary) else { continue }
            guard WindowEligibilityPolicy.accepts(raw, currentPID: currentPID) else { continue }
            guard seen.insert(raw.windowID).inserted else { continue }

            let spaceIDs = SpaceIdentityAdapter.spaceIDs(for: raw.windowID) ?? []
            if spaceIDs.isEmpty {
                Log.windows.debug("Excluding CGWindowID \(raw.windowID): exact Space membership unavailable")
            }

            let runningApp = NSRunningApplication(processIdentifier: raw.pid)
            let bundleID = runningApp?.bundleIdentifier
            candidates.append(WindowModel(
                id: raw.windowID,
                pid: raw.pid,
                bundleIdentifier: bundleID,
                appName: raw.appName,
                title: raw.title,
                frame: raw.frame,
                displayID: DisplayResolver.displayID(for: raw.frame),
                spaceIDs: spaceIDs,
                iconKey: bundleID ?? "pid:\(raw.pid)"
            ))
        }
        let membershipLatencyMs = elapsedMs(since: membershipStart)

        let activeDisplayID = settings.displayScope == .activeOnly
            ? DisplayResolver.keyboardContextDisplayID(from: candidates)
            : nil
        let eligible = WindowSpaceFilter.eligible(
            candidates,
            context: context,
            scope: settings.displayScope,
            activeDisplayID: activeDisplayID
        )

        return WindowSessionSnapshot(
            visibleSpaceContext: context,
            displayScope: settings.displayScope,
            activeDisplayID: activeDisplayID,
            windows: eligible,
            currentSpaceLatencyMs: currentSpaceLatencyMs,
            membershipLatencyMs: membershipLatencyMs,
            totalLatencyMs: elapsedMs(since: totalStart)
        )
    }

    func isSpaceContextCurrent(_ snapshot: WindowSessionSnapshot) -> Bool {
        let displayIDs = DisplayResolver.activeDisplayIDs()
        guard let currentSpaces = SpaceIdentityAdapter.currentSpaceByDisplay(displayIDs: displayIDs) else {
            return false
        }
        return snapshot.visibleSpaceContext.matches(currentSpaceByDisplay: currentSpaces)
    }

    func validateForFocus(_ target: WindowModel, snapshot: WindowSessionSnapshot) -> Bool {
        guard isSpaceContextCurrent(snapshot) else {
            Log.windows.error("Space context changed during switch session; cancelling selection")
            return false
        }

        guard let dictionary = visibleWindowDictionary(id: target.id),
              let raw = makeRawWindow(from: dictionary),
              raw.pid == target.pid,
              WindowEligibilityPolicy.accepts(raw, currentPID: currentPID) else {
            Log.windows.error("Selected CGWindowID no longer exists as an eligible visible window")
            return false
        }

        let currentDisplayID = DisplayResolver.displayID(for: raw.frame)
        if snapshot.displayScope == .activeOnly,
           currentDisplayID != snapshot.activeDisplayID {
            Log.windows.error("Selected CGWindowID moved outside the active display context")
            return false
        }

        guard let spaceIDs = SpaceIdentityAdapter.spaceIDs(for: target.id), !spaceIDs.isEmpty else {
            Log.windows.error("Selected CGWindowID has unknown Space membership; cancelling selection")
            return false
        }
        let permitted = snapshot.visibleSpaceContext.permittedSpaceIDs(
            scope: snapshot.displayScope,
            activeDisplayID: snapshot.activeDisplayID
        )
        guard spaceIDs.contains(where: permitted.contains) else {
            Log.windows.error("Selected CGWindowID no longer belongs to the permitted Space context")
            return false
        }
        return true
    }

    private func visibleWindowDictionary(id: CGWindowID) -> [String: Any]? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return windows.first { dictionary in
            (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id
        }
    }

    private func makeRawWindow(from dictionary: [String: Any]) -> RawWindowInfo? {
        guard let number = dictionary[kCGWindowNumber as String] as? NSNumber,
              let pidNumber = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDictionary) else {
            return nil
        }

        let pid = pid_t(pidNumber.int32Value)
        let runningApp = NSRunningApplication(processIdentifier: pid)
        return RawWindowInfo(
            windowID: number.uint32Value,
            pid: pid,
            appName: dictionary[kCGWindowOwnerName as String] as? String ?? "",
            title: dictionary[kCGWindowName as String] as? String ?? "",
            frame: frame,
            layer: (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            alpha: (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            isOnscreen: ((dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false),
            activationPolicy: runningApp?.activationPolicy
        )
    }

    private func elapsedMs(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}
