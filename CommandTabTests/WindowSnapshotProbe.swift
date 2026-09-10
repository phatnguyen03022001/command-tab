import AppKit
import CoreGraphics
import Foundation

@main
struct WindowSnapshotProbe {
    static func main() {
        let settings = CommandTabSettings.shared
        let enumerator = WindowEnumerator()
        guard let snapshot = enumerator.currentSnapshot(settings: settings) else {
            fputs("FAIL: authoritative snapshot unavailable\n", stderr)
            exit(1)
        }
        print("eligible_window_count=\(snapshot.windows.count)")
        print(String(format: "current_space_latency_ms=%.3f", snapshot.currentSpaceLatencyMs))
        print(String(format: "membership_latency_ms=%.3f", snapshot.membershipLatencyMs))
        print(String(format: "snapshot_latency_ms=%.3f", snapshot.totalLatencyMs))
        for (displayID, spaceID) in snapshot.visibleSpaceContext.currentSpaceByDisplay.sorted(by: { $0.key < $1.key }) {
            print("CURRENT display=\(displayID) currentSpace=\(spaceID)")
        }
        for window in snapshot.windows.prefix(20) {
            let display = window.displayID.map(String.init) ?? "unknown"
            print("WINDOW wid=\(window.id) pid=\(window.pid) app=\(window.appName) display=\(display) spaces=\(window.spaceIDs) eligible=true")
        }
    }
}
