import AppKit
import CoreGraphics

@main
struct SpaceIdentityAdapterTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        require(SpaceIdentityAdapter.isAvailable, "required read-only CGS symbols must resolve")

        let displays = DisplayResolver.activeDisplayIDs()
        guard let mapping = SpaceIdentityAdapter.currentSpaceByDisplay(displayIDs: displays) else {
            fputs("FAIL: current Space mapping unavailable\n", stderr)
            exit(1)
        }
        require(mapping.count == displays.count, "every active display must have an authoritative current Space")
        require(mapping.values.allSatisfy { $0 != 0 }, "current Space IDs must be nonzero")

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let ids = info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let resolved = ids.compactMap { SpaceIdentityAdapter.spaceIDs(for: $0) }
        require(resolved.contains { !$0.isEmpty }, "at least one on-screen window must expose Space membership")

        print("SpaceIdentityAdapterTests passed mapping=\(mapping)")
    }
}
