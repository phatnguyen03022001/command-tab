import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = CommandTabSettings.shared
    private let enumerator = WindowEnumerator()
    private let focusController = WindowFocusController()
    private let switcher = SwitcherPanelController()
    private lazy var sessionController = SwitchSessionController(
        settings: settings,
        enumerator: enumerator,
        focusController: focusController,
        switcher: switcher
    )
    private lazy var eventTap = HotKeyEventTap(delegate: sessionController)
    private lazy var menuBar = MenuBarController(
        settings: settings,
        openSettings: { [weak self] in self?.showSettings() },
        quit: { NSApp.terminate(nil) }
    )
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        retryAccessibility: { [weak self] in self?.installEventTapIfAllowed() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.applyAppearance()
        settings.onChange = { [weak self] in
            guard let self else { return }
            self.settings.applyAppearance()
            self.menuBar.applyVisibility()
        }
        menuBar.applyVisibility()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        installEventTapIfAllowed()
        if !AccessibilityPermission.isTrusted() {
            Log.app.notice("Accessibility permission is not available; event tap not installed")
            showSettings()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        eventTap.stop()
        switcher.close()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
    }

    @objc private func activeApplicationDidChange(_ notification: Notification) {
        sessionController.noteFrontmostApplicationChange()
    }

    func installEventTapIfAllowed() {
        guard AccessibilityPermission.isTrusted() else { return }
        if !eventTap.isRunning {
            let installed = eventTap.start()
            if installed {
                Log.app.notice("CommandTab event tap installed")
            } else {
                Log.input.error("Failed to install event tap; native Command-Tab remains untouched")
            }
        }
    }

    func showSettings() {
        settingsWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
