import AppKit
import CoreGraphics

@main
struct SwitcherVisualAccessibilityTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func window(_ id: CGWindowID, title: String) -> WindowModel {
        WindowModel(id: id, pid: pid_t(id), bundleIdentifier: "test.\(id)",
                    appName: "Editor", title: title,
                    frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                    displayID: CGMainDisplayID(), spaceIDs: [1], iconKey: "test.\(id)")
    }

    static func item(_ id: CGWindowID, title: String,
                     metrics: SwitcherPresentationMetrics) -> SwitcherItemView {
        let result = SwitcherItemView(window: window(id, title: title),
                                      icon: NSImage(size: NSSize(width: 64, height: 64)),
                                      mode: metrics.mode, metrics: metrics)
        result.frame = CGRect(x: 0, y: 0, width: metrics.itemWidth, height: metrics.itemHeight)
        result.layoutSubtreeIfNeeded()
        return result
    }

    static func label(_ name: String, of view: SwitcherItemView) -> NSTextField {
        Mirror(reflecting: view).children.first(where: { $0.label == name })!.value as! NSTextField
    }

    static func aligned(_ items: [SwitcherItemView], _ title: String, compareLabels: Bool = true) {
        guard let first = items.first else { return }
        for item in items {
            item.layoutSubtreeIfNeeded()
            let iconY = item.iconContainer.convert(item.iconContainer.bounds, to: item).minY
            let firstIconY = first.iconContainer.convert(first.iconContainer.bounds, to: first).minY
            require(abs(iconY - firstIconY) < 0.5,
                    "\(title): icon container top stays aligned across mixed titles")
            if compareLabels {
                let appLabel = label("appNameLabel", of: item)
                let firstAppLabel = label("appNameLabel", of: first)
                require(abs(appLabel.convert(appLabel.bounds, to: item).minY -
                            firstAppLabel.convert(firstAppLabel.bounds, to: first).minY) < 0.5,
                        "\(title): app label top stays aligned across mixed titles")
            }
            require(abs(item.frame.height - first.frame.height) < 0.5,
                    "\(title): adaptive item dimensions stay consistent")
        }
    }

    static func panel(_ controller: SwitcherPanelController) -> NSPanel? {
        guard let value = Mirror(reflecting: controller).children.first(where: { $0.label == "panel" })?.value
        else { return nil }
        return Mirror(reflecting: value).children.first?.value as? NSPanel
    }

    static func items(_ controller: SwitcherPanelController) -> [SwitcherItemView] {
        Mirror(reflecting: controller).children.first(where: { $0.label == "itemViews" })?.value
            as? [SwitcherItemView] ?? []
    }

    static func alpha(_ view: NSView) -> CGFloat {
        guard let color = view.layer?.backgroundColor,
              let resolved = NSColor(cgColor: color) else { return -1 }
        return resolved.alphaComponent
    }

    static func main() {
        _ = NSApplication.shared
        // Real AppKit constraints with controlled synthetic windows; no real desktop windows or previews.
        for iconSize in [48, 72, 96] {
            for thumbnailAvailable in [false, true] {
                let metrics = SwitcherPresentationMetrics(
                    iconSize: CGFloat(iconSize), mode: .windows,
                    thumbnailsAvailable: thumbnailAvailable
                )
                let tiles = [
                    item(11, title: "Project – Documentation", metrics: metrics),
                    item(12, title: "", metrics: metrics),
                    item(13, title: "Editor", metrics: metrics),
                    item(14, title: String(repeating: "Very Long Window Title ", count: 20), metrics: metrics)
                ]
                aligned(tiles, "Windows \(iconSize), thumbnail eligibility \(thumbnailAvailable)")
                require(label("windowTitleLabel", of: tiles[0]).isHidden == false,
                        "meaningful title is visible")
                require(label("windowTitleLabel", of: tiles[1]).isHidden,
                        "missing title is hidden")
                require(label("windowTitleLabel", of: tiles[2]).isHidden,
                        "application name duplicate is hidden")
                let thumb = NSImage(size: NSSize(width: 240, height: 150))
                if thumbnailAvailable {
                    for (index, tile) in tiles.enumerated() {
                        tile.setThumbnail(thumb, forWindowID: CGWindowID(11 + index))
                        tile.layoutSubtreeIfNeeded()
                    }
                    aligned(tiles, "Windows \(iconSize), thumbnails present")
                    require(tiles.allSatisfy { !$0.previewContainer.isHidden },
                            "captured previews are all visible")
                    for tile in tiles {
                        require(abs(tile.previewContainer.convert(tile.previewContainer.bounds, to: tile).minY -
                                    tiles[0].previewContainer.convert(tiles[0].previewContainer.bounds, to: tiles[0]).minY) < 0.5,
                                "thumbnails share a baseline regardless of titles")
                    }
                    tiles[1].configure(window: window(22, title: ""), icon: NSImage(), mode: .windows)
                    tiles[1].layoutSubtreeIfNeeded()
                    // An individual capture may fail: keep icons aligned without imposing
                    // an empty thumbnail spacer on that item.
                    aligned(tiles, "Windows \(iconSize), mixed preview availability", compareLabels: false)
                } else {
                    require(tiles.allSatisfy { $0.previewContainer.isHidden },
                            "no capture permission reserves no blank preview")
                }
                tiles[0].isSelected = true
                tiles[0].layoutSubtreeIfNeeded()
                aligned(tiles, "Windows \(iconSize), selection change", compareLabels: !thumbnailAvailable)
            }
            let appMetrics = SwitcherPresentationMetrics(iconSize: CGFloat(iconSize), mode: .applications)
            let appTiles = [item(31, title: "Document", metrics: appMetrics),
                            item(32, title: "", metrics: appMetrics)]
            aligned(appTiles, "Applications \(iconSize)")
            appTiles.forEach { $0.setShowAppNames(false) }
            aligned(appTiles, "Applications \(iconSize), hidden app labels")
        }

        let suite = "commandtab.switcher.display.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CommandTabSettings(defaults: defaults)
        settings.appearanceMode = .light
        settings.showBackground = false
        settings.glassDarkness = 0
        settings.backgroundBlur = 0
        settings.selectedIconZoom = 175
        var preferences = SwitcherDisplayPreferences()
        var controller: SwitcherPanelController? = SwitcherPanelController(settings: settings)
        controller!.displayPreferencesProvider = { preferences }
        let models = [window(41, title: "Document"), window(42, title: ""),
                      window(43, title: "Editor")]
        controller!.show(windows: models, selectedIndex: 1, sessionID: 5, mode: .windows)
        guard let root = panel(controller!)?.contentView as? SwitcherPresentationRootView,
              let selected = items(controller!).dropFirst().first else {
            require(false, "synthetic presentation is available")
            return
        }
        require(root.materialContainer.isHidden && root.glassView.isHidden,
                "transparent preference leaves the panel background invisible")
        require(abs(alpha(label("appNameLabel", of: selected)) - 0.88) < 0.01,
                "transparent mode has local protective text backing instead of opaque panel")
        require(label("appNameLabel", of: selected).shadow == nil,
                "glyph backing does not stack with a redundant shadow")
        require(selected.iconContainer.layer!.sublayerTransform.m11 > 1.5,
                "normal mode respects configured selected zoom")

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for darkness in [0, 100] {
                for blur in [0, 100] {
                    settings.appearanceMode = appearance == .aqua ? .light : .dark
                    settings.applyAppearance()
                    settings.glassDarkness = darkness
                    settings.backgroundBlur = blur
                    controller!.show(windows: models, selectedIndex: 1, sessionID: 5, mode: .windows)
                    require(abs(alpha(label("windowTitleLabel", of: items(controller!)[0])) - 0.88) < 0.01,
                            "transparent text backing is independent of darkness and blur")
                }
            }
        }
        preferences.reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        require(abs(selected.iconContainer.layer!.sublayerTransform.m11 - 1.0) < 0.01,
                "Reduce Motion eliminates selected zoom")
        require(items(controller!).allSatisfy {
            abs($0.layer!.sublayerTransform.m41) < 0.01
        }, "Reduce Motion eliminates neighbor displacement")
        require(selected.isAccessibilitySelected(), "Reduce Motion preserves selection")
        require(settings.selectedIconZoom == 175, "Reduce Motion never mutates user zoom")

        preferences.reduceTransparency = true
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        require(!root.materialContainer.isHidden && root.glassView.isHidden,
                "Reduce Transparency substitutes native material with opaque backing")
        require(abs(alpha(root.materialContainer) - 1) < 0.01,
                "accessibility backing is fully opaque")
        require(root.foregroundView.superview === root || root.foregroundView.superview === root.glassView,
                "foreground remains accessible after material switching")
        require(alpha(label("appNameLabel", of: selected)) == 0,
                "opaque accessibility surface removes redundant per-label backing")
        require(!settings.showBackground && settings.glassDarkness == 100 && settings.backgroundBlur == 100,
                "system preferences never overwrite configured material settings")

        preferences.increaseContrast = true
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        require(selected.selectionBackgroundView.layer!.borderWidth == 2,
                "Increase Contrast supplies a stronger selection outline")
        require(label("windowTitleLabel", of: selected).textColor == NSColor.labelColor.withAlphaComponent(1),
                "Increase Contrast uses primary semantic color for secondary titles")
        preferences = .init()
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        require(root.materialContainer.isHidden && root.glassView.isHidden,
                "dynamic preference reset restores transparent mode")
        require(selected.iconContainer.layer!.sublayerTransform.m11 > 1.5,
                "dynamic preference reset restores configured zoom")
        require(selected.selectionBackgroundView.layer!.borderWidth == 1,
                "standard selection border returns after contrast preference reset")
        controller!.close()
        weak let releasedController = controller
        controller = nil
        require(releasedController == nil, "display-preference observer does not retain its controller")
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        print("SwitcherVisualAccessibilityTests passed")
    }
}
