import AppKit
import CoreGraphics

@main
struct DisplayResolverTests {
    static func window(id: CGWindowID, displayID: CGDirectDisplayID?) -> WindowModel {
        WindowModel(
            id: id,
            pid: 200,
            bundleIdentifier: "test.app",
            appName: "TestApp",
            title: "Window",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            displayID: displayID,
            iconKey: "test.app"
        )
    }

    static func main() {
        let ordered = [window(id: 1, displayID: 42), window(id: 2, displayID: 99)]
        guard DisplayResolver.keyboardContextDisplayID(from: ordered) == 42 else {
            fputs("FAIL: keyboard context must follow frontmost z-order window\n", stderr)
            exit(1)
        }
        print("DisplayResolverTests passed")
    }
}
