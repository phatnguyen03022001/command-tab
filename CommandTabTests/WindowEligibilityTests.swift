import AppKit
import CoreGraphics

@main
struct WindowEligibilityTests {
    static func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func raw(
        id: CGWindowID = 1,
        pid: pid_t = 200,
        appName: String = "TestApp",
        title: String = "Window",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        layer: Int = 0,
        alpha: Double = 1,
        onscreen: Bool = true,
        policy: NSApplication.ActivationPolicy? = .regular
    ) -> RawWindowInfo {
        RawWindowInfo(windowID: id, pid: pid, appName: appName, title: title, frame: frame, layer: layer, alpha: alpha, isOnscreen: onscreen, activationPolicy: policy)
    }

    static func main() {
        let currentPID = pid_t(100)
        assert(WindowEligibilityPolicy.accepts(raw(), currentPID: currentPID), "normal user window accepted")
        assert(!WindowEligibilityPolicy.accepts(raw(pid: currentPID), currentPID: currentPID), "own windows rejected")
        assert(!WindowEligibilityPolicy.accepts(raw(layer: 1), currentPID: currentPID), "non-zero layer rejected")
        assert(!WindowEligibilityPolicy.accepts(raw(frame: CGRect(x: 0, y: 0, width: 40, height: 40)), currentPID: currentPID), "tiny windows rejected")
        assert(!WindowEligibilityPolicy.accepts(raw(onscreen: false), currentPID: currentPID), "offscreen windows rejected")
        assert(!WindowEligibilityPolicy.accepts(raw(policy: .accessory), currentPID: currentPID), "accessory apps rejected")
        print("WindowEligibilityTests passed")
    }
}
