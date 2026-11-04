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
            switcher.show(windows: windows, selectedIndex: 1, sessionID: 1, mode: .applications)
        }
        switcher.close()

        var warm: [Double] = []
        warm.reserveCapacity(30)
        for iteration in 0..<30 {
            let elapsed = measure {
                switcher.show(
                    windows: windows,
                    selectedIndex: iteration % windows.count,
                    sessionID: iteration + 2,
                    mode: .applications
                )
            }
            warm.append(elapsed)
            switcher.close()
        }

        print(String(format: "item_count=%d", windows.count))
        print(String(format: "cold_show_ms=%.3f", cold))
        print(String(format: "warm_repeated_show_min_ms=%.3f", warm.min() ?? 0))
        print(String(format: "warm_repeated_show_p50_ms=%.3f", percentile(warm, 0.50)))
        print(String(format: "warm_repeated_show_p90_ms=%.3f", percentile(warm, 0.90)))
        print(String(format: "warm_repeated_show_max_ms=%.3f", warm.max() ?? 0))

        // Direct navigation selection update measurement on active switcher hierarchy
        switcher.show(windows: windows, selectedIndex: 0, sessionID: 100, mode: .applications)
        var updates: [Double] = []
        updates.reserveCapacity(50)
        for iteration in 0..<50 {
            let elapsed = measure {
                switcher.update(
                    selectedIndex: (iteration + 1) % windows.count,
                    sessionID: 100
                )
            }
            updates.append(elapsed)
        }
        switcher.close()

        print(String(format: "direct_selection_update_min_ms=%.3f", updates.min() ?? 0))
        print(String(format: "direct_selection_update_p50_ms=%.3f", percentile(updates, 0.50)))
        print(String(format: "direct_selection_update_p90_ms=%.3f", percentile(updates, 0.90)))
        print(String(format: "direct_selection_update_max_ms=%.3f", updates.max() ?? 0))
    }
}
