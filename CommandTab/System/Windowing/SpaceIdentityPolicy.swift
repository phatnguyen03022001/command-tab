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
