import AppKit
import CoreGraphics

@main
struct AllSpacesLiveProbe {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        let window = NSWindow(
            contentRect: NSRect(x: 220, y: 220, width: 520, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "CommandTab All Spaces Probe"
        window.collectionBehavior = [.canJoinAllSpaces]
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let windowID = CGWindowID(window.windowNumber)
        let current = SpaceIdentityAdapter.currentSpaceByDisplay(
            displayIDs: DisplayResolver.activeDisplayIDs()
        ) ?? [:]
        let spaces = SpaceIdentityAdapter.spaceIDs(for: windowID) ?? []

        print("ALL_SPACES_PROBE wid=\(windowID) current=\(current) spaces=\(spaces)")
        guard !spaces.isEmpty else {
            fputs("FAIL: sticky window returned unknown Space membership\n", stderr)
            exit(1)
        }
        let visible = Set(current.values)
        let intersectsCurrent = spaces.contains { visible.contains($0) }
        print("ALL_SPACES_BEHAVIOR intersectsCurrent=\(intersectsCurrent) membershipCount=\(spaces.count)")
        window.close()
    }
}
