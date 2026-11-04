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

    static func reflectedView(named name: String, in item: SwitcherItemView) -> NSView? {
        Mirror(reflecting: item).children.first(where: { $0.label == name })?.value as? NSView
    }

    static func iconContainer(in item: SwitcherItemView) -> NSView {
        guard let view = reflectedView(named: "iconContainer", in: item) else {
            fputs("FAIL: switcher item must expose a dedicated iconContainer\n", stderr)
            exit(1)
        }
        return view
    }

    static func selectionBackgroundView(in item: SwitcherItemView) -> NSView {
        guard let view = reflectedView(named: "selectionBackgroundView", in: item) else {
            fputs("FAIL: switcher item must expose a structural selectionBackgroundView\n", stderr)
            exit(1)
        }
        return view
    }

    static func uniformScale(of view: NSView) -> CGFloat {
        guard let transform = view.layer?.sublayerTransform else { return 1.0 }
        require(abs(transform.m11 - transform.m22) < 0.0001, "iconContainer content scale must remain uniform")
        return transform.m11
    }

    static func hasCenterConstraint(in container: NSView, child: NSView, attribute: NSLayoutConstraint.Attribute) -> Bool {
        container.constraints.contains { constraint in
            let forward = (constraint.firstItem as? NSView) === child
                && constraint.firstAttribute == attribute
                && (constraint.secondItem as? NSView) === container
                && constraint.secondAttribute == attribute
            let reverse = (constraint.secondItem as? NSView) === child
                && constraint.secondAttribute == attribute
                && (constraint.firstItem as? NSView) === container
                && constraint.firstAttribute == attribute
            return forward || reverse
        }
    }

    static func requireApprovedColors(_ item: SwitcherItemView, appearance: NSAppearance.Name) {
        item.appearance = NSAppearance(named: appearance)
        let selectionView = selectionBackgroundView(in: item)
        guard let selectionLayer = selectionView.layer else {
            fputs("FAIL: selection background must be layer-backed\n", stderr)
            exit(1)
        }

        item.isSelected = false
        let unselected = visibleTextFields(in: item)
        require(unselected.count == 2, "Windows mode must keep two meaningful labels in \(appearance.rawValue)")
        require(rgba(item.layer?.backgroundColor).alpha == 0, "unselected item base must be clear")
        require(rgba(selectionLayer.backgroundColor).alpha == 0, "unselected selection fill must be clear")
        require(selectionLayer.borderWidth == 0 && selectionLayer.borderColor == nil, "unselected selection pod must have no edge")
        require(selectionLayer.shadowOpacity == 0, "unselected selection pod must cast no shadow")

        item.isSelected = true
        let selected = visibleTextFields(in: item)
        let fill = rgba(selectionLayer.backgroundColor)
        guard let borderColor = selectionLayer.borderColor, let shadowColor = selectionLayer.shadowColor else {
            fputs("FAIL: selected pod must expose light edge plus dark outer separation\n", stderr)
            exit(1)
        }
        let edge = rgba(borderColor)
        let shadow = rgba(shadowColor)
        let fillSpread = max(fill.red, fill.green, fill.blue) - min(fill.red, fill.green, fill.blue)
        let edgeSpread = max(edge.red, edge.green, edge.blue) - min(edge.red, edge.green, edge.blue)
        let shadowSpread = max(shadow.red, shadow.green, shadow.blue) - min(shadow.red, shadow.green, shadow.blue)
        require(rgba(item.layer?.backgroundColor).alpha == 0, "selected item base must remain clear to prevent full-item cards")
        require(fill.alpha > 0 && fill.alpha <= 0.15, "selected pod must use subtle bounded neutral fill")
        require(fillSpread < 0.01, "selected pod fill must be achromatic")
        require(edge.alpha >= 0.15 && edge.alpha <= 0.31 && edgeSpread < 0.01, "selected pod must use a subtle achromatic light edge")
        require(edge.red > 0.95 && edge.green > 0.95 && edge.blue > 0.95, "selected primary edge must be light in both appearances")
        require(selectionLayer.borderWidth >= 0.9 && selectionLayer.borderWidth <= 1.1, "selected pod edge must remain 1pt-class")
        require(shadow.red < 0.05 && shadow.green < 0.05 && shadow.blue < 0.05 && shadowSpread < 0.01, "outer separation must be achromatic black")
        require(selectionLayer.shadowOpacity > 0 && selectionLayer.shadowOpacity <= 0.40, "outer separation must be subtle")
        require(selectionLayer.shadowRadius > 0 && selectionLayer.shadowRadius <= 2.5, "outer separation must stay tight")
        require(selectionLayer.shadowOffset == .zero, "outer separation must be centered, not a drop shadow")
        require(CATransform3DIsIdentity(selectionLayer.transform), "selection pod must not own an independent transform")
        let container = iconContainer(in: item)
        let selectedScale = uniformScale(of: container)
        require(abs(selectedScale - 1.15) < 0.0001, "standalone selected iconContainer must use canonical default scale 1.15")
        require(container.layer?.masksToBounds == false, "selected iconContainer must not clip its enlarged icon or pod")
        require(CATransform3DIsIdentity(container.layer?.transform ?? CATransform3DIdentity), "iconContainer frame transform must remain identity")
        require(selected.allSatisfy { $0.superview !== container }, "labels must remain outside the scaled iconContainer")

        let metricsBeforeBackgroundToggle = item.metrics
        item.setBackgroundVisible(false)
        require(abs(uniformScale(of: container) - selectedScale) < 0.0001, "Background OFF must preserve selected scale")
        item.setBackgroundVisible(true)
        require(abs(uniformScale(of: container) - selectedScale) < 0.0001, "Background ON must preserve selected scale")
        require(item.metrics == metricsBeforeBackgroundToggle, "background toggles must not mutate layout metrics")

        let dark = appearance == .darkAqua
        let fillLuminance = (fill.red + fill.green + fill.blue) / 3
        require(dark ? fillLuminance > 0.95 : fillLuminance < 0.05, "Light and Dark must use opposite neutral fill polarity")
        require(selected.allSatisfy { abs(rgba(resolvedCGColor($0.textColor!, appearance: appearance)).alpha - 1.0) < 0.001 }, "selected labels must remain fully opaque")
        require(imageViews(in: item).allSatisfy { abs($0.alphaValue - 1.0) < 0.001 }, "selected icon must remain fully opaque")
        require(item.layer?.borderWidth == 0 && item.layer?.shadowOpacity == 0, "item layer itself must remain undecorated")

        let selectedFillAlpha = fill.alpha
        item.setBackgroundVisible(false)
        item.isSelected = true
        require(abs(rgba(selectionLayer.backgroundColor).alpha - selectedFillAlpha) < 0.001, "selection must survive Background OFF unchanged")
        require(abs(uniformScale(of: container) - selectedScale) < 0.0001, "selected scale must survive Background OFF unchanged")
        item.setBackgroundVisible(true)
        require(abs(rgba(selectionLayer.backgroundColor).alpha - selectedFillAlpha) < 0.001, "selection must survive Background ON unchanged")
        require(abs(uniformScale(of: container) - selectedScale) < 0.0001, "selected scale must survive Background ON unchanged")

        item.isSelected = false
        require(abs(uniformScale(of: container) - 1.0) < 0.0001, "unselected iconContainer must reset exactly to 1.00")
    }

    static func main() {
        _ = NSApplication.shared
        let icon = NSImage(size: NSSize(width: 32, height: 32))

        let applicationItem = SwitcherItemView(window: window(), icon: icon, mode: .applications)
        require(applicationItem.layer?.masksToBounds == false, "SwitcherItemView must not clip selected iconContainer overflow")
        require(visibleTextFields(in: applicationItem).map(\.stringValue) == ["Code"],
                "Applications mode must show application name only")
        require(imageViews(in: applicationItem).contains { !$0.isHidden && $0.image != nil },
                "Applications mode must keep a visible application icon")
        require(!applicationItem.subviews.contains(where: { String(describing: type(of: $0)).contains("Glass") }),
                "item views must not allocate per-item NSGlassEffectView")

        let appIconContainer = iconContainer(in: applicationItem)
        let appSelection = selectionBackgroundView(in: applicationItem)
        guard let appImage = imageViews(in: applicationItem).first else {
            fputs("FAIL: application item image view unavailable\n", stderr)
            exit(1)
        }
        require(appSelection.superview === appIconContainer, "selection background must live inside iconContainer")
        require(appImage.superview === appIconContainer, "imageView must live inside iconContainer")
        let selectionIndex = appIconContainer.subviews.firstIndex { $0 === appSelection }
        let imageIndex = appIconContainer.subviews.firstIndex { $0 === appImage }
        require(selectionIndex != nil && imageIndex != nil && selectionIndex! < imageIndex!,
                "selection background must be explicitly behind imageView")
        require(hasCenterConstraint(in: appIconContainer, child: appSelection, attribute: .centerX),
                "selection background must be structurally centerX-anchored to iconContainer")
        require(hasCenterConstraint(in: appIconContainer, child: appSelection, attribute: .centerY),
                "selection background must be structurally centerY-anchored to iconContainer")
        require(hasCenterConstraint(in: appIconContainer, child: appImage, attribute: .centerX),
                "imageView must be structurally centerX-anchored to iconContainer")
        require(hasCenterConstraint(in: appIconContainer, child: appImage, attribute: .centerY),
                "imageView must be structurally centerY-anchored to iconContainer")

        for iconSize in [48, 72, 96] {
            let metrics = SwitcherPresentationMetrics(iconSize: CGFloat(iconSize), itemSpacing: 10)
            let item = SwitcherItemView(window: window(), icon: icon, mode: .applications, metrics: metrics)
            let before = item.metrics
            item.isSelected = true
            let selectedScale = uniformScale(of: iconContainer(in: item))
            require(abs(selectedScale - 1.15) < 0.0001, "selected scale must use canonical 1.15 at \(iconSize)pt")
            require(item.metrics == before, "selected scale must not mutate \(iconSize)pt layout metrics")
            require(item.metrics.iconSize == CGFloat(iconSize), "selected scale must not mutate icon-size preference")
            require(item.metrics.itemSpacing == 10, "selected scale must not mutate App Spacing")
            require(item.layer?.masksToBounds == false && iconContainer(in: item).layer?.masksToBounds == false,
                    "selected visual may extend beyond its unscaled slot without clipping at \(iconSize)pt")
            item.isSelected = false
            require(abs(uniformScale(of: iconContainer(in: item)) - 1.0) < 0.0001, "unselected \(iconSize)pt iconContainer must reset to 1.00")
        }

        let adaptiveSelectedItem = SwitcherItemView(window: window(), icon: icon, mode: .applications,
                                                    metrics: SwitcherPresentationMetrics(iconSize: 72, itemSpacing: 10))
        adaptiveSelectedItem.isSelected = true
        adaptiveSelectedItem.applyMetrics(SwitcherPresentationMetrics(iconSize: 48, itemSpacing: 4))
        let adaptiveContainer = iconContainer(in: adaptiveSelectedItem)
        let adaptiveTransform = adaptiveContainer.layer?.sublayerTransform ?? CATransform3DIdentity
        let adaptiveCenter = adaptiveSelectedItem.metrics.selectionPodSize * 0.5
        let mappedAdaptiveX = adaptiveTransform.m11 * adaptiveCenter + adaptiveTransform.m21 * adaptiveCenter + adaptiveTransform.m41
        let mappedAdaptiveY = adaptiveTransform.m12 * adaptiveCenter + adaptiveTransform.m22 * adaptiveCenter + adaptiveTransform.m42
        require(abs(mappedAdaptiveX - adaptiveCenter) < 0.001 && abs(mappedAdaptiveY - adaptiveCenter) < 0.001,
                "adaptive metric changes must preserve centered selected scale without cumulative drift")

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
        guard let root = panel?.contentView as? SwitcherPresentationRootView else {
            fputs("FAIL: switcher root unavailable or not SwitcherPresentationRootView\n", stderr)
            exit(1)
        }
        if #available(macOS 26.0, *) {
            guard let glassRoot = root.glassView as? NSGlassEffectView else {
                fputs("FAIL: switcher must use one shared native glass container on macOS 26+\n", stderr)
                exit(1)
            }
            require(glassRoot.style == .clear, "shared switcher glass container must use clear style")
            require(glassRoot.cornerRadius == 28, "shared switcher glass container must use 28pt corner radius")
            require(glassRoot.tintColor == nil, "shared switcher glass container must have nil tintColor")
            require(glassRoot.contentView === root.foregroundView, "native glass must own the reusable switcher content via contentView")
            if #available(macOS 27.0, *) {
                require(glassRoot.effectIsInteractive, "shared switcher glass must enable interactive behavior for the interactive switcher surface")
            }
            require(root.foregroundView.superview !== root, "native glass content must not remain a sibling behind the effect")
        } else {
            guard let materialRoot = root.glassView as? NSVisualEffectView else {
                fputs("FAIL: switcher must use one shared native visual-effect container on earlier macOS\n", stderr)
                exit(1)
            }
            require(materialRoot.material == .popover, "shared switcher container must use popover material")
            require((materialRoot.layer?.cornerRadius ?? 0) > 0, "shared switcher container must be rounded")
        }
        require(root.foregroundView is NSClipView, "foreground must remain the bounded overflow viewport")
        require(root.layer?.cornerRadius == 0, "modern presentation root must not own glass corner treatment")
        require(root.layer?.masksToBounds == false, "presentation root must not clip the native glass perimeter")
        require(panel?.hasShadow == true, "shared native switcher panel must use native panel shadow")
        let defaultMetrics = SwitcherPresentationMetrics(iconSize: 72, itemSpacing: 10)
        require(panel?.frame.width == defaultMetrics.contentWidth(itemCount: 1),
                "single-item panel width must match stable layout metrics")

        controller.show(windows: [window(), window()], selectedIndex: 0, sessionID: 100, mode: .applications)
        require(panel?.frame.width == defaultMetrics.contentWidth(itemCount: 2),
                "two-item panel width must match stable layout metrics")

        controller.show(windows: [window(), window(), window()], selectedIndex: 0, sessionID: 101, mode: .applications)
        require(panel?.frame.width == defaultMetrics.contentWidth(itemCount: 3),
                "three-item panel width must match stable layout metrics")

        controller.close()
        print("SwitcherPresentationTests passed")
    }
}
