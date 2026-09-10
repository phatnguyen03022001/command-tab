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

    static func filtered(_ windows: [WindowModel], currentSpace: UInt64 = 3) -> [WindowModel] {
        WindowSpaceFilter.eligible(
            windows,
            context: VisibleSpaceContext(currentSpaceByDisplay: [1: currentSpace]),
            scope: .allVisible,
            activeDisplayID: nil
        )
    }

    static func main() {
        let samePID = filtered([
            window(id: 1, pid: 100, spaceIDs: [3]),
            window(id: 2, pid: 100, spaceIDs: [3]),
            window(id: 3, pid: 100, spaceIDs: [4])
        ])
        require(samePID.map(\.id) == [1, 2], "exact Space filtering must preserve two current-Space same-PID windows")
        require(SwitcherModePolicy.items(from: samePID, mode: .applications).map(\.id) == [1],
                "Applications mode must dedupe current-Space windows by PID")
        require(SwitcherModePolicy.items(from: samePID, mode: .windows).map(\.id) == [1, 2],
                "Windows mode must preserve all exact current-Space CGWindowIDs")

        let offSpaceFirst = filtered([
            window(id: 30, pid: 400, spaceIDs: [4]),
            window(id: 31, pid: 400, spaceIDs: [3])
        ])
        require(offSpaceFirst.map(\.id) == [31], "off-Space sibling must be excluded before mode policy")
        require(SwitcherModePolicy.items(from: offSpaceFirst, mode: .applications).map(\.id) == [31],
                "Applications dedupe must happen only after Space filtering")

        let sameBundleDifferentPIDs = filtered([
            window(id: 40, pid: 500, bundleIdentifier: "shared.bundle", spaceIDs: [3]),
            window(id: 41, pid: 501, bundleIdentifier: "shared.bundle", spaceIDs: [3])
        ])
        require(
            SwitcherModePolicy.items(from: sameBundleDifferentPIDs, mode: .applications).map(\.id) == [40, 41],
            "Applications mode must dedupe by PID, not bundle identifier"
        )

        let sticky = filtered([
            window(id: 50, pid: 600, spaceIDs: [3, 4]),
            window(id: 51, pid: 600, spaceIDs: [3])
        ])
        require(SwitcherModePolicy.items(from: sticky, mode: .applications).map(\.id) == [50],
                "Applications mode must preserve first WindowServer-order representative")
        require(SwitcherModePolicy.items(from: sticky, mode: .windows).map(\.id) == [50, 51],
                "Windows mode must retain exact sticky and current-Space window identities")

        let unknownFirst = filtered([
            window(id: 60, pid: 700, spaceIDs: []),
            window(id: 61, pid: 700, spaceIDs: [3])
        ])
        require(unknownFirst.map(\.id) == [61], "unknown Space membership must fail closed before mode policy")

        print("AppDedupePolicyTests passed")
    }
}
