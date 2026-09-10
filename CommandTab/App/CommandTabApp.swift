import AppKit

@main
enum CommandTabMain {
    static func main() {
        if CommandLine.arguments.contains("--accessibility-check") {
            print("accessibility_trusted=\(AccessibilityPermission.isTrusted())")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
