import AppKit

struct QuickLaunchApplicationResolver {
    private let isApplicationBundle: (URL) -> Bool
    private let bundleIdentifierAtURL: (URL) -> String?
    private let locateBundleIdentifier: (String) -> URL?

    init(
        isApplicationBundle: @escaping (URL) -> Bool = QuickLaunchApplicationResolver.defaultIsApplicationBundle,
        bundleIdentifierAtURL: @escaping (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier },
        locateBundleIdentifier: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    ) {
        self.isApplicationBundle = isApplicationBundle
        self.bundleIdentifierAtURL = bundleIdentifierAtURL
        self.locateBundleIdentifier = locateBundleIdentifier
    }

    func resolve(_ assignment: QuickLaunchAssignment) -> URL? {
        let stored = assignment.applicationURL.standardizedFileURL
        if isApplicationBundle(stored), identityMatches(stored, assignment: assignment) {
            return stored
        }
        guard let bundleIdentifier = assignment.bundleIdentifier,
              let located = locateBundleIdentifier(bundleIdentifier)?.standardizedFileURL,
              isApplicationBundle(located),
              bundleIdentifierAtURL(located) == bundleIdentifier else {
            return nil
        }
        return located
    }

    private func identityMatches(_ url: URL, assignment: QuickLaunchAssignment) -> Bool {
        guard let expected = assignment.bundleIdentifier else { return true }
        return bundleIdentifierAtURL(url) == expected
    }

    static func defaultIsApplicationBundle(_ url: URL) -> Bool {
        guard url.isFileURL,
              url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" else {
            return false
        }
        return true
    }
}

final class QuickLaunchApplicationService: QuickLaunchApplicationServing {
    private let resolver: QuickLaunchApplicationResolver

    init(resolver: QuickLaunchApplicationResolver = QuickLaunchApplicationResolver()) {
        self.resolver = resolver
    }

    func resolve(_ assignment: QuickLaunchAssignment) -> URL? {
        resolver.resolve(assignment)
    }

    func launchOrActivate(_ url: URL, assignment: QuickLaunchAssignment) {
        let targetURL = url.standardizedFileURL
        let candidates: [NSRunningApplication]
        if let bundleIdentifier = assignment.bundleIdentifier {
            candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        } else {
            candidates = NSWorkspace.shared.runningApplications.filter {
                $0.bundleURL?.standardizedFileURL == targetURL
            }
        }

        if let running = candidates.sorted(by: { lhs, rhs in
            let lhsExact = lhs.bundleURL?.standardizedFileURL == targetURL
            let rhsExact = rhs.bundleURL?.standardizedFileURL == targetURL
            if lhsExact != rhsExact { return lhsExact && !rhsExact }
            return lhs.processIdentifier < rhs.processIdentifier
        }).first {
            if !running.activate(options: []) {
                Log.input.error("Quick Launch could not activate \(assignment.displayName, privacy: .public)")
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: targetURL, configuration: configuration) { _, error in
            if let error {
                Log.input.error("Quick Launch could not open \(assignment.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
