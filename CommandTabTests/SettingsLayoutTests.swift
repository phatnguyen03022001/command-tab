import AppKit

@main
struct SettingsLayoutTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    static func main() {
        _ = NSApplication.shared
        let suite = "commandtab.settings.layout.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fputs("FAIL: test defaults unavailable\n", stderr)
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let quick = QuickLaunchSettings(defaults: defaults)
        let appearanceSettings = CommandTabSettings(defaults: defaults)
        let controller = SettingsWindowController(
            settings: appearanceSettings,
            quickLaunchSettings: quick,
            retryAccessibility: {}
        )
        guard let window = controller.window, let content = window.contentView else {
            fputs("FAIL: settings window unavailable\n", stderr)
            exit(1)
        }

        window.layoutIfNeeded()
        guard let scroll = content.subviews.compactMap({ $0 as? NSScrollView }).first else {
            fputs("FAIL: settings content must be hosted by NSScrollView\n", stderr)
            exit(1)
        }
        require(scroll.hasVerticalScroller, "settings scroll view must provide vertical scrolling")
        require(!scroll.hasHorizontalScroller, "settings scroll view must not provide horizontal scrolling")
        guard let document = scroll.documentView else {
            fputs("FAIL: settings scroll document unavailable\n", stderr)
            exit(1)
        }
        require(document.isFlipped, "settings document must use top-origin scrolling")
        document.layoutSubtreeIfNeeded()
        let views = descendants(of: document)
        let switcherModePopup = views.compactMap { $0 as? NSPopUpButton }
            .first { $0.itemTitles == ["Applications", "Windows"] }
        require(switcherModePopup != nil, "Settings must expose native Applications/Windows switcher mode control")

        let switches = views.compactMap { $0 as? NSSwitch }
        require(switches.count >= 4, "Settings must expose native NSSwitch toggles including Show App Names")
        let switchLabels = switches.compactMap { $0.accessibilityLabel() }
        require(switchLabels.contains("Launch at Login"), "Launch at Login must be an NSSwitch")
        require(switchLabels.contains("Show Menu Bar Icon"), "Show Menu Bar Icon must be an NSSwitch")
        require(switchLabels.contains("Show Background"), "Show Background must be an NSSwitch")
        require(switchLabels.contains("Show App Names"), "Show App Names must be an NSSwitch")

        let sliders = views.compactMap { $0 as? NSSlider }
        require(sliders.count >= 5, "Settings must expose sliders including Selected Icon Zoom")
        let sliderLabels = sliders.compactMap { $0.accessibilityLabel() }
        require(sliderLabels.contains("Glass Darkness"), "Glass Darkness slider must be accessible")
        require(sliderLabels.contains("Background Blur"), "Background Blur slider must be accessible")
        require(sliderLabels.contains("Icon Size"), "Icon Size slider must be accessible")
        require(sliderLabels.contains("App Spacing"), "App Spacing slider must be accessible")
        require(sliderLabels.contains("Selected Icon Zoom"), "Selected Icon Zoom slider must be accessible")
        let zoomSlider = sliders.first { $0.accessibilityLabel() == "Selected Icon Zoom" }
        require(zoomSlider?.minValue == 100 && zoomSlider?.maxValue == 175, "Selected Icon Zoom slider must expose exact 100...175 range")
        require(zoomSlider?.numberOfTickMarks == 76, "Selected Icon Zoom slider must expose 1% steps")

