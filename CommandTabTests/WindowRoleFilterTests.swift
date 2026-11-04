import AppKit
import CoreGraphics

@main
struct WindowRoleFilterTests {
    static func make(_ id: CGWindowID, _ pid: pid_t) -> WindowModel {
        WindowModel(id: id, pid: pid, bundleIdentifier: "test.app", appName: "TestApp",
                    title: "", frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                    displayID: 1, iconKey: "test.app")
    }

    static func main() {
        let input = [make(100, 1), make(101, 1), make(102, 1), make(200, 2), make(201, 2)]
        let subroles: [CGWindowID: String] = [
            100: "AXSystemDialog",
            101: "AXStandardWindow",
            102: "AXSystemDialog",
            200: "AXStandardWindow",
            201: "AXStandardWindow"
        ]
        let result = WindowRoleFilter.excludingAuxiliaryWindows(input, subrolesByWindowID: subroles)
        precondition(result.map(\.id) == [101, 200, 201],
                     "System dialogs must be excluded while two real windows in one app remain")
        let unresolved = WindowRoleFilter.excludingAuxiliaryWindows(
            [make(300, 3), make(301, 3)],
            subrolesByWindowID: [300: "AXStandardWindow"]
        )
        precondition(unresolved.map(\.id) == [300, 301],
                     "An AX identity lookup failure must not hide unrelated real windows")
        print("WindowRoleFilterTests passed")
    }
}
