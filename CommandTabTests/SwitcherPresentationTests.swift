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

    static func imageViews(in view: NSView) -> [NSImageView] {
        var images = view is NSImageView ? [view as! NSImageView] : []
        for child in view.subviews { images += imageViews(in: child) }
        return images
    }

    static func resolvedCGColor(_ color: NSColor, appearance: NSAppearance.Name) -> CGColor {
        let resolvedAppearance = NSAppearance(named: appearance)!
        var result: CGColor!
        resolvedAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    static func rgba(_ color: CGColor?) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        guard let color,
              let converted = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else {
            fputs("FAIL: color could not resolve to device RGB\n", stderr)
            exit(1)
        }
        return (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
    }

    static func selectionFillLayer(in item: SwitcherItemView) -> CALayer {
        guard let layer = Mirror(reflecting: item).children.first(where: { $0.label == "selectionFillLayer" })?.value as? CALayer else {
            fputs("FAIL: switcher item must expose one dedicated selection fill layer\n", stderr)
            exit(1)
        }
        return layer
    }

    static func requireApprovedColors(_ item: SwitcherItemView, appearance: NSAppearance.Name) {
        item.appearance = NSAppearance(named: appearance)
        let fillLayer = selectionFillLayer(in: item)

        item.isSelected = false
        let unselected = visibleTextFields(in: item)
        require(unselected.count == 2, "Windows mode must keep two meaningful labels in \(appearance.rawValue)")
        require(unselected[0].textColor == .labelColor, "primary label must use semantic labelColor")
        require(unselected[1].textColor == .secondaryLabelColor, "secondary title must use semantic secondaryLabelColor")
        require(rgba(item.layer?.backgroundColor).alpha == 0, "unselected item base must be clear")
        require(rgba(fillLayer.backgroundColor).alpha == 0, "unselected selection fill must be clear")
        require(item.layer?.borderWidth == 0, "unselected item must not have a border")
        require(item.layer?.shadowOpacity == 0, "unselected item must not cast a shadow")

        item.isSelected = true
        let selected = visibleTextFields(in: item)
        let fill = rgba(fillLayer.backgroundColor)
        require(rgba(item.layer?.backgroundColor).alpha == 0, "selected item base must remain clear to prevent double fill")
        require(fill.alpha > 0.9, "selected item must have exactly one visible selection fill")
        require(abs(fill.red - fill.green) < 0.02 && abs(fill.green - fill.blue) < 0.02,
                "selection fill must remain neutral monochrome rather than accent-colored")
        require(fillLayer.backgroundColor != resolvedCGColor(.selectedContentBackgroundColor, appearance: appearance),
                "selection fill must not use selectedContentBackgroundColor")

        let dark = appearance == .darkAqua
        let fillLuminance = (fill.red + fill.green + fill.blue) / 3
        require(dark ? fillLuminance > 0.8 : fillLuminance < 0.2,
                "selection fill must be near-white in Dark and near-black in Light")
        for label in selected {
            let text = rgba(label.textColor?.cgColor)
            let textLuminance = (text.red + text.green + text.blue) / 3
            require(dark ? textLuminance < 0.2 : textLuminance > 0.8,
                    "selected text must contrast with the monochrome selection fill")
        }
    }

    static func main() {
        _ = NSApplication.shared
        let icon = NSImage(size: NSSize(width: 32, height: 32))

        let applicationItem = SwitcherItemView(window: window(), icon: icon, mode: .applications)
        require(visibleTextFields(in: applicationItem).map(\.stringValue) == ["Code"],
                "Applications mode must show application name only")
        require(imageViews(in: applicationItem).contains { !$0.isHidden && $0.image != nil },
                "Applications mode must keep a visible application icon")

        let windowsItem = SwitcherItemView(window: window(), icon: icon, mode: .windows)
        require(visibleTextFields(in: windowsItem).map(\.stringValue) == ["Code", "README.md — Code"],
                "Windows mode must show app name plus meaningful real window title")
        require(imageViews(in: windowsItem).contains { !$0.isHidden && $0.image != nil },
                "Windows mode must keep a visible application icon")
        requireApprovedColors(windowsItem, appearance: .aqua)
        requireApprovedColors(windowsItem, appearance: .darkAqua)

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
        guard let materialRoot = root as? NSVisualEffectView else {
            fputs("FAIL: switcher must use one shared native visual-effect container\n", stderr)
            exit(1)
        }
        require(materialRoot.material == .popover, "shared switcher container must use popover material")
        require((materialRoot.layer?.cornerRadius ?? 0) > 0, "shared switcher container must be rounded")
        require((materialRoot.layer?.borderWidth ?? 0) > 0, "shared switcher container must have a subtle border")
        let border = rgba(materialRoot.layer?.borderColor)
        let separator = rgba(resolvedCGColor(.separatorColor, appearance: materialRoot.effectiveAppearance.name))
        require(abs(border.red - separator.red) < 0.05 && abs(border.green - separator.green) < 0.05 && abs(border.blue - separator.blue) < 0.05,
                "shared switcher border must derive from semantic separator color")
        require(panel?.hasShadow == true, "shared native switcher panel must use native panel shadow")
        controller.close()
        print("SwitcherPresentationTests passed")
    }
}
