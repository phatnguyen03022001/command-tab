import Foundation

@main
struct QuickLaunchSettingsTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func assignment(_ name: String, bundleID: String, path: String) -> QuickLaunchAssignment {
        QuickLaunchAssignment(
            bundleIdentifier: bundleID,
            applicationURL: URL(fileURLWithPath: path),
            displayName: name
        )
    }

    static func main() {
        let suite = "com.picmao.commandtab.tests.quicklaunch.settings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { exit(2) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = QuickLaunchSettings(defaults: defaults)

        require(settings.assignment(for: 1) == nil, "slots must default to unconfigured")
        require(settings.assignment(for: 9) == nil, "slot 9 must default to unconfigured")

        let safari = assignment("Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app")
        let code = assignment("Visual Studio Code", bundleID: "com.microsoft.VSCode", path: "/Applications/Visual Studio Code.app")
        settings.setAssignment(safari, for: 1)
        settings.setAssignment(code, for: 2)
        require(settings.assignment(for: 1) == safari, "slot 1 must preserve its assignment")
        require(settings.assignment(for: 2) == code, "slot 2 must remain independent")

        let safariMoved = assignment("Safari", bundleID: "com.apple.Safari", path: "/System/Applications/Safari.app")
        settings.setAssignment(safariMoved, for: 1)
        require(settings.assignment(for: 1) == safariMoved, "changing a slot must replace the old URL deterministically")
        require(settings.assignment(for: 2) == code, "changing slot 1 must not mutate slot 2")

        settings.clearAssignment(for: 1)
        require(settings.assignment(for: 1) == nil, "clearing a slot must restore passthrough state")
        require(settings.assignment(for: 2) == code, "clearing slot 1 must not clear slot 2")
        require(settings.assignment(for: 0) == nil, "invalid slot 0 must be ignored")
        require(settings.assignment(for: 10) == nil, "invalid slot 10 must be ignored")

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appURL = tempRoot.appendingPathComponent("Picked.app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        try! FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundlePackageType": "APPL",
            "CFBundleIdentifier": "com.example.Picked",
            "CFBundleDisplayName": "Picked"
        ]
        let plistData = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try! plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let picked = QuickLaunchAssignment.fromApplicationURL(appURL)
        require(picked?.bundleIdentifier == "com.example.Picked", "picker metadata must preserve bundle identifier")
        require(picked?.displayName == "Picked", "picker metadata must use application display name")
        require(picked?.applicationURL == appURL.standardizedFileURL, "picker metadata must preserve app URL")

        print("QuickLaunchSettingsTests passed")
    }
}
