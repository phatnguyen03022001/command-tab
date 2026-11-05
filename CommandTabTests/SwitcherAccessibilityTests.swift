import AppKit
import CoreGraphics

@main
struct SwitcherAccessibilityTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func window(_ id: CGWindowID, _ app: String, _ title: String) -> WindowModel {
        WindowModel(id: id, pid: pid_t(id), bundleIdentifier: "test.\(id)", appName: app,
                    title: title, frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                    displayID: CGMainDisplayID(), spaceIDs: [1], iconKey: "test.\(id)")
    }
    static func items(_ controller: SwitcherPanelController) -> [SwitcherItemView] {
        Mirror(reflecting: controller).children.first(where: { $0.label == "itemViews" })?.value
            as? [SwitcherItemView] ?? []
    }
    static func panel(_ controller: SwitcherPanelController) -> NSPanel? {
        guard let value = Mirror(reflecting: controller).children.first(where: { $0.label == "panel" })?.value else { return nil }
        return Mirror(reflecting: value).children.first?.value as? NSPanel
    }
    static func findList(_ view: NSView) -> NSView? {
        if view.isAccessibilityElement() && view.accessibilityRole() == .list { return view }
        for subview in view.subviews {
            if let result = findList(subview) { return result }
        }
        return nil
    }
    static func flush() { RunLoop.main.run(until: Date().addingTimeInterval(0.22)) }

    static func main() {
        _ = NSApplication.shared
        let suite = "commandtab.ax.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CommandTabSettings(defaults: defaults)
        let controller = SwitcherPanelController(settings: settings)
        var announcements: [String] = []
        controller.announceAccessibilitySelection = { _, label in announcements.append(label) }
        let initial = [window(101, "Editor", "Project"), window(102, "Browser", "Tab")]
        let wasActive = NSApp.isActive
        controller.show(windows: initial, selectedIndex: 0, sessionID: 1, mode: .applications)
        let first = items(controller)
        require(first.count == 2, "two AX items exposed")
        require(first[0].isAccessibilityElement(), "tile is an accessibility element")
        require(first[0].accessibilityRole() == .row, "tile is an AX row")
        require(first[0].accessibilityLabel() == "Editor", "app mode label includes application")
        require(first[0].isAccessibilitySelected(), "initial selection available to AX")
        require(!first[1].isAccessibilitySelected(), "nonselected tile reported correctly")
        guard let root = panel(controller)?.contentView, let list = findList(root) else {
            require(false, "switcher list is exposed to AX")
            return
        }
        require(list.accessibilityLabel() == "Command Tab switcher", "list has descriptive AX label")
        require(list.accessibilitySelectedChildren()?.contains(where: { ($0 as? NSView) === first[0] }) == true,
                "list exposes initial selected child")
        require(list.accessibilityChildren()?.contains(where: { ($0 as? NSView) === first[1] }) == true,
                "list exposes its tile children")
        require(NSApp.isActive == wasActive, "nonactivating panel must not activate application")
        flush()
        require(announcements == ["Command Tab switcher. Editor"], "initial presentation announces current item")

        controller.update(selectedIndex: 1, sessionID: 1)
        require(!first[0].isAccessibilitySelected() && first[1].isAccessibilitySelected(), "AX selected state follows navigation")
        require(list.accessibilitySelectedChildren()?.contains(where: { ($0 as? NSView) === first[1] }) == true,
                "list selected child moves with navigation")
        flush()
        require(announcements.last == "Browser" && announcements.count == 2, "navigation announces new item once")
        controller.update(selectedIndex: 1, sessionID: 1)
        flush()
        require(announcements.count == 2, "same selection does not repeat announcements")
        controller.update(selectedIndex: 0, sessionID: 1)
        controller.update(selectedIndex: 1, sessionID: 1)
        controller.update(selectedIndex: 0, sessionID: 1)
        flush()
        require(announcements.count == 3 && announcements.last == "Editor", "rapid navigation coalesces announcements")
        controller.close()

        // Window mode: only titles already included in the visible window item are exposed.
        controller.show(windows: [window(201, "Editor", "Document"),
                                  window(202, "Browser", "  Browser  "),
                                  window(203, "Terminal", "   ")],
                        selectedIndex: 0, sessionID: 2, mode: .windows)
        let windows = items(controller)
        require(windows[0] === first[0] && windows[1] === first[1], "pooled views reused")
        require(windows[0].accessibilityLabel() == "Editor, Document", "window title included once")
        require(windows[1].accessibilityLabel() == "Browser", "duplicate app title omitted")
        require(windows[2].accessibilityLabel() == "Terminal", "blank title omitted")
        require(windows[0].isAccessibilitySelected() && !windows[1].isAccessibilitySelected(), "reused selection refreshed")
        flush()
        require(announcements.last == "Command Tab switcher. Editor, Document", "new session announced")
        controller.close()
        controller.show(windows: [window(301, "Mail", "")], selectedIndex: 0, sessionID: 3, mode: .applications)
        require(items(controller)[0].accessibilityLabel() == "Mail", "pooled accessibility labels replaced")
        require(items(controller)[1].isHidden && !items(controller)[1].isAccessibilitySelected(), "hidden recycled view is not selected")
        controller.close()
        let count = announcements.count
        flush()
        require(announcements.count == count, "closed session cancels pending speech")
        print("SwitcherAccessibilityTests passed")
    }
}
