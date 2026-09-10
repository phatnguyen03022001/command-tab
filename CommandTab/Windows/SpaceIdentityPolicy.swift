import CoreGraphics

struct VisibleSpaceContext: Equatable {
    let currentSpaceByDisplay: [CGDirectDisplayID: UInt64]

    var visibleSpaceIDs: Set<UInt64> {
        Set(currentSpaceByDisplay.values)
    }

    func permittedSpaceIDs(
        scope: DisplayScope,
        activeDisplayID: CGDirectDisplayID?
    ) -> Set<UInt64> {
        switch scope {
        case .allVisible:
            return visibleSpaceIDs
        case .activeOnly:
            guard let activeDisplayID,
                  let spaceID = currentSpaceByDisplay[activeDisplayID] else {
                return []
            }
            return [spaceID]
        }
    }

    func matches(currentSpaceByDisplay other: [CGDirectDisplayID: UInt64]) -> Bool {
        currentSpaceByDisplay == other
    }
}

enum WindowSpaceFilter {
    static func eligible(
        _ windows: [WindowModel],
        context: VisibleSpaceContext,
        scope: DisplayScope,
        activeDisplayID: CGDirectDisplayID?
    ) -> [WindowModel] {
        let permitted = context.permittedSpaceIDs(scope: scope, activeDisplayID: activeDisplayID)
        guard !permitted.isEmpty else { return [] }

        let spaceEligible = windows.filter { window in
            guard !window.spaceIDs.isEmpty else { return false }
            if scope == .activeOnly, window.displayID != activeDisplayID {
                return false
            }
            return window.spaceIDs.contains { permitted.contains($0) }
        }
        return spaceEligible
    }
}

enum SwitcherModePolicy {
    static func items(from windows: [WindowModel], mode: SwitcherMode) -> [WindowModel] {
        switch mode {
        case .applications:
            return ApplicationWindowDedupePolicy.representatives(from: windows)
        case .windows:
            return windows
        }
    }
}

enum ApplicationWindowDedupePolicy {
    static func representatives(from windows: [WindowModel]) -> [WindowModel] {
        var seenPIDs = Set<pid_t>()
        var representatives: [WindowModel] = []
        representatives.reserveCapacity(windows.count)

        for window in windows where seenPIDs.insert(window.pid).inserted {
            representatives.append(window)
        }
        return representatives
    }
}
