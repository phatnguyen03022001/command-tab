import AppKit

final class MenuBarController {
    private let settings: CommandTabSettings
    private let openSettings: () -> Void
    private let quit: () -> Void
    private var statusItem: NSStatusItem?

    init(settings: CommandTabSettings, openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.settings = settings
        self.openSettings = openSettings
        self.quit = quit
    }

    func applyVisibility() {
        if settings.showMenuBarIcon {
            ensureStatusItem()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "command", accessibilityDescription: "Command Tab") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "⌘⇥"
            }
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About Command Tab", action: #selector(aboutAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Command Tab", action: #selector(quitAction), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func settingsAction() { openSettings() }

    @objc private func aboutAction() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Command Tab",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        ])
    }

    @objc private func quitAction() { quit() }
}
