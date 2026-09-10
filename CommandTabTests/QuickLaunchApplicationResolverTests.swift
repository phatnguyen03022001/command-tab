import Foundation

@main
struct QuickLaunchApplicationResolverTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        let oldURL = URL(fileURLWithPath: "/Applications/Old Example.app")
        let newURL = URL(fileURLWithPath: "/Applications/New Example.app")
        let assignment = QuickLaunchAssignment(
            bundleIdentifier: "com.example.App",
            applicationURL: oldURL,
            displayName: "Example"
        )

        let movedResolver = QuickLaunchApplicationResolver(
            isApplicationBundle: { $0 == newURL },
            bundleIdentifierAtURL: { $0 == newURL ? "com.example.App" : nil },
            locateBundleIdentifier: { $0 == "com.example.App" ? newURL : nil }
        )
        require(movedResolver.resolve(assignment) == newURL,
                "missing stored URL must resolve deterministic updated URL by bundle identifier")

        let validResolver = QuickLaunchApplicationResolver(
            isApplicationBundle: { $0 == oldURL },
            bundleIdentifierAtURL: { $0 == oldURL ? "com.example.App" : nil },
            locateBundleIdentifier: { _ in nil }
        )
        require(validResolver.resolve(assignment) == oldURL,
                "valid stored URL with matching bundle identifier must win")

        let mismatchedResolver = QuickLaunchApplicationResolver(
            isApplicationBundle: { $0 == oldURL || $0 == newURL },
            bundleIdentifierAtURL: { $0 == newURL ? "com.example.App" : "com.other.App" },
            locateBundleIdentifier: { _ in newURL }
        )
        require(mismatchedResolver.resolve(assignment) == newURL,
                "stored URL with wrong bundle identity must fall back to bundle lookup")

        let invalidResolver = QuickLaunchApplicationResolver(
            isApplicationBundle: { _ in false },
            bundleIdentifierAtURL: { _ in nil },
            locateBundleIdentifier: { _ in nil }
        )
        require(invalidResolver.resolve(assignment) == nil,
                "missing app URL with no bundle fallback must fail safely")

        print("QuickLaunchApplicationResolverTests passed")
    }
}
