import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = CommandTabSettings.shared
    private let quickLaunchSettings = QuickLaunchSettings.shared
    private let enumerator = WindowEnumerator()
    private let focusController = WindowFocusController()
    private let switcher = SwitcherPanelController()
    private lazy var sessionController = SwitchSessionController(
        settings: settings,
        enumerator: enumerator,
        focusController: focusController,
        switcher: switcher
    )
    private lazy var quickLaunchController = QuickLaunchController(settings: quickLaunchSettings)
    private lazy var eventTap = HotKeyEventTap(
        delegate: sessionController,
        handleQuickLaunch: { [weak self] keyCode, flags, switcherActive, isRepeat in
            guard let self,
                  let slot = QuickLaunchShortcutPolicy.slot(
                      forKeyCode: keyCode, flags: flags, switcherActive: switcherActive
                  ) else { return false }
            return self.quickLaunchController.handle(slot: slot, isRepeat: isRepeat)
        }
    )
    private lazy var menuBar = MenuBarController(
        settings: settings,
        openSettings: { [weak self] in self?.showSettings() },
        quit: { NSApp.terminate(nil) }
    )
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        quickLaunchSettings: quickLaunchSettings,
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

    func installEventTapIfAllowed() {
        guard AccessibilityPermission.isTrusted() else {
            // A revoked grant must not leave an old session or tap intercepting shortcuts.
            if eventTap.isRunning {
                _ = sessionController.cancelSwitcher()
                eventTap.stop()
            }
            return
        }
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
