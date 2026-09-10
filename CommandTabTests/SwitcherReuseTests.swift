import AppKit
import CoreGraphics

@main
struct SwitcherReuseTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func window(id: CGWindowID, pid: pid_t) -> WindowModel {
        WindowModel(
            id: id,
            pid: pid,
            bundleIdentifier: "probe.\(pid)",
            appName: "App-\(pid)",
            title: "Window-\(id)",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            displayID: CGMainDisplayID(),
            spaceIDs: [3],
            iconKey: "probe.\(pid)"
        )
    }

    static func panel(of controller: SwitcherPanelController) -> NSPanel? {
        guard let value = Mirror(reflecting: controller).children.first(where: { $0.label == "panel" })?.value else { return nil }
        return Mirror(reflecting: value).children.first?.value as? NSPanel
    }

    static func itemViews(of controller: SwitcherPanelController) -> [SwitcherItemView] {
        Mirror(reflecting: controller).children.first(where: { $0.label == "itemViews" })?.value as? [SwitcherItemView] ?? []
    }

    static func allText(in view: NSView) -> [String] {
        var values: [String] = []
        if let field = view as? NSTextField { values.append(field.stringValue) }
        for child in view.subviews { values.append(contentsOf: allText(in: child)) }
        return values
    }

    static func main() {
        _ = NSApplication.shared
        let controller = SwitcherPanelController()
        let firstWindows = [
            window(id: 100, pid: 10),
            window(id: 101, pid: 11),
            window(id: 102, pid: 12)
        ]
        controller.show(windows: firstWindows, selectedIndex: 1, sessionID: 1)
        guard let firstPanel = panel(of: controller), let firstRoot = firstPanel.contentView,
              let firstStack = firstRoot.subviews.compactMap({ $0 as? NSStackView }).first else {
            fputs("FAIL: initial stable hierarchy unavailable\n", stderr)
            exit(1)
        }
        let firstItems = itemViews(of: controller)
        require(firstItems.count == 3, "initial item pool must match required capacity")

        controller.close()
        let secondWindows = [
            window(id: 200, pid: 20),
            window(id: 201, pid: 21),
            window(id: 202, pid: 22)
        ]
        controller.show(windows: secondWindows, selectedIndex: 0, sessionID: 2)
        guard let secondPanel = panel(of: controller), let secondRoot = secondPanel.contentView,
              let secondStack = secondRoot.subviews.compactMap({ $0 as? NSStackView }).first else {
            fputs("FAIL: repeated stable hierarchy unavailable\n", stderr)
            exit(1)
        }
        let secondItems = itemViews(of: controller)
        require(firstPanel === secondPanel, "NSPanel instance must be reused")
        require(firstRoot === secondRoot, "root content view must be reused")
        require(firstStack === secondStack, "stack view must be reused")
        require(firstItems.count == secondItems.count, "pool capacity must stay stable when sufficient")
        require(
            zip(firstItems, secondItems).allSatisfy { $0 === $1 },
            "existing SwitcherItemViews must be reused when capacity is sufficient"
        )

        controller.close()
        controller.show(windows: [window(id: 300, pid: 30)], selectedIndex: 0, sessionID: 3)
        let thirdItems = itemViews(of: controller)
        require(thirdItems.count == 3, "high-water-mark item pool must be retained")
        require(thirdItems[0] === firstItems[0], "first pooled item must be reused after count shrinks")
        require(secondStack.arrangedSubviews.count == 3, "pooled arranged views must not accumulate duplicates")
        require(secondStack.arrangedSubviews.filter { !$0.isHidden }.count == 1, "unused pooled views must be hidden without layout gaps")
        let text = allText(in: thirdItems[0])
        require(text.contains("Window-300"), "reused item must replace stale title")
        require(text.contains("App-30"), "reused item must replace stale app label")
        require(thirdItems[0].isSelected, "active reused item must carry current selection")
        require(!thirdItems[1].isSelected && !thirdItems[2].isSelected, "hidden pooled items must not keep stale selection")
        controller.close()
        print("SwitcherReuseTests passed")
    }
}
