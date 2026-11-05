import AppKit

final class SettingsWindowController: NSWindowController {
    private let settings: CommandTabSettings
    private let quickLaunchView: QuickLaunchSettingsView
    private let retryAccessibility: () -> Void
    private let isAccessibilityTrusted: () -> Bool
    private var permissionObservers: [NSObjectProtocol] = []
    private let launchAtLoginSwitch = NSSwitch()
    private let menuBarIconSwitch = NSSwitch()
    private let appearancePopup = NSPopUpButton()
    private let revealPopup = NSPopUpButton()
    private let displayPopup = NSPopUpButton()
    private let switcherModePopup = NSPopUpButton()
    private let showBackgroundSwitch = NSSwitch()
    private let darknessSlider = NSSlider()
    private let darknessValueLabel = NSTextField(labelWithString: "67%")
    private let blurSlider = NSSlider()
    private let blurValueLabel = NSTextField(labelWithString: "0%")
    private let iconSizeSlider = NSSlider()
    private let iconSizeValueLabel = NSTextField(labelWithString: "72 pt")
    private let appSpacingSlider = NSSlider()
    private let appSpacingValueLabel = NSTextField(labelWithString: "10 pt")
    private let selectedIconZoomSlider = NSSlider()
    private let selectedIconZoomValueLabel = NSTextField(labelWithString: "115%")
    private let showAppNamesSwitch = NSSwitch()
    private lazy var resetAppearanceButton = NSButton(title: "Reset Appearance", target: self, action: #selector(resetAppearanceAction))
    private weak var settingsScrollView: NSScrollView?
    private let permissionLabel = NSTextField(labelWithString: "")
    private let permissionStatusTitle = NSTextField(labelWithString: "")
    private let permissionStatusIcon = NSImageView()
    private lazy var permissionButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibility))

    init(
        settings: CommandTabSettings,
        quickLaunchSettings: QuickLaunchSettings,
        retryAccessibility: @escaping () -> Void,
        isAccessibilityTrusted: @escaping () -> Bool = AccessibilityPermission.isTrusted
    ) {
        self.settings = settings
        self.quickLaunchView = QuickLaunchSettingsView(settings: quickLaunchSettings)
        self.retryAccessibility = retryAccessibility
        self.isAccessibilityTrusted = isAccessibilityTrusted
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Command Tab Settings"
        window.minSize = NSSize(width: 480, height: 440)
        super.init(window: window)
        fitWindowToVisibleScreen()
        buildUI()
        refreshControls()
        let center = NotificationCenter.default
        permissionObservers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.recheckAccessibility()
        })
        permissionObservers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.recheckAccessibility()
        })
    }

    deinit {
        for observer in permissionObservers { NotificationCenter.default.removeObserver(observer) }
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        refreshControls()
        fitWindowToVisibleScreen()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        window?.layoutIfNeeded()
        scrollToTop()
        recheckAccessibility()
    }

    private func recheckAccessibility() {
        refreshControls()
        retryAccessibility()
    }

    private func scrollToTop() {
        guard let scrollView = settingsScrollView else { return }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func fitWindowToVisibleScreen() {
        guard let window else { return }
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let margin: CGFloat = 16
        let maxWidth = max(480, visibleFrame.width - margin * 2)
        let maxHeight = max(440, visibleFrame.height - margin * 2)
        let size = NSSize(width: min(520, maxWidth), height: min(640, maxHeight))
        window.setContentSize(size)
        window.center()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        configureControls()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        settingsScrollView = scrollView
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let documentView = SettingsDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24)
        ])

        for mode in AppearanceMode.allCases { appearancePopup.addItem(withTitle: mode.title) }
        appearancePopup.target = self
        appearancePopup.action = #selector(changeAppearance)

        for delay in RevealDelay.allCases { revealPopup.addItem(withTitle: delay.title) }
        revealPopup.target = self
        revealPopup.action = #selector(changeRevealDelay)

        for scope in DisplayScope.allCases { displayPopup.addItem(withTitle: scope.title) }
        displayPopup.target = self
        displayPopup.action = #selector(changeDisplayScope)

        for mode in SwitcherMode.allCases { switcherModePopup.addItem(withTitle: mode.title) }
        switcherModePopup.target = self
        switcherModePopup.action = #selector(changeSwitcherMode)

        // 1. Appearance Section
        let appearanceHeader = makeSectionHeader("Appearance")
        stack.addArrangedSubview(appearanceHeader)

        let appearanceRow = makeControlRow(
            title: "Appearance",
            subtitle: "Choose application visual theme",
            control: appearancePopup
        )
        stack.addArrangedSubview(appearanceRow)
        appearanceRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        appearanceRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let backgroundRow = makeSwitchRow(
            title: "Show Background",
            subtitle: "Show the clear glass switcher surface",
            toggle: showBackgroundSwitch
        )
        stack.addArrangedSubview(backgroundRow)
        backgroundRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        backgroundRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let darknessRow = makeSliderRow(
            title: "Glass Darkness",
            subtitle: "Controls neutral smoked contrast",
            slider: darknessSlider,
            valueLabel: darknessValueLabel
        )
        stack.addArrangedSubview(darknessRow)
        darknessRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        darknessRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let blurRow = makeSliderRow(
            title: "Background Blur",
            subtitle: "Controls background diffusion strength",
            slider: blurSlider,
            valueLabel: blurValueLabel
        )
        stack.addArrangedSubview(blurRow)
        blurRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        blurRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let iconSizeRow = makeSliderRow(
            title: "Icon Size",
            subtitle: "Preferred application and window icon size (48–96 pt)",
            slider: iconSizeSlider,
            valueLabel: iconSizeValueLabel
        )
        stack.addArrangedSubview(iconSizeRow)
        iconSizeRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        iconSizeRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let appSpacingRow = makeSliderRow(
            title: "App Spacing",
            subtitle: "Preferred spacing between switcher items (4–24 pt)",
            slider: appSpacingSlider,
            valueLabel: appSpacingValueLabel
        )
        stack.addArrangedSubview(appSpacingRow)
        appSpacingRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        appSpacingRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let selectedIconZoomRow = makeSliderRow(
            title: "Selected Icon Zoom",
            subtitle: "Scale the selected app icon and neutral selection pod (100–175%)",
            slider: selectedIconZoomSlider,
            valueLabel: selectedIconZoomValueLabel
        )
        stack.addArrangedSubview(selectedIconZoomRow)
        selectedIconZoomRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        selectedIconZoomRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let showAppNamesRow = makeSwitchRow(
            title: "Show App Names",
            subtitle: "Show application names below switcher icons",
            toggle: showAppNamesSwitch
        )
        stack.addArrangedSubview(showAppNamesRow)
        showAppNamesRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        showAppNamesRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let resetRow = makeButtonRow(button: resetAppearanceButton)
        stack.addArrangedSubview(resetRow)
        resetRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        resetRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let dividerAppearance = makeDivider()
        stack.addArrangedSubview(dividerAppearance)
        dividerAppearance.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        dividerAppearance.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        // 2. Switcher Section
        let switcherHeader = makeSectionHeader("Switcher")
        stack.addArrangedSubview(switcherHeader)

        let switcherModeRow = makeControlRow(
            title: "Switcher Mode",
            subtitle: "Group windows by application or show individually",
            control: switcherModePopup
        )
        stack.addArrangedSubview(switcherModeRow)
        switcherModeRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        switcherModeRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let revealRow = makeControlRow(
            title: "Reveal Delay",
            subtitle: "Delay before displaying the overlay on ⌘Tab",
            control: revealPopup
        )
        stack.addArrangedSubview(revealRow)
        revealRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        revealRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let displayRow = makeControlRow(
            title: "Display Scope",
            subtitle: "Scope windows to all visible displays or active display only",
            control: displayPopup
        )
        stack.addArrangedSubview(displayRow)
        displayRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        displayRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let divider2 = makeDivider()
        stack.addArrangedSubview(divider2)
        divider2.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        divider2.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        // 3. General Section
        let generalHeader = makeSectionHeader("General")
        stack.addArrangedSubview(generalHeader)

        let launchRow = makeSwitchRow(
            title: "Launch at Login",
            subtitle: "Start Command Tab automatically when you log in",
            toggle: launchAtLoginSwitch
        )
        stack.addArrangedSubview(launchRow)
        launchRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        launchRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let menuRow = makeSwitchRow(
            title: "Show Menu Bar Icon",
            subtitle: "Display Command Tab in the menu bar",
            toggle: menuBarIconSwitch
        )
        stack.addArrangedSubview(menuRow)
        menuRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        menuRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let divider1 = makeDivider()
        stack.addArrangedSubview(divider1)
        divider1.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        divider1.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        // 4. Quick Launch Section
        let quickLaunchHeader = makeSectionHeader("Quick Launch")
        stack.addArrangedSubview(quickLaunchHeader)

        let quickLaunchSub = NSTextField(labelWithString: "Press ⌘ and a number key to instantly activate or launch an assigned app.")
        quickLaunchSub.font = .systemFont(ofSize: 11.5)
        quickLaunchSub.textColor = .secondaryLabelColor
        quickLaunchSub.lineBreakMode = .byWordWrapping
        quickLaunchSub.maximumNumberOfLines = 0
        quickLaunchSub.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(quickLaunchSub)

        stack.addArrangedSubview(quickLaunchView)
        quickLaunchView.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        quickLaunchView.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let divider3 = makeDivider()
        stack.addArrangedSubview(divider3)
        divider3.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        divider3.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        // 5. Accessibility Permission Section
        let accessibilityHeader = makeSectionHeader("Accessibility")
        stack.addArrangedSubview(accessibilityHeader)

        let accessibilityRow = buildAccessibilityRow()
        stack.addArrangedSubview(accessibilityRow)
        accessibilityRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        accessibilityRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
    }

    private func configureControls() {
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(changeLaunchAtLogin)
        launchAtLoginSwitch.setAccessibilityLabel("Launch at Login")

        menuBarIconSwitch.target = self
        menuBarIconSwitch.action = #selector(changeMenuBarIconVisibility)
        menuBarIconSwitch.setAccessibilityLabel("Show Menu Bar Icon")

        [appearancePopup, revealPopup, displayPopup, switcherModePopup].forEach { popup in
            popup.controlSize = .regular
            popup.font = .systemFont(ofSize: 13)
        }
        appearancePopup.setAccessibilityLabel("Appearance")
        revealPopup.setAccessibilityLabel("Reveal Delay")
        displayPopup.setAccessibilityLabel("Display Scope")
        switcherModePopup.setAccessibilityLabel("Switcher Mode")

        showBackgroundSwitch.target = self
        showBackgroundSwitch.action = #selector(changeShowBackground)
        showBackgroundSwitch.setAccessibilityLabel("Show Background")

        darknessSlider.minValue = 0
        darknessSlider.maxValue = 100
        darknessSlider.isContinuous = true
        darknessSlider.target = self
        darknessSlider.action = #selector(changeDarkness)
        darknessSlider.setAccessibilityLabel("Glass Darkness")

        blurSlider.minValue = 0
        blurSlider.maxValue = 100
        blurSlider.isContinuous = true
        blurSlider.target = self
        blurSlider.action = #selector(changeBlur)
        blurSlider.setAccessibilityLabel("Background Blur")

        iconSizeSlider.minValue = 48
        iconSizeSlider.maxValue = 96
        iconSizeSlider.numberOfTickMarks = 13
        iconSizeSlider.allowsTickMarkValuesOnly = true
        iconSizeSlider.isContinuous = true
        iconSizeSlider.target = self
        iconSizeSlider.action = #selector(changeIconSize)
        iconSizeSlider.setAccessibilityLabel("Icon Size")

        appSpacingSlider.minValue = 4
        appSpacingSlider.maxValue = 24
        appSpacingSlider.numberOfTickMarks = 11
        appSpacingSlider.allowsTickMarkValuesOnly = true
        appSpacingSlider.isContinuous = true
        appSpacingSlider.target = self
        appSpacingSlider.action = #selector(changeAppSpacing)
        appSpacingSlider.setAccessibilityLabel("App Spacing")

        selectedIconZoomSlider.minValue = 100
        selectedIconZoomSlider.maxValue = 175
        selectedIconZoomSlider.numberOfTickMarks = 76
        selectedIconZoomSlider.allowsTickMarkValuesOnly = true
        selectedIconZoomSlider.isContinuous = true
        selectedIconZoomSlider.target = self
        selectedIconZoomSlider.action = #selector(changeSelectedIconZoom)
        selectedIconZoomSlider.setAccessibilityLabel("Selected Icon Zoom")

        showAppNamesSwitch.target = self
        showAppNamesSwitch.action = #selector(changeShowAppNames)
        showAppNamesSwitch.setAccessibilityLabel("Show App Names")

        resetAppearanceButton.bezelStyle = .rounded
        resetAppearanceButton.controlSize = .regular
        resetAppearanceButton.font = .systemFont(ofSize: 13)
        resetAppearanceButton.setAccessibilityLabel("Reset Appearance")
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeDivider() -> NSView {
        let divider = SettingsDividerView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func makeSwitchRow(title: String, subtitle: String, toggle: NSSwitch) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subLabel = NSTextField(labelWithString: subtitle)
        subLabel.font = .systemFont(ofSize: 11.5)
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byWordWrapping
        subLabel.maximumNumberOfLines = 2
        subLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, subLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addSubview(textStack)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeControlRow(title: String, subtitle: String, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subLabel = NSTextField(labelWithString: subtitle)
        subLabel.font = .systemFont(ofSize: 11.5)
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byWordWrapping
        subLabel.maximumNumberOfLines = 2
        subLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, subLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(textStack)
        row.addSubview(control)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        return row
    }

    private func makeSliderRow(
        title: String,
        subtitle: String,
        slider: NSSlider,
        valueLabel: NSTextField
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subLabel = NSTextField(labelWithString: subtitle)
        subLabel.font = .systemFont(ofSize: 11.5)
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byWordWrapping
        subLabel.maximumNumberOfLines = 2
        subLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, subLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.controlSize = .regular

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let controlStack = NSStackView(views: [slider, valueLabel])
        controlStack.orientation = .horizontal
        controlStack.alignment = .centerY
        controlStack.spacing = 8
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.widthAnchor.constraint(equalToConstant: 180).isActive = true

        row.addSubview(textStack)
        row.addSubview(controlStack)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: controlStack.leadingAnchor, constant: -12),
            controlStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            controlStack.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeButtonRow(button: NSButton) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13)

        row.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            row.trailingAnchor.constraint(greaterThanOrEqualTo: button.trailingAnchor)
        ])
        return row
    }

    private func buildAccessibilityRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        permissionStatusIcon.imageScaling = .scaleProportionallyUpOrDown
        permissionStatusIcon.translatesAutoresizingMaskIntoConstraints = false
        permissionStatusIcon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        permissionStatusIcon.heightAnchor.constraint(equalToConstant: 22).isActive = true

        permissionStatusTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        permissionStatusTitle.textColor = .labelColor

        permissionLabel.font = .systemFont(ofSize: 11.5)
        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.lineBreakMode = .byWordWrapping
        permissionLabel.maximumNumberOfLines = 0
        permissionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [permissionStatusTitle, permissionLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        permissionButton.controlSize = .regular
        permissionButton.bezelStyle = .rounded
        permissionButton.font = .systemFont(ofSize: 13)
        permissionButton.translatesAutoresizingMaskIntoConstraints = false
        permissionButton.setContentHuggingPriority(.required, for: .horizontal)

        row.addSubview(permissionStatusIcon)
        row.addSubview(textStack)
        row.addSubview(permissionButton)

        NSLayoutConstraint.activate([
            permissionStatusIcon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            permissionStatusIcon.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            textStack.leadingAnchor.constraint(equalTo: permissionStatusIcon.trailingAnchor, constant: 10),
            textStack.topAnchor.constraint(equalTo: row.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: permissionButton.leadingAnchor, constant: -12),
            permissionButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            permissionButton.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func refreshControls() {
        launchAtLoginSwitch.state = settings.launchAtLoginEnabled() ? .on : .off
        menuBarIconSwitch.state = settings.showMenuBarIcon ? .on : .off
        appearancePopup.selectItem(at: AppearanceMode.allCases.firstIndex(of: settings.appearanceMode) ?? 0)
        revealPopup.selectItem(at: RevealDelay.allCases.firstIndex(of: settings.revealDelay) ?? 1)
        displayPopup.selectItem(at: DisplayScope.allCases.firstIndex(of: settings.displayScope) ?? 0)
        switcherModePopup.selectItem(at: SwitcherMode.allCases.firstIndex(of: settings.switcherMode) ?? 0)
        showBackgroundSwitch.state = settings.showBackground ? .on : .off
        darknessSlider.integerValue = settings.glassDarkness
        darknessValueLabel.stringValue = "\(settings.glassDarkness)%"
        blurSlider.integerValue = settings.backgroundBlur
        blurValueLabel.stringValue = "\(settings.backgroundBlur)%"
        iconSizeSlider.integerValue = settings.iconSize
        iconSizeValueLabel.stringValue = "\(settings.iconSize) pt"
        appSpacingSlider.integerValue = settings.appSpacing
        appSpacingValueLabel.stringValue = "\(settings.appSpacing) pt"
        selectedIconZoomSlider.integerValue = settings.selectedIconZoom
        selectedIconZoomValueLabel.stringValue = "\(settings.selectedIconZoom)%"
        refreshSliderAccessibilityValues()
        showAppNamesSwitch.state = settings.showAppNames ? .on : .off
        darknessSlider.isEnabled = settings.showBackground
        blurSlider.isEnabled = settings.showBackground
        quickLaunchView.refresh()
        if isAccessibilityTrusted() {
            permissionStatusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Accessibility Enabled")
            permissionStatusIcon.contentTintColor = .systemGreen
            permissionStatusTitle.stringValue = "Accessibility Enabled"
            permissionLabel.stringValue = "Command Tab is authorized to intercept ⌘Tab and focus windows."
        } else {
            permissionStatusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Accessibility Required")
            permissionStatusIcon.contentTintColor = .systemOrange
            permissionStatusTitle.stringValue = "Accessibility Required"
            permissionLabel.stringValue = "Accessibility is required to intercept ⌘Tab and focus selected windows. Without it, native macOS ⌘Tab is left untouched."
        }
    }

    private func refreshSliderAccessibilityValues() {
        darknessSlider.setAccessibilityValueDescription("\(settings.glassDarkness)%")
        blurSlider.setAccessibilityValueDescription("\(settings.backgroundBlur)%")
        iconSizeSlider.setAccessibilityValueDescription("\(settings.iconSize) points")
        appSpacingSlider.setAccessibilityValueDescription("\(settings.appSpacing) points")
        selectedIconZoomSlider.setAccessibilityValueDescription("\(settings.selectedIconZoom)%")
    }

    @objc private func changeShowBackground() {
        settings.showBackground = showBackgroundSwitch.state == .on
        refreshControls()
    }

    @objc private func changeDarkness() {
        settings.glassDarkness = darknessSlider.integerValue
        darknessValueLabel.stringValue = "\(settings.glassDarkness)%"
        refreshSliderAccessibilityValues()
    }

    @objc private func changeBlur() {
        settings.backgroundBlur = blurSlider.integerValue
        blurValueLabel.stringValue = "\(settings.backgroundBlur)%"
        refreshSliderAccessibilityValues()
    }

    @objc private func changeIconSize() {
        let normalized = CommandTabSettings.normalizeIconSize(iconSizeSlider.integerValue)
        settings.iconSize = normalized
        iconSizeSlider.integerValue = normalized
        iconSizeValueLabel.stringValue = "\(normalized) pt"
        refreshSliderAccessibilityValues()
    }

    @objc private func changeAppSpacing() {
        let normalized = CommandTabSettings.normalizeAppSpacing(appSpacingSlider.integerValue)
        settings.appSpacing = normalized
        appSpacingSlider.integerValue = normalized
        appSpacingValueLabel.stringValue = "\(normalized) pt"
        refreshSliderAccessibilityValues()
    }

    @objc private func changeSelectedIconZoom() {
        let normalized = CommandTabSettings.normalizeSelectedIconZoom(selectedIconZoomSlider.integerValue)
        settings.selectedIconZoom = normalized
        selectedIconZoomSlider.integerValue = normalized
        selectedIconZoomValueLabel.stringValue = "\(normalized)%"
        refreshSliderAccessibilityValues()
    }

    @objc private func changeShowAppNames() {
        settings.showAppNames = showAppNamesSwitch.state == .on
    }

    @objc private func resetAppearanceAction() {
        settings.resetAppearance()
        settings.applyAppearance()
        refreshControls()
    }

    @objc private func changeLaunchAtLogin() {
        do {
            try settings.setLaunchAtLogin(launchAtLoginSwitch.state == .on)
        } catch {
            Log.settings.error("Launch at Login update failed: \(error.localizedDescription, privacy: .public)")
            refreshControls()
        }
    }

    @objc private func changeMenuBarIconVisibility() {
        settings.showMenuBarIcon = menuBarIconSwitch.state == .on
    }

    @objc private func changeAppearance() {
        settings.appearanceMode = AppearanceMode.allCases[max(0, appearancePopup.indexOfSelectedItem)]
    }

    @objc private func changeRevealDelay() {
        settings.revealDelay = RevealDelay.allCases[max(0, revealPopup.indexOfSelectedItem)]
    }

    @objc private func changeDisplayScope() {
        settings.displayScope = DisplayScope.allCases[max(0, displayPopup.indexOfSelectedItem)]
    }

    @objc private func changeSwitcherMode() {
        settings.switcherMode = SwitcherMode.allCases[max(0, switcherModePopup.indexOfSelectedItem)]
    }

    @objc private func openAccessibility() {
        AccessibilityPermission.openSystemSettings()
        // Recovery is driven by activation/key-window events, not a one-second guess.
    }
}

private final class SettingsDividerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateColor()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        }
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = resolvedCGColor(.windowBackgroundColor)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = resolvedCGColor(.windowBackgroundColor)
    }

    private func resolvedCGColor(_ color: NSColor) -> CGColor {
        var result: CGColor!
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }
}
