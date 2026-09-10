import AppKit
import CoreGraphics

@main
struct SameAppAcrossSpacesFixture {
    static let createSecond = "/tmp/commandtab-create-second-window"
    static let stop = "/tmp/commandtab-stop-space-fixture"

    static func main() {
        try? FileManager.default.removeItem(atPath: createSecond)
        try? FileManager.default.removeItem(atPath: stop)

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()

        let frame = NSRect(x: 180, y: 180, width: 760, height: 520)
        let first = makeWindow(frame: frame, moveToActiveSpace: false)
        first.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        report(label: "A", window: first)

        var second: NSWindow?
        while !FileManager.default.fileExists(atPath: stop) {
            if second == nil, FileManager.default.fileExists(atPath: createSecond) {
                let created = makeWindow(frame: frame, moveToActiveSpace: true)
                created.orderFrontRegardless()
                second = created
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                report(label: "B", window: created)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        second?.close()
        first.close()
    }

    static func makeWindow(frame: NSRect, moveToActiveSpace: Bool) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CommandTab Same-App Fixture"
        if moveToActiveSpace {
            window.collectionBehavior = [.moveToActiveSpace]
        }
        return window
    }

    static func report(label: String, window: NSWindow) {
        let id = CGWindowID(window.windowNumber)
        let spaces = SpaceIdentityAdapter.spaceIDs(for: id) ?? []
        let current = SpaceIdentityAdapter.currentSpaceByDisplay(
            displayIDs: DisplayResolver.activeDisplayIDs()
        ) ?? [:]
        print("FIXTURE_\(label) pid=\(getpid()) wid=\(id) frame=\(window.frame) spaces=\(spaces) current=\(current)")
        fflush(stdout)
    }
}
