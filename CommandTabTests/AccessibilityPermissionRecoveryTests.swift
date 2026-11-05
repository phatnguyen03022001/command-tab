import AppKit

@main
struct AccessibilityPermissionRecoveryTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func status(_ controller: SettingsWindowController) -> String? {
        let value = Mirror(reflecting: controller).children.first(where: { $0.label == "permissionStatusTitle" })?.value
        return (value as? NSTextField)?.stringValue
    }
    static func main() {
        _ = NSApplication.shared
        let suite = "commandtab.permission.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var trusted = false
        var running = false
        var installFails = false
        var installs = 0
        var stops = 0
        var retries = 0
        let retry = {
            retries += 1
            if !trusted {
                if running { running = false; stops += 1 }
                return
            }
            if !running {
                installs += 1
                if !installFails { running = true }
            }
        }
        var controller: SettingsWindowController? = SettingsWindowController(
            settings: CommandTabSettings(defaults: defaults),
            quickLaunchSettings: QuickLaunchSettings(defaults: defaults),
            retryAccessibility: retry,
            isAccessibilityTrusted: { trusted }
        )
        require(status(controller!) == "Accessibility Required", "denied status initially visible")
        controller!.showWindow(nil)
        require(installs == 0 && !running, "denied permission never installs tap")
        let before = retries
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        require(retries > before && installs == 0, "reactivation while denied is safe")

        trusted = true
        installFails = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        require(status(controller!) == "Accessibility Enabled", "late grant refreshes Settings status")
        require(installs == 1 && !running, "event tap installation failure remains retryable")
        installFails = false
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        require(installs == 2 && running, "next reactivation recovers after failed installation")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        require(installs == 2, "repeated reactivation never duplicates running event tap")

        trusted = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: controller!.window)
        require(!running && stops == 1, "revoked permission stops existing event tap")
        require(status(controller!) == "Accessibility Required", "revocation refreshes status")
        trusted = true
        controller!.window?.orderOut(nil)
        controller!.showWindow(nil)
        require(running && installs == 3, "reopening Settings after grant reinstalls tap")
        let successfulCount = installs
        controller!.showWindow(nil)
        require(installs == successfulCount, "reopening does not duplicate tap")

        controller!.window?.close()
        let afterClosing = retries
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        require(retries == afterClosing, "closed Settings never triggers redundant retries")
        controller = nil

        // An unpresented controller can be released, removing its observers.
        var temporary: SettingsWindowController? = SettingsWindowController(
            settings: CommandTabSettings(defaults: defaults),
            quickLaunchSettings: QuickLaunchSettings(defaults: defaults),
            retryAccessibility: retry,
            isAccessibilityTrusted: { trusted }
        )
        weak let released = temporary
        temporary = nil
        require(released == nil, "observer-owning controller must deallocate when unpresented")
        let afterDeinit = retries
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        require(retries == afterDeinit, "deallocated controller must not retry")
        print("AccessibilityPermissionRecoveryTests passed")
    }
}
