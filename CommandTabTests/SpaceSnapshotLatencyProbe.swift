import AppKit
import CoreGraphics
import Foundation

@main
struct SpaceSnapshotLatencyProbe {
    static func percentile(_ values: [Double], _ q: Double) -> Double {
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * q).rounded(.up)))
        return sorted[index]
    }

    static func describe(_ name: String, _ values: [Double]) {
        print(String(format: "%@ min=%.3fms p50=%.3fms p90=%.3fms max=%.3fms",
            name,
            values.min() ?? 0,
            percentile(values, 0.50),
            percentile(values, 0.90),
            values.max() ?? 0
        ))
    }

    static func main() {
        let settings = CommandTabSettings.shared
        let enumerator = WindowEnumerator()
        guard let cold = enumerator.currentSnapshot(displayScope: settings.displayScope) else {
            fputs("FAIL: cold Space-aware snapshot unavailable\n", stderr)
            exit(1)
        }
        print(String(format: "cold_space_aware_snapshot=%.3fms", cold.totalLatencyMs))
        print(String(format: "cold_current_space_resolution=%.3fms", cold.currentSpaceLatencyMs))
        print(String(format: "cold_window_space_membership=%.3fms", cold.membershipLatencyMs))
        print("cold_item_count=\(SwitcherModePolicy.items(from: cold.windows, mode: settings.switcherMode).count)")

        var total: [Double] = []
        var currentSpace: [Double] = []
        var membership: [Double] = []
        total.reserveCapacity(25)
        currentSpace.reserveCapacity(25)
        membership.reserveCapacity(25)

        for _ in 0..<25 {
            guard let snapshot = enumerator.currentSnapshot(displayScope: settings.displayScope) else {
                fputs("FAIL: warm Space-aware snapshot unavailable\n", stderr)
                exit(1)
            }
            total.append(snapshot.totalLatencyMs)
            currentSpace.append(snapshot.currentSpaceLatencyMs)
            membership.append(snapshot.membershipLatencyMs)
        }

        describe("warm_space_aware_snapshot", total)
        describe("warm_current_space_resolution", currentSpace)
        describe("warm_window_space_membership", membership)
        print("warm_item_count=\(enumerator.currentSnapshot(displayScope: settings.displayScope).map { SwitcherModePolicy.items(from: $0.windows, mode: settings.switcherMode).count } ?? -1)")
    }
}
