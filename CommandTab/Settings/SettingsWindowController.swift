import AppKit

final class SettingsWindowController: NSWindowController {
    private let settings: CommandTabSettings
    private let retryAccessibility: () -> Void
    private let launchCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let menuCheckbox = NSButton(checkboxWithTitle: "Show Menu Bar Icon", target: nil, action: nil)
    private let appearancePopup = NSPopUpButton()
    private let revealPopup = NSPopUpButton()
    private let displayPopup = NSPopUpButton()
    private let permissionLabel = NSTextField(labelWithString: "")

    init(settings: CommandTabSettings, retryAccessibility: @escaping () -> Void) {
        self.settings = settings
        self.retryAccessibility = retryAccessibility
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Command Tab Settings"
        window.center()
        super.init(window: window)
        buildUI()
        refreshControls()
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        refreshControls()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24)
        ])

        stack.addArrangedSubview(sectionLabel("General"))
        launchCheckbox.target = self
        launchCheckbox.action = #selector(toggleLaunchAtLogin)
        stack.addArrangedSubview(launchCheckbox)
        menuCheckbox.target = self
        menuCheckbox.action = #selector(toggleMenuIcon)
        stack.addArrangedSubview(menuCheckbox)

        stack.addArrangedSubview(row(label: "Appearance", control: appearancePopup))
        for mode in AppearanceMode.allCases { appearancePopup.addItem(withTitle: mode.title) }
        appearancePopup.target = self
        appearancePopup.action = #selector(changeAppearance)

        stack.addArrangedSubview(row(label: "Switcher Reveal Delay", control: revealPopup))
        for delay in RevealDelay.allCases { revealPopup.addItem(withTitle: delay.title) }
        revealPopup.target = self
        revealPopup.action = #selector(changeRevealDelay)

        stack.addArrangedSubview(row(label: "Display", control: displayPopup))
        for scope in DisplayScope.allCases { displayPopup.addItem(withTitle: scope.title) }
        displayPopup.target = self
        displayPopup.action = #selector(changeDisplayScope)

        permissionLabel.lineBreakMode = .byWordWrapping
        permissionLabel.maximumNumberOfLines = 3
        permissionLabel.preferredMaxLayoutWidth = 400
        stack.addArrangedSubview(permissionLabel)
        let permissionButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibility))
        stack.addArrangedSubview(permissionButton)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func row(label: String, control: NSControl) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        let text = NSTextField(labelWithString: label)
        text.widthAnchor.constraint(equalToConstant: 160).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        row.addArrangedSubview(text)
        row.addArrangedSubview(control)
        return row
    }

    private func refreshControls() {
        launchCheckbox.state = settings.launchAtLoginEnabled() ? .on : .off
        menuCheckbox.state = settings.showMenuBarIcon ? .on : .off
        appearancePopup.selectItem(at: AppearanceMode.allCases.firstIndex(of: settings.appearanceMode) ?? 0)
        revealPopup.selectItem(at: RevealDelay.allCases.firstIndex(of: settings.revealDelay) ?? 1)
        displayPopup.selectItem(at: DisplayScope.allCases.firstIndex(of: settings.displayScope) ?? 0)
        if AccessibilityPermission.isTrusted() {
            permissionLabel.stringValue = "Accessibility is enabled. Command Tab can intercept ⌘Tab and focus selected windows."
        } else {
            permissionLabel.stringValue = "Accessibility is required to intercept ⌘Tab and focus selected windows. Without it, native macOS ⌘Tab is left untouched."
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try settings.setLaunchAtLogin(launchCheckbox.state == .on)
        } catch {
            Log.settings.error("Launch at Login update failed: \(error.localizedDescription, privacy: .public)")
            refreshControls()
        }
    }

    @objc private func toggleMenuIcon() { settings.showMenuBarIcon = menuCheckbox.state == .on }

    @objc private func changeAppearance() {
        settings.appearanceMode = AppearanceMode.allCases[max(0, appearancePopup.indexOfSelectedItem)]
    }

    @objc private func changeRevealDelay() {
        settings.revealDelay = RevealDelay.allCases[max(0, revealPopup.indexOfSelectedItem)]
    }

    @objc private func changeDisplayScope() {
        settings.displayScope = DisplayScope.allCases[max(0, displayPopup.indexOfSelectedItem)]
    }

    @objc private func openAccessibility() {
        AccessibilityPermission.openSystemSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshControls()
            self?.retryAccessibility()
        }
    }
}
