import AppKit
import CoreGraphics

@main
struct WindowIdentityMatcherTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func target(id: CGWindowID = 10) -> WindowModel {
        WindowModel(
            id: id,
            pid: 200,
            bundleIdentifier: "test.app",
            appName: "TestApp",
            title: "Same",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            displayID: 1,
            spaceIDs: [3],
            iconKey: "test.app"
        )
    }

    static func main() {
        let candidates = [
            WindowIdentityCandidate(index: 0, exactWindowID: 11),
            WindowIdentityCandidate(index: 1, exactWindowID: 10)
        ]
        require(
            WindowIdentityMatcher.resolve(target: target(), candidates: candidates) == .exact(index: 1),
            "exact CGWindowID must select the matching AX window"
        )
        let unresolved = [
            WindowIdentityCandidate(index: 0, exactWindowID: nil),
            WindowIdentityCandidate(index: 1, exactWindowID: nil)
        ]
        require(
            WindowIdentityMatcher.resolve(target: target(), candidates: unresolved) == .notFound,
            "missing exact AX IDs must fail closed"
        )

        let duplicateExact = [
            WindowIdentityCandidate(index: 0, exactWindowID: 10),
            WindowIdentityCandidate(index: 1, exactWindowID: 10)
        ]
        require(
            WindowIdentityMatcher.resolve(target: target(), candidates: duplicateExact) == .ambiguous,
            "duplicate exact AX IDs must fail closed as ambiguous"
        )

        require(
            WindowIdentityMatcher.resolve(target: target(id: 99), candidates: candidates) == .notFound,
            "stale CGWindowID must not resolve another AX window"
        )
        print("WindowIdentityMatcherTests passed")
    }
}
