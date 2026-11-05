import AppKit

@main
struct SettingsAccessibilityTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func descendants(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(descendants)
    }

    static func main() {
        _ = NSApplication.shared
        let suite = "commandtab.settings.ax.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CommandTabSettings(defaults: defaults)
        let quick = QuickLaunchSettings(defaults: defaults)
        let controller = SettingsWindowController(
            settings: settings,
            quickLaunchSettings: quick,
            retryAccessibility: {},
            isAccessibilityTrusted: { false }
        )
        guard let content = controller.window?.contentView else {
            require(false, "Settings content exists")
            return
        }
        let views = descendants(content)
        let popups = views.compactMap { $0 as? NSPopUpButton }
        let popupNames = Set(popups.compactMap { $0.accessibilityLabel() })
        require(popupNames == ["Appearance", "Reveal Delay", "Display Scope", "Switcher Mode"],
                "all four popup controls expose unique purposes")
        for popup in popups {
            require(popup.indexOfSelectedItem >= 0, "popup selected value is available")
        }

        let switches = views.compactMap { $0 as? NSSwitch }
        require(Set(switches.compactMap { $0.accessibilityLabel() }) ==
                ["Launch at Login", "Show Menu Bar Icon", "Show Background", "Show App Names"],
                "every Settings switch exposes its visible meaning")
        let sliders = views.compactMap { $0 as? NSSlider }
        let expectedValues: [String: String] = [
            "Glass Darkness": "10%",
            "Background Blur": "0%",
            "Icon Size": "72 points",
            "App Spacing": "10 points",
            "Selected Icon Zoom": "115%"
        ]
        require(sliders.count == expectedValues.count, "five native sliders exist")
        for slider in sliders {
            guard let label = slider.accessibilityLabel(), let expected = expectedValues[label] else {
                require(false, "all sliders have unique labels")
                return
            }
            require(slider.accessibilityValueDescription() == expected,
                    "\(label) exposes its value with meaningful units")
        }

        guard let quickView = views.compactMap({ $0 as? QuickLaunchSettingsView }).first else {
            require(false, "Quick Launch view exists")
            return
        }
        var buttons = descendants(quickView).compactMap { $0 as? NSButton }
        require(buttons.count == 18, "each Quick Launch slot has exactly two actions")
        for slot in 1...9 {
            require(buttons.contains {
                $0.accessibilityLabel() == "Assign application to Command+\(slot)" && $0.isEnabled
            }, "unassigned slot \(slot) exposes its Assign action")
            require(buttons.contains {
                $0.accessibilityLabel() == "Clear application from Command+\(slot), Not Configured" && !$0.isEnabled
            }, "unassigned slot \(slot) exposes disabled Clear")
        }
        quick.setAssignment(
            QuickLaunchAssignment(bundleIdentifier: "test.editor",
                                  applicationURL: URL(fileURLWithPath: "/nonexistent/Editor.app"),
                                  displayName: "Editor"),
            for: 4
        )
        quickView.refresh()
        buttons = descendants(quickView).compactMap { $0 as? NSButton }
        require(buttons.contains {
            $0.accessibilityLabel() == "Change application for Command+4, currently Editor" && $0.isEnabled
        }, "assigned slot announces current application")
        require(buttons.contains {
            $0.accessibilityLabel() == "Clear application from Command+4, Editor" && $0.isEnabled
        }, "assigned slot enables a slot-specific Clear action")
        quick.clearAssignment(for: 4)
        quickView.refresh()
        require(descendants(quickView).compactMap { $0 as? NSButton }.contains {
            $0.accessibilityLabel() == "Assign application to Command+4" && $0.isEnabled
        }, "clearing restores the initial dynamic label")
        defaults.set(["displayName": "Damaged"], forKey: "quickLaunch.slot.4")
        quickView.refresh()
        let invalidButtons = descendants(quickView).compactMap { $0 as? NSButton }
        require(invalidButtons.contains {
            $0.accessibilityLabel() == "Change application for Command+4, currently Unavailable Assignment"
                && $0.isEnabled
        }, "malformed assigned slot must remain visibly configured")
        require(invalidButtons.contains {
            $0.accessibilityLabel() == "Clear application from Command+4, Unavailable Assignment"
                && $0.isEnabled
        }, "malformed assignment must be user-recoverable through Clear")
        quick.clearAssignment(for: 4)
        quickView.refresh()

        let ordinaryButtons = views.compactMap { $0 as? NSButton }
            .filter { candidate in !buttons.contains(where: { $0 === candidate }) }
        require(ordinaryButtons.allSatisfy {
            !($0.accessibilityLabel() ?? $0.title).isEmpty
        }, "other interactive buttons retain readable native purposes")

        settings.glassDarkness = 83
        settings.selectedIconZoom = 130
        controller.showWindow(nil)
        require(sliders.first { $0.accessibilityLabel() == "Glass Darkness" }?
                .accessibilityValueDescription() == "83%", "refreshed slider value updates")
        require(sliders.first { $0.accessibilityLabel() == "Selected Icon Zoom" }?
                .accessibilityValueDescription() == "130%", "refreshed zoom value updates")
        controller.window?.orderOut(nil)
        print("SettingsAccessibilityTests passed")
    }
}
