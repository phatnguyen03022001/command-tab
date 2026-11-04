import AppKit
import CoreGraphics

@main
enum CommandTabMain {
    static func main() {
        if CommandLine.arguments.contains("--accessibility-check") {
            print("accessibility_trusted=\(AccessibilityPermission.isTrusted())")
            return
        }
        if CommandLine.arguments.contains("--capture-permission-check") {
            print("screen_recording_granted=\(CGPreflightScreenCaptureAccess())")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