        let verticalStacks = views.compactMap { $0 as? NSStackView }.filter { $0.orientation == .vertical }
        let mainStack = verticalStacks.max(by: { $0.arrangedSubviews.count < $1.arrangedSubviews.count })
        let firstHeader = mainStack?.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }.first
        require(firstHeader == "Appearance", "Appearance section must be first in Settings")

        let appearancePopup = views.compactMap { $0 as? NSPopUpButton }
            .first { $0.itemTitles == ["System", "Light", "Dark"] }
        let showBackground = switches.first { $0.accessibilityLabel() == "Show Background" }
        let showAppNames = switches.first { $0.accessibilityLabel() == "Show App Names" }
        let appearanceControls: [(String, NSView?)] = [
            ("Appearance", appearancePopup),
            ("Show Background", showBackground),
            ("Glass Darkness", sliders.first { $0.accessibilityLabel() == "Glass Darkness" }),
            ("Background Blur", sliders.first { $0.accessibilityLabel() == "Background Blur" }),
            ("Icon Size", sliders.first { $0.accessibilityLabel() == "Icon Size" }),
            ("App Spacing", sliders.first { $0.accessibilityLabel() == "App Spacing" }),
            ("Selected Icon Zoom", sliders.first { $0.accessibilityLabel() == "Selected Icon Zoom" }),
            ("Show App Names", showAppNames),
            ("Reset Appearance", views.compactMap { $0 as? NSButton }.first { $0.title == "Reset Appearance" })
        ]
        require(appearanceControls.allSatisfy { $0.1 != nil }, "all Appearance controls must exist")
        let orderedAppearance = appearanceControls.compactMap { name, view -> (String, CGFloat)? in
            guard let view else { return nil }
            return (name, view.convert(view.bounds, to: document).midY)
        }.sorted { $0.1 < $1.1 }.map(\.0)
        require(orderedAppearance == ["Appearance", "Show Background", "Glass Darkness", "Background Blur", "Icon Size", "App Spacing", "Selected Icon Zoom", "Show App Names", "Reset Appearance"],
                "Appearance controls must use the exact operator-requested order")

        appearanceSettings.showBackground = false
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 240))
        controller.showWindow(nil)
        require(abs(scroll.contentView.bounds.origin.y) < 0.5, "Settings must open scrolled to top")
        require(sliders.first(where: { $0.accessibilityLabel() == "Glass Darkness" })?.isEnabled == false,
                "Glass Darkness must disable when Show Background is OFF")
        require(sliders.first(where: { $0.accessibilityLabel() == "Background Blur" })?.isEnabled == false,
                "Background Blur must disable when Show Background is OFF")
        require(sliders.first(where: { $0.accessibilityLabel() == "Icon Size" })?.isEnabled == true,
                "Icon Size must remain enabled when background is OFF")
        require(sliders.first(where: { $0.accessibilityLabel() == "App Spacing" })?.isEnabled == true,
                "App Spacing must remain enabled when background is OFF")
        require(sliders.first(where: { $0.accessibilityLabel() == "Selected Icon Zoom" })?.isEnabled == true,
                "Selected Icon Zoom must remain enabled when background is OFF")

        let resetAppearanceButton = views.compactMap { $0 as? NSButton }
            .first { $0.title == "Reset Appearance" }
        require(resetAppearanceButton != nil, "Settings must expose Reset Appearance button")

        let accessibilityButton = views.compactMap { $0 as? NSButton }
            .first { $0.title == "Open Accessibility Settings" }
        require(accessibilityButton != nil, "Accessibility action must remain inside scrollable document")
        let buttonRect = accessibilityButton!.convert(accessibilityButton!.bounds, to: document)
        require(document.bounds.contains(buttonRect), "Accessibility action must lie within document bounds")
        require(document.frame.height >= scroll.contentView.bounds.height, "document must cover the viewport")

        window.setContentSize(NSSize(width: 480, height: 440))
        window.layoutIfNeeded()
        document.layoutSubtreeIfNeeded()
        let minDocumentWidth = document.bounds.width
        let quickLaunch = views.compactMap { $0 as? QuickLaunchSettingsView }.first
        require(quickLaunch != nil, "QuickLaunchSettingsView must exist")
        let quickRect = quickLaunch!.convert(quickLaunch!.bounds, to: document)
        require(quickRect.maxX <= minDocumentWidth + 1.0, "QuickLaunch view must fit within document bounds at minimum size")

        window.setContentSize(NSSize(width: 620, height: 700))
        window.layoutIfNeeded()
        document.layoutSubtreeIfNeeded()
        let expandedDocumentWidth = document.bounds.width
        let expandedQuickRect = quickLaunch!.convert(quickLaunch!.bounds, to: document)
        require(expandedQuickRect.maxX <= expandedDocumentWidth + 1.0, "QuickLaunch view must fit within document bounds when expanded")

        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 800
        require(window.frame.height <= visibleHeight - 32, "settings window must clamp to screen visible height")
        print("SettingsLayoutTests passed")
    }
}
