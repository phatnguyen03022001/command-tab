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
        let controller = SettingsWindowController(
            settings: .shared,
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
