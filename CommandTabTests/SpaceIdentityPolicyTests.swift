import AppKit
import CoreGraphics

@main
struct SpaceIdentityPolicyTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func window(
        id: CGWindowID,
        pid: pid_t = 200,
        title: String = "Same",
        frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600),
        displayID: CGDirectDisplayID = 1,
        spaceIDs: [UInt64]
    ) -> WindowModel {
        WindowModel(
            id: id,
            pid: pid,
            bundleIdentifier: "test.app",
            appName: "TestApp",
            title: title,
            frame: frame,
            displayID: displayID,
            spaceIDs: spaceIDs,
            iconKey: "test.app"
        )
    }

    static func main() {
        let allVisible = VisibleSpaceContext(currentSpaceByDisplay: [1: 3, 2: 7])
        require(
            allVisible.permittedSpaceIDs(scope: .allVisible, activeDisplayID: nil) == Set([3, 7]),
            "all-visible scope must union current Spaces from active displays"
        )
        require(
            allVisible.permittedSpaceIDs(scope: .activeOnly, activeDisplayID: 2) == Set([7]),
            "active-display scope must use only that display current Space"
        )
        require(
            allVisible.permittedSpaceIDs(scope: .activeOnly, activeDisplayID: nil).isEmpty,
            "active-display scope must fail closed without a display identity"
        )

        let windows = [
            window(id: 10, pid: 500, displayID: 1, spaceIDs: [3]),
            window(id: 11, pid: 500, displayID: 1, spaceIDs: [4]),
            window(id: 12, pid: 600, displayID: 2, spaceIDs: [7]),
            window(id: 13, pid: 700, displayID: 1, spaceIDs: [])
        ]
        let eligibleAll = WindowSpaceFilter.eligible(
            windows,
            context: allVisible,
            scope: .allVisible,
            activeDisplayID: nil
        )
        require(eligibleAll.map(\.id) == [10, 12], "intersection required; unknown membership must be rejected")

        let eligibleActive = WindowSpaceFilter.eligible(
            windows,
            context: allVisible,
            scope: .activeOnly,
            activeDisplayID: 2
        )
        require(eligibleActive.map(\.id) == [12], "active-display-only must isolate its current Space")

        let normalThenFullscreen = VisibleSpaceContext(currentSpaceByDisplay: [1: 100])
        let fullscreenWindows = [
            window(id: 20, spaceIDs: [100]),
            window(id: 21, spaceIDs: [101])
        ]
        require(
            WindowSpaceFilter.eligible(fullscreenWindows, context: normalThenFullscreen, scope: .allVisible, activeDisplayID: nil).map(\.id) == [20],
            "fullscreen Space IDs must remain isolated like normal Spaces"
        )

        require(
            allVisible.matches(currentSpaceByDisplay: [1: 3, 2: 7]),
            "identical Space context must remain valid"
        )
        require(
            !allVisible.matches(currentSpaceByDisplay: [1: 4, 2: 7]),
            "changed Space context must invalidate session"
        )

        let sameIdentityShape = [
            window(id: 30, pid: 900, title: "Same", spaceIDs: [3]),
            window(id: 31, pid: 900, title: "Same", spaceIDs: [4])
        ]
        let oneSpace = VisibleSpaceContext(currentSpaceByDisplay: [1: 3])
        require(
            WindowSpaceFilter.eligible(sameIdentityShape, context: oneSpace, scope: .allVisible, activeDisplayID: nil).map(\.id) == [30],
            "same PID/title/frame windows on different Spaces must not merge"
        )

        print("SpaceIdentityPolicyTests passed")
    }
}
