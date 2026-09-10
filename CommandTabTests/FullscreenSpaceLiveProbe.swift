import AppKit
import CoreGraphics

@main
struct FullscreenSpaceLiveProbe {
    static func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return predicate()
    }

    static func currentSpaces() -> [CGDirectDisplayID: UInt64] {
        SpaceIdentityAdapter.currentSpaceByDisplay(displayIDs: DisplayResolver.activeDisplayIDs()) ?? [:]
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()

        let window = NSWindow(
            contentRect: NSRect(x: 160, y: 160, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CommandTab Fullscreen Space Probe"
        window.collectionBehavior = [.fullScreenPrimary]
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let windowID = CGWindowID(window.windowNumber)
        let beforeContext = currentSpaces()
        let beforeMembership = SpaceIdentityAdapter.spaceIDs(for: windowID) ?? []
        print("FULLSCREEN_BEFORE current=\(beforeContext) wid=\(windowID) spaces=\(beforeMembership)")

        let beforeIDs = Set(beforeContext.values)
        window.toggleFullScreen(nil)
        var fullContext: [CGDirectDisplayID: UInt64] = [:]
        var fullMembership: [UInt64] = []
        let fullscreenStable = waitUntil({
            fullContext = currentSpaces()
            fullMembership = SpaceIdentityAdapter.spaceIDs(for: windowID) ?? []
            let fullIDs = Set(fullContext.values)
            return window.styleMask.contains(.fullScreen)
                && !fullMembership.isEmpty
                && fullMembership.contains(where: fullIDs.contains)
                && fullIDs != beforeIDs
        }, timeout: 4.0)
        guard fullscreenStable else {
            fputs("FAIL: fullscreen Space did not stabilize authoritatively\n", stderr)
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            _ = waitUntil({ !window.styleMask.contains(.fullScreen) }, timeout: 4.0)
            window.close()
            exit(1)
        }
        print("FULLSCREEN_ACTIVE current=\(fullContext) wid=\(windowID) spaces=\(fullMembership)")
        window.close()
        var afterContext: [CGDirectDisplayID: UInt64] = [:]
        let restored = waitUntil({
            afterContext = currentSpaces()
            return afterContext == beforeContext
        }, timeout: 4.0)
        print("FULLSCREEN_AFTER current=\(afterContext)")

        guard restored else {
            fputs("FAIL: closing fullscreen window did not restore original authoritative Space\n", stderr)
            exit(1)
        }
        print("FullscreenSpaceLiveProbe passed")
    }
}
