import Foundation

struct QuickLaunchAssignment: Equatable {
    let bundleIdentifier: String?
    let applicationURL: URL
    let displayName: String

    static func fromApplicationURL(_ url: URL) -> QuickLaunchAssignment? {
        let standardized = url.standardizedFileURL
        guard standardized.isFileURL,
              standardized.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: standardized),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" else {
            return nil
        }
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? standardized.deletingPathExtension().lastPathComponent
        return QuickLaunchAssignment(
            bundleIdentifier: bundle.bundleIdentifier,
            applicationURL: standardized,
            displayName: displayName
        )
    }
}

protocol QuickLaunchAssignmentProviding: AnyObject {
    func assignment(for slot: Int) -> QuickLaunchAssignment?
}

final class QuickLaunchSettings: QuickLaunchAssignmentProviding {
    static let shared = QuickLaunchSettings()

    private let defaults: UserDefaults
    private let keyPrefix = "quickLaunch.slot."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func assignment(for slot: Int) -> QuickLaunchAssignment? {
        guard (1...9).contains(slot),
              let dictionary = defaults.dictionary(forKey: key(for: slot)),
              let path = dictionary["applicationPath"] as? String,
              let displayName = dictionary["displayName"] as? String else {
            return nil
        }
        let bundleIdentifier = (dictionary["bundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return QuickLaunchAssignment(
            bundleIdentifier: bundleIdentifier,
            applicationURL: URL(fileURLWithPath: path).standardizedFileURL,
            displayName: displayName
        )
    }

    func setAssignment(_ assignment: QuickLaunchAssignment, for slot: Int) {
        guard (1...9).contains(slot) else { return }
        var dictionary: [String: String] = [
            "applicationPath": assignment.applicationURL.standardizedFileURL.path,
            "displayName": assignment.displayName
        ]
        if let bundleIdentifier = assignment.bundleIdentifier, !bundleIdentifier.isEmpty {
            dictionary["bundleIdentifier"] = bundleIdentifier
        }
        defaults.set(dictionary, forKey: key(for: slot))
    }

    func clearAssignment(for slot: Int) {
        guard (1...9).contains(slot) else { return }
        defaults.removeObject(forKey: key(for: slot))
    }

    private func key(for slot: Int) -> String {
        "\(keyPrefix)\(slot)"
    }
}
