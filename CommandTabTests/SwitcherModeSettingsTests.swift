import AppKit

@main
struct SwitcherModeSettingsTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        let suite = "commandtab.switcher.mode.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { exit(2) }
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = CommandTabSettings(defaults: defaults)
        require(first.switcherMode == .applications, "Switcher mode must default to Applications")
        first.switcherMode = .windows

        let second = CommandTabSettings(defaults: defaults)
        require(second.switcherMode == .windows, "Switcher mode must persist through UserDefaults")
        second.switcherMode = .applications
        require(first.switcherMode == .applications, "settings instances must observe the persisted mode")

        print("SwitcherModeSettingsTests passed")
    }
}
