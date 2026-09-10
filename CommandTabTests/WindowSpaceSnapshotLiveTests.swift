import AppKit
import CoreGraphics

@main
struct WindowSpaceSnapshotLiveTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        let settings = CommandTabSettings.shared
        guard let snapshot = WindowEnumerator().currentSnapshot(settings: settings) else {
            fputs("FAIL: authoritative Space snapshot unavailable\n", stderr)
            exit(1)
        }

        require(!snapshot.visibleSpaceContext.visibleSpaceIDs.isEmpty, "visible Space set must not be empty")
        let permitted = snapshot.visibleSpaceContext.permittedSpaceIDs(
            scope: snapshot.displayScope,
            activeDisplayID: snapshot.activeDisplayID
        )
        require(!permitted.isEmpty, "permitted Space set must not be empty")

        for window in snapshot.windows {
            require(!window.spaceIDs.isEmpty, "eligible window must have known Space membership")
            require(window.spaceIDs.contains { permitted.contains($0) }, "eligible window must intersect permitted Spaces")
        }

        print("WindowSpaceSnapshotLiveTests passed windows=\(snapshot.windows.count) spaces=\(snapshot.visibleSpaceContext.visibleSpaceIDs.sorted())")
    }
}
