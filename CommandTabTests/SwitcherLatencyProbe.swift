import AppKit
import CoreGraphics
import Foundation

@main
struct SwitcherLatencyProbe {
    static func percentile(_ values: [Double], _ q: Double) -> Double {
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * q).rounded(.up)))
        return sorted[index]
    }

    static func measure(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    static func main() {
        _ = NSApplication.shared
        let pid = ProcessInfo.processInfo.processIdentifier
        let windows = (0..<6).map { index in
            WindowModel(
                id: CGWindowID(10_000 + index),
                pid: pid_t(Int(pid) + index),
                bundleIdentifier: "probe.\(index)",
                appName: "Probe \(index + 1)",
                title: "Window \(index + 1)",
                frame: CGRect(x: 0, y: 0, width: 900, height: 700),
                displayID: CGMainDisplayID(),
                spaceIDs: [3],
                iconKey: "probe.\(index)"
            )
        }
        let switcher = SwitcherPanelController()
        let cold = measure {
            switcher.show(windows: windows, selectedIndex: 1, sessionID: 1)
        }
        switcher.close()

        var warm: [Double] = []
        warm.reserveCapacity(30)
        for iteration in 0..<30 {
            let elapsed = measure {
                switcher.show(
                    windows: windows,
                    selectedIndex: iteration % windows.count,
                    sessionID: iteration + 2
                )
            }
            warm.append(elapsed)
            switcher.close()
        }

        print(String(format: "item_count=%d", windows.count))
        print(String(format: "cold_ms=%.3f", cold))
        print(String(format: "warm_min_ms=%.3f", warm.min() ?? 0))
        print(String(format: "warm_p50_ms=%.3f", percentile(warm, 0.50)))
        print(String(format: "warm_p90_ms=%.3f", percentile(warm, 0.90)))
        print(String(format: "warm_max_ms=%.3f", warm.max() ?? 0))
    }
}
