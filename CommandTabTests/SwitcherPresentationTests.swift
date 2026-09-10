import AppKit
import CoreGraphics

@main
struct SwitcherPresentationTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func window(title: String = "README.md — Code") -> WindowModel {
        WindowModel(
            id: 901,
            pid: getpid(),
            bundleIdentifier: "test.commandtab.presentation",
            appName: "Code",
            title: title,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            displayID: CGMainDisplayID(),
            spaceIDs: [3],
            iconKey: "test.commandtab.presentation"
        )
    }

    static func textFields(in view: NSView) -> [NSTextField] {
        var fields = view is NSTextField ? [view as! NSTextField] : []
        for child in view.subviews { fields += textFields(in: child) }
        return fields
    }

    static func visibleTextFields(in view: NSView) -> [NSTextField] {
        textFields(in: view).filter { !$0.isHidden }
    }

    static func resolvedCGColor(_ color: NSColor, appearance: NSAppearance.Name) -> CGColor {
        let resolvedAppearance = NSAppearance(named: appearance)!
        var result: CGColor!
        resolvedAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    static func requireSemanticColors(_ item: SwitcherItemView, appearance: NSAppearance.Name) {
        item.appearance = NSAppearance(named: appearance)
        item.isSelected = false
        let unselected = visibleTextFields(in: item)
        require(unselected.count == 2, "Windows mode must keep two meaningful labels in \(appearance.rawValue)")
        require(unselected[0].textColor == .labelColor, "primary label must use semantic labelColor")
        require(unselected[1].textColor == .secondaryLabelColor, "secondary title must use semantic secondaryLabelColor")
        require(item.layer?.backgroundColor == resolvedCGColor(.controlBackgroundColor, appearance: appearance),
                "unselected item must resolve semantic controlBackgroundColor in its effective appearance")

        item.isSelected = true
        let selected = visibleTextFields(in: item)
        require(item.layer?.backgroundColor == resolvedCGColor(.selectedContentBackgroundColor, appearance: appearance),
                "selected item must resolve semantic selectedContentBackgroundColor in its effective appearance")
        require(selected.allSatisfy { $0.textColor == .alternateSelectedControlTextColor },
                "selected labels must use semantic selected-control foreground")
    }

    static func main() {
        _ = NSApplication.shared
        let icon = NSImage(size: NSSize(width: 32, height: 32))

        let applicationItem = SwitcherItemView(window: window(), icon: icon, mode: .applications)
        require(visibleTextFields(in: applicationItem).map(\.stringValue) == ["Code"],
                "Applications mode must show application name only")

        let windowsItem = SwitcherItemView(window: window(), icon: icon, mode: .windows)
        require(visibleTextFields(in: windowsItem).map(\.stringValue) == ["Code", "README.md — Code"],
                "Windows mode must show app name plus meaningful real window title")
        requireSemanticColors(windowsItem, appearance: .aqua)
        requireSemanticColors(windowsItem, appearance: .darkAqua)

        let duplicateTitle = SwitcherItemView(window: window(title: "  code  "), icon: icon, mode: .windows)
        require(visibleTextFields(in: duplicateTitle).map(\.stringValue) == ["Code"],
                "normalized app-name duplicate must never appear as secondary title")

        let chromeWindow = WindowModel(
            id: 902, pid: getpid(), bundleIdentifier: "com.google.Chrome",
            appName: "Chrome", title: " Chrome ",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            displayID: CGMainDisplayID(), spaceIDs: [3], iconKey: "com.google.Chrome"
        )
        let chromeDuplicate = SwitcherItemView(window: chromeWindow, icon: icon, mode: .windows)
        require(visibleTextFields(in: chromeDuplicate).map(\.stringValue) == ["Chrome"],
                "Chrome/Chrome must not duplicate the app name as a secondary title")

        let emptyTitle = SwitcherItemView(window: window(title: "   "), icon: icon, mode: .windows)
        require(visibleTextFields(in: emptyTitle).map(\.stringValue) == ["Code"],
                "missing window title must not invent secondary metadata")

        let controller = SwitcherPanelController()
        controller.show(windows: [window()], selectedIndex: 0, sessionID: 99, mode: .applications)
        let panelValue = Mirror(reflecting: controller).children.first { $0.label == "panel" }?.value
        let panel = panelValue.flatMap { Mirror(reflecting: $0).children.first?.value as? NSPanel }
        guard let root = panel?.contentView else {
            fputs("FAIL: switcher root unavailable\n", stderr)
            exit(1)
        }
        require(!(root is NSVisualEffectView), "switcher root must not use shared visual-effect HUD material")
        require(panel?.hasShadow == false, "transparent switcher panel must not cast a group shadow")
        controller.close()
        print("SwitcherPresentationTests passed")
    }
}
