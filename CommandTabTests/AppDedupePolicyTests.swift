import AppKit
import CoreGraphics

@main
struct AppDedupePolicyTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func window(
        id: CGWindowID,
        pid: pid_t,
        bundleIdentifier: String? = "test.app",
        displayID: CGDirectDisplayID = 1,
        spaceIDs: [UInt64]
    ) -> WindowModel {
        WindowModel(
            id: id,
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            appName: "App-\(pid)",
            title: "Window-\(id)",
            frame: CGRect(x: 10, y: 10, width: 800, height: 600),
            displayID: displayID,
            spaceIDs: spaceIDs,
            iconKey: bundleIdentifier ?? "pid:\(pid)"
        )
    }

    static func items(_ windows: [WindowModel], currentSpace: UInt64 = 3) -> [WindowModel] {
        WindowSpaceFilter.eligible(
            windows,
            context: VisibleSpaceContext(currentSpaceByDisplay: [1: currentSpace]),
            scope: .allVisible,
            activeDisplayID: nil
        )
    }

    static func main() {
        let samePID = items([
            window(id: 1, pid: 100, spaceIDs: [3]),
            window(id: 2, pid: 100, spaceIDs: [3])
        ])
        require(samePID.map(\.id) == [1], "same-PID same-Space windows must collapse to one app item")

        let zOrder = items([
            window(id: 10, pid: 200, spaceIDs: [3]),
            window(id: 11, pid: 200, spaceIDs: [3]),
            window(id: 12, pid: 200, spaceIDs: [3])
        ])
        require(zOrder.map(\.id) == [10], "first eligible WindowServer-order window must win")

        let crossSpace = items([
            window(id: 20, pid: 300, spaceIDs: [3]),
            window(id: 21, pid: 300, spaceIDs: [4])
        ])
        require(crossSpace.map(\.id) == [20], "off-Space sibling must not influence representative")

        let offSpaceFirst = items([
            window(id: 30, pid: 400, spaceIDs: [4]),
            window(id: 31, pid: 400, spaceIDs: [3])
        ])
        require(offSpaceFirst.map(\.id) == [31], "Space filtering must happen before app dedupe")

        let sameBundleDifferentPIDs = items([
            window(id: 40, pid: 500, bundleIdentifier: "shared.bundle", spaceIDs: [3]),
            window(id: 41, pid: 501, bundleIdentifier: "shared.bundle", spaceIDs: [3])
        ])
        require(
            sameBundleDifferentPIDs.map(\.id) == [40, 41],
            "different PIDs must not collapse merely because bundle identifiers match"
        )

        let sticky = items([
            window(id: 50, pid: 600, spaceIDs: [3, 4]),
            window(id: 51, pid: 600, spaceIDs: [3])
        ])
        require(sticky.map(\.id) == [50], "sticky/All-Spaces membership must preserve first eligible representative")

        let unknownFirst = items([
            window(id: 60, pid: 700, spaceIDs: []),
            window(id: 61, pid: 700, spaceIDs: [3])
        ])
        require(unknownFirst.map(\.id) == [61], "unknown Space membership must be excluded before dedupe")

        print("AppDedupePolicyTests passed")
    }
}
