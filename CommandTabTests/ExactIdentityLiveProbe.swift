import AppKit
import ApplicationServices

@main
struct ExactIdentityLiveProbe {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let frame = NSRect(x: 180, y: 180, width: 720, height: 480)
        let a = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        let b = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        a.title = "CommandTab Identity Fixture"
        b.title = "CommandTab Identity Fixture"
        a.orderFront(nil)
        b.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let expected = Set([CGWindowID(a.windowNumber), CGWindowID(b.windowNumber)])
        let axApp = AXUIElementCreateApplication(getpid())
        var value: CFTypeRef?
        let axError = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        print("accessibility_trusted=\(AXIsProcessTrusted()) ax_windows_error=\(axError.rawValue)")
        guard axError == .success, let windows = value as? [AXUIElement] else {
            fputs("FAIL: cannot enumerate own AX windows\n", stderr)
            exit(1)
        }

        let mapped = Set(windows.compactMap { AXWindowIDAdapter.windowID(for: $0) })
        print("expected_ids=\(expected.sorted())")
        print("mapped_ids=\(mapped.sorted())")
        guard expected.isSubset(of: mapped) else {
            fputs("FAIL: exact private AX to CG identity did not map both same-frame windows\n", stderr)
            exit(1)
        }

        a.close()
        b.close()
        print("ExactIdentityLiveProbe passed")
    }
}
