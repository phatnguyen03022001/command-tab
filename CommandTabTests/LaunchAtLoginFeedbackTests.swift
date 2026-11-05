import AppKit

private enum SimulatedLoginItemFailure: Error {
    case unavailable
}

@main
struct LaunchAtLoginFeedbackTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func descendants(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(descendants)
    }

    static func main() {
        _ = NSApplication.shared
        let suite = "commandtab.settings.login-feedback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var enabled = false
        var shouldFail = false
        var requests: [Bool] = []
        var feedbackStates: [NSControl.StateValue] = []
        var launchSwitch: NSSwitch?

        let controller = SettingsWindowController(
            settings: CommandTabSettings(defaults: defaults),
            quickLaunchSettings: QuickLaunchSettings(defaults: defaults),
            retryAccessibility: {},
            isAccessibilityTrusted: { false },
            isLaunchAtLoginEnabled: { enabled },
            setLaunchAtLogin: { requested in
                requests.append(requested)
                if shouldFail { throw SimulatedLoginItemFailure.unavailable }
                enabled = requested
            },
            presentLaunchAtLoginFailure: { _ in
                feedbackStates.append(launchSwitch?.state ?? .mixed)
            }
        )
        guard let content = controller.window?.contentView,
              let toggle = descendants(content).compactMap({ $0 as? NSSwitch })
                .first(where: { $0.accessibilityLabel() == "Launch at Login" }) else {
            require(false, "accessible Launch at Login switch exists")
            return
        }
        launchSwitch = toggle

        func request(_ value: Bool) {
            toggle.state = value ? .on : .off
            require(toggle.sendAction(toggle.action!, to: toggle.target), "switch must dispatch a user action")
        }

        require(toggle.state == .off, "initial switch reflects authoritative disabled state")
        request(true)
        require(enabled && toggle.state == .on, "successful enable reflects actual system state")
        require(feedbackStates.isEmpty, "successful enable must not report failure")

        request(false)
        require(!enabled && toggle.state == .off, "successful disable reflects actual system state")
        require(feedbackStates.isEmpty, "successful disable must not report failure")

        shouldFail = true
        request(true)
        require(!enabled && toggle.state == .off, "failed enable restores authoritative disabled state")
        require(feedbackStates == [.off], "failed enable reports once after restoring switch state")

        controller.showWindow(nil)
        controller.showWindow(nil)
        require(feedbackStates.count == 1, "refresh/reopen must not replay a previous error")
        require(toggle.accessibilityLabel() == "Launch at Login", "native switch retains accessibility purpose")

        shouldFail = false
        request(true)
        require(enabled && toggle.state == .on, "retry after failure may succeed")
        require(feedbackStates.count == 1, "successful retry must not emit failure")

        shouldFail = true
        request(false)
        require(enabled && toggle.state == .on, "failed disable restores authoritative enabled state")
        require(feedbackStates == [.off, .on], "failed disable reports exactly once after restoration")
        require(requests == [true, false, true, true, false], "only explicit user actions change login items")

        controller.window?.orderOut(nil)
        print("LaunchAtLoginFeedbackTests passed")
    }
}
