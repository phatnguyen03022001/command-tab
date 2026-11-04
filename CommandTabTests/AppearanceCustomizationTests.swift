import AppKit
import CoreGraphics
import Foundation

@main
struct AppearanceCustomizationTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }


    static func reflectedView(named name: String, in item: SwitcherItemView) -> NSView? {
        Mirror(reflecting: item).children.first(where: { $0.label == name })?.value as? NSView
    }

    static func imageViews(in view: NSView) -> [NSImageView] {
        var result = view is NSImageView ? [view as! NSImageView] : []
        for child in view.subviews { result += imageViews(in: child) }
        return result
    }

    static func main() {
        _ = NSApplication.shared
        let suite = "commandtab.settings.appearance.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fputs("FAIL: test defaults unavailable\n", stderr)
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        // 1. Defaults
        let settings = CommandTabSettings(defaults: defaults)
        require(settings.showBackground, "Show Background default must be ON")
        require(settings.glassDarkness == 10, "Glass Darkness default must be 10")
        require(settings.backgroundBlur == 0, "Background Blur default must be 0")
        require(settings.iconSize == 72, "Icon Size default must be 72")
        require(settings.appSpacing == 10, "App Spacing default must be 10")
        require(settings.selectedIconZoom == 115, "Selected Icon Zoom default must be 115")
        require(abs(settings.selectedIconScale - 1.15) < 0.0001, "Selected Icon Zoom default must derive scale 1.15")
        require(settings.showAppNames, "Show App Names default must be ON")

        // 3. Glass Darkness persists
        settings.glassDarkness = 45
        require(settings.glassDarkness == 45, "Glass Darkness must persist value")
        require(defaults.integer(forKey: "glassDarkness") == 45, "Glass Darkness must write to defaults")

        // 3. Glass Darkness clamps 0...100
        settings.glassDarkness = -10
        require(settings.glassDarkness == 0, "Glass Darkness must clamp lower bound to 0")
        settings.glassDarkness = 150
        require(settings.glassDarkness == 100, "Glass Darkness must clamp upper bound to 100")

        // 4. Light smoke alpha derivation (smokeAlpha = darkness * 0.30)
        settings.glassDarkness = 67
        let lightAlpha67 = settings.smokeAlpha(isDark: false)
        require(abs(lightAlpha67 - 0.201) < 0.005, "Light smoke alpha at 67 must be ~0.20 (actual: \(lightAlpha67))")
        settings.glassDarkness = 100
        let lightAlpha100 = settings.smokeAlpha(isDark: false)
        require(abs(lightAlpha100 - 0.30) < 0.001, "Light smoke alpha at 100 must be 0.30 (actual: \(lightAlpha100))")
        settings.glassDarkness = 0
        require(settings.smokeAlpha(isDark: false) == 0.0, "Light smoke alpha at 0 must be 0.0")

        // 5. Dark smoke alpha derivation (smokeAlpha = darkness * 0.18)
        settings.glassDarkness = 67
        let darkAlpha67 = settings.smokeAlpha(isDark: true)
        require(abs(darkAlpha67 - 0.1206) < 0.005, "Dark smoke alpha at 67 must be ~0.12 (actual: \(darkAlpha67))")
        settings.glassDarkness = 100
        let darkAlpha100 = settings.smokeAlpha(isDark: true)
        require(abs(darkAlpha100 - 0.18) < 0.001, "Dark smoke alpha at 100 must be 0.18 (actual: \(darkAlpha100))")
        settings.glassDarkness = 0
        require(settings.smokeAlpha(isDark: true) == 0.0, "Dark smoke alpha at 0 must be 0.0")

        // 6. Background Blur persists & clamps
        settings.backgroundBlur = 80
        require(settings.backgroundBlur == 80, "Background Blur must persist value")
        require(defaults.integer(forKey: "backgroundBlur") == 80, "Background Blur must write to defaults")
        settings.backgroundBlur = -20
        require(settings.backgroundBlur == 0, "Background Blur must clamp lower bound to 0")
        settings.backgroundBlur = 200
        require(settings.backgroundBlur == 100, "Background Blur must clamp upper bound to 100")

        // 7. Blur controls extra backing diffusion while native clear glass remains the primary blur.
        settings.backgroundBlur = 100
        require(abs(settings.diffusionBackingAlpha - 0.25) < 0.001, "Blur 100 must map to maximum extra diffusion alpha 0.25")
        settings.backgroundBlur = 50
        require(abs(settings.diffusionBackingAlpha - 0.125) < 0.001, "Blur 50 must map to extra diffusion alpha 0.125")
        settings.backgroundBlur = 0
        require(settings.diffusionBackingAlpha == 0.0, "Blur 0 must map to backing alpha 0.0")

        // 8. Icon Size persists, clamps 48...96, obeys 4pt steps
        settings.iconSize = 64
        require(settings.iconSize == 64, "Icon Size must persist value")
        require(defaults.integer(forKey: "iconSize") == 64, "Icon Size must write to defaults")

        settings.iconSize = 30
        require(settings.iconSize == 48, "Icon Size must clamp lower bound to 48")
        settings.iconSize = 120
        require(settings.iconSize == 96, "Icon Size must clamp upper bound to 96")

        // 4pt step normalization
        require(CommandTabSettings.normalizeIconSize(50) == 52, "50 must snap to 52")
        require(CommandTabSettings.normalizeIconSize(51) == 52, "51 must snap to 52")
        require(CommandTabSettings.normalizeIconSize(49) == 48, "49 must snap to 48")
        require(CommandTabSettings.normalizeIconSize(73) == 72, "73 must snap to 72")
        require(CommandTabSettings.normalizeIconSize(75) == 76, "75 must snap to 76")

        // App Spacing persists independently, clamps 4...24, and snaps to 2pt steps.
        settings.appSpacing = 18
        require(settings.appSpacing == 18, "App Spacing must persist independently")
        require(defaults.integer(forKey: "appSpacing") == 18, "App Spacing must write to defaults")
        settings.iconSize = 48
        require(settings.appSpacing == 18, "Icon Size changes must not overwrite App Spacing")
        settings.appSpacing = 1
        require(settings.appSpacing == 4, "App Spacing must clamp lower bound to 4")
        settings.appSpacing = 99
        require(settings.appSpacing == 24, "App Spacing must clamp upper bound to 24")
        require(CommandTabSettings.normalizeAppSpacing(11) == 12, "11 must snap to 12")
        require(CommandTabSettings.normalizeAppSpacing(9) == 10, "9 must snap to 10")

        // Selected Icon Zoom persists independently and clamps exactly to 100...175.
        settings.selectedIconZoom = 119
        require(settings.selectedIconZoom == 119, "Selected Icon Zoom must persist value")
        require(defaults.integer(forKey: "selectedIconZoom") == 119, "Selected Icon Zoom must write to defaults")
        require(abs(settings.selectedIconScale - 1.19) < 0.0001, "Selected Icon Zoom must derive runtime scale")
        settings.selectedIconZoom = 80
        require(settings.selectedIconZoom == 100, "Selected Icon Zoom must clamp lower bound to 100")
        settings.selectedIconZoom = 175
        require(settings.selectedIconZoom == 175, "Selected Icon Zoom must persist advertised upper bound 175")
        require(abs(settings.selectedIconScale - 1.75) < 0.0001, "175% must derive exact selected scale 1.75")
        settings.selectedIconZoom = 200
        require(settings.selectedIconZoom == 175, "Selected Icon Zoom must clamp upper bound to 175")
        require(CommandTabSettings.normalizeSelectedIconZoom(99) == 100, "zoom 99 must clamp to 100")
        require(CommandTabSettings.normalizeSelectedIconZoom(176) == 175, "zoom 176 must clamp to 175")
        require(CommandTabSettings.normalizeSelectedIconZoom(117) == 117, "zoom must preserve 1% steps")

        settings.showAppNames = false
        require(!settings.showAppNames, "Show App Names must persist OFF")
        require(defaults.bool(forKey: "showAppNames") == false, "Show App Names must write to defaults")
        settings.showAppNames = true
        require(settings.showAppNames, "Show App Names must persist ON")

        // Show Background preserves stored Darkness/Blur values while OFF.
        settings.glassDarkness = 25
        settings.backgroundBlur = 30
        settings.showBackground = false
        require(!settings.showBackground, "Show Background must persist OFF")
        require(settings.glassDarkness == 25 && settings.backgroundBlur == 30,
                "Show Background OFF must preserve stored material values")
        settings.showBackground = true
        require(settings.glassDarkness == 25 && settings.backgroundBlur == 30,
                "Show Background ON must restore preserved material values")

        // 9. Metrics derivation
        let m48 = SwitcherPresentationMetrics(iconSize: 48)
        require(m48.iconSize == 48, "m48 iconSize must be 48")
        require(m48.selectionPodSize == 56, "m48 selectionPodSize must be 56")
        require(m48.itemWidth == 72, "m48 itemWidth must be 72")
        require(m48.itemHeight == 100, "m48 itemHeight must be 100")
        require(m48.panelHeight == 120, "m48 panelHeight must be 120")
        require(m48.itemSpacing == 10, "m48 itemSpacing must use preferred default 10 independently of icon size")

        let m72 = SwitcherPresentationMetrics(iconSize: 72)
        require(m72.iconSize == 72, "m72 iconSize must be 72")
        require(m72.selectionPodSize == 80, "m72 selectionPodSize must be 80")
        require(m72.itemWidth == 96, "m72 itemWidth must be 96")
        require(m72.itemHeight == 124, "m72 itemHeight must be 124")
        require(m72.panelHeight == 144, "m72 panelHeight must be 144")
        require(m72.itemSpacing == 10, "m72 itemSpacing must be 10")

        let m96 = SwitcherPresentationMetrics(iconSize: 96)
        require(m96.iconSize == 96, "m96 iconSize must be 96")
        require(m96.selectionPodSize == 104, "m96 selectionPodSize must be 104")
        require(m96.itemWidth == 120, "m96 itemWidth must be 120")
        require(m96.itemHeight == 148, "m96 itemHeight must be 148")
        require(m96.panelHeight == 168, "m96 panelHeight must be 168")
        require(m96.itemSpacing == 10, "m96 itemSpacing must use preferred default 10 independently of icon size")

        // 10. Reset Appearance
        // Change unrelated preferences first
        settings.showMenuBarIcon = false
        settings.revealDelay = .instant
        settings.displayScope = .activeOnly
        settings.switcherMode = .windows
        settings.appearanceMode = .dark

        // Change appearance preferences
        settings.showBackground = false
        settings.glassDarkness = 90
        settings.backgroundBlur = 75
        settings.iconSize = 88
        settings.appSpacing = 22
        settings.selectedIconZoom = 173
        settings.showAppNames = false

        settings.resetAppearance()

        // Verify appearance preferences reset to canonical defaults
        require(settings.showBackground, "Reset must restore Show Background to ON")
        require(settings.glassDarkness == 10, "Reset must restore glassDarkness to 10")
        require(settings.backgroundBlur == 0, "Reset must restore backgroundBlur to 0")
        require(settings.iconSize == 72, "Reset must restore iconSize to 72")
        require(settings.appSpacing == 10, "Reset must restore appSpacing to 10")
        require(settings.selectedIconZoom == 115, "Reset must restore Selected Icon Zoom to 115")
        require(settings.showAppNames, "Reset must restore Show App Names to ON")
        require(settings.appearanceMode == .system, "Reset must restore Appearance to System")

        // Verify unrelated preferences remain unchanged
        require(settings.showMenuBarIcon == false, "Reset must not alter showMenuBarIcon")
        require(settings.revealDelay == .instant, "Reset must not alter revealDelay")
        require(settings.displayScope == .activeOnly, "Reset must not alter displayScope")
        require(settings.switcherMode == .windows, "Reset must not alter switcherMode")

        // Show App Names affects only appNameLabel and must collapse hidden rows naturally.
        let namesWindow = WindowModel(
            id: 98, pid: getpid(), bundleIdentifier: "probe.names", appName: "Probe App",
            title: "Meaningful Title", frame: .zero, displayID: 1, spaceIDs: [1], iconKey: "probe.names"
        )
        let appNamesItem = SwitcherItemView(window: namesWindow, icon: NSImage(), mode: .applications)
        appNamesItem.setShowAppNames(false)
        require(reflectedView(named: "appNameLabel", in: appNamesItem)?.isHidden == true,
                "Applications OFF must hide app-name label")
        require(reflectedView(named: "windowTitleLabel", in: appNamesItem)?.isHidden == true,
                "Applications OFF must remain icon-only")

        let windowsNamesItem = SwitcherItemView(window: namesWindow, icon: NSImage(), mode: .windows)
        windowsNamesItem.setShowAppNames(false)
        require(reflectedView(named: "appNameLabel", in: windowsNamesItem)?.isHidden == true,
                "Windows OFF must hide app-name label")
        require(reflectedView(named: "windowTitleLabel", in: windowsNamesItem)?.isHidden == false,
                "Windows OFF must preserve meaningful window-title label")
        let noTitle = WindowModel(
            id: 97, pid: getpid(), bundleIdentifier: "probe.names.none", appName: "Probe App",
            title: "Probe App", frame: .zero, displayID: 1, spaceIDs: [1], iconKey: "probe.names.none"
        )
        let noTitleItem = SwitcherItemView(window: noTitle, icon: NSImage(), mode: .windows)
        noTitleItem.setShowAppNames(false)
        require(reflectedView(named: "appNameLabel", in: noTitleItem)?.isHidden == true
                && reflectedView(named: "windowTitleLabel", in: noTitleItem)?.isHidden == true,
                "Windows OFF without meaningful title must be icon-only")

        // 11. Selection Pod Alignment Invariants (<= 0.5pt tolerance across 48/72/96 in both modes)
        for size in [48, 72, 96] {
            let metrics = SwitcherPresentationMetrics(iconSize: CGFloat(size))
            for mode in [SwitcherMode.applications, SwitcherMode.windows] {
                let win = WindowModel(
                    id: 99,
                    pid: getpid(),
                    bundleIdentifier: "com.apple.Safari",
                    appName: "Safari",
                    title: mode == .windows ? "Apple" : "Safari",
                    frame: .zero,
                    displayID: 1,
                    spaceIDs: [1],
                    iconKey: "safari"
                )
                let item = SwitcherItemView(window: win, icon: NSImage(), mode: mode, metrics: metrics)
                item.frame = NSRect(x: 0, y: 0, width: metrics.itemWidth, height: metrics.itemHeight)
                item.layoutSubtreeIfNeeded()

                guard let iconContainer = reflectedView(named: "iconContainer", in: item),
                      let selectionView = reflectedView(named: "selectionBackgroundView", in: item),
                      let imageView = imageViews(in: item).first,
                      let selectionLayer = selectionView.layer else {
                    fputs("FAIL: structural icon/selection hierarchy unavailable\n", stderr)
                    exit(1)
                }
                require(selectionView.superview === iconContainer, "selection must share iconContainer for size \(size) in \(mode.rawValue)")
                require(imageView.superview === iconContainer, "icon must share iconContainer for size \(size) in \(mode.rawValue)")
                let expectedCornerRadius = round(metrics.selectionPodSize * 0.30)
                require(abs(selectionLayer.cornerRadius - expectedCornerRadius) < 0.001,
                        "selection pod corner radius must derive from pod size for size \(size) in \(mode.rawValue)")
                let deltaX = abs(imageView.frame.midX - selectionView.frame.midX)
                let deltaY = abs(imageView.frame.midY - selectionView.frame.midY)
                require(deltaX <= 0.5, "deltaX must be <= 0.5 for size \(size) in \(mode.rawValue) (actual: \(deltaX))")
                require(deltaY <= 0.5, "deltaY must be <= 0.5 for size \(size) in \(mode.rawValue) (actual: \(deltaY))")

                let baselineDelta = CGPoint(x: imageView.frame.midX - selectionView.frame.midX,
                                            y: imageView.frame.midY - selectionView.frame.midY)
                item.configure(window: win, icon: NSImage(), mode: mode == .applications ? .windows : .applications)
                item.layoutSubtreeIfNeeded()
                let toggledDelta = CGPoint(x: imageView.frame.midX - selectionView.frame.midX,
                                           y: imageView.frame.midY - selectionView.frame.midY)
                require(abs(baselineDelta.x - toggledDelta.x) <= 0.001 && abs(baselineDelta.y - toggledDelta.y) <= 0.001,
                        "title visibility must not move selection relative to icon for size \(size) from \(mode.rawValue)")
            }
        }

        // 12. Panel behavior, Alpha guarantees, and Edge Stacking Invariants
        let controller = SwitcherPanelController(settings: settings)
        let sampleWindow = WindowModel(
            id: 1,
            pid: getpid(),
            bundleIdentifier: "com.apple.finder",
            appName: "Finder",
            title: "Finder",
            frame: .zero,
            displayID: CGMainDisplayID(),
            spaceIDs: [1],
            iconKey: "finder"
        )
        controller.show(windows: [sampleWindow], selectedIndex: 0, sessionID: 1, mode: .applications)

        guard let panel = Mirror(reflecting: controller).children.first(where: { $0.label == "panel" })?.value as? NSPanel? as? NSPanel else {
            fputs("FAIL: panel reflection unavailable\n", stderr)
            exit(1)
        }
        require(panel.alphaValue == 1.0, "Panel alphaValue must remain 1.0 at default darkness")

        settings.glassDarkness = 0
        require(panel.alphaValue == 1.0, "Panel alphaValue must remain 1.0 at darkness 0")

        settings.glassDarkness = 100
        require(panel.alphaValue == 1.0, "Panel alphaValue must remain 1.0 at darkness 100")

        guard let root = panel.contentView as? SwitcherPresentationRootView else {
            fputs("FAIL: panel root must be SwitcherPresentationRootView\n", stderr)
            exit(1)
        }
        require(root.alphaValue == 1.0, "Root view alphaValue must remain 1.0")
        require(root.foregroundView.alphaValue == 1.0, "Foreground alpha must remain 1.0")
        require(abs(root.glassView.alphaValue - 1.0) < 0.001, "Native glass must render at full alpha")
        require(panel.alphaValue == 1.0, "Panel alpha must remain 1.0 with native glass")

        // Modern edge stacking: root is non-drawing/non-clipping; glass owns the visible rim.
        require(root.layer?.borderWidth == 0, "Root view must not have a custom border")
        require(root.layer?.borderColor == nil, "Root view must not have a custom border color")
        require(root.layer?.backgroundColor == nil, "Root view must remain non-drawing")
        require(root.layer?.cornerRadius == 0, "Root view must not own the visible glass corner treatment")
        require(root.layer?.masksToBounds == false, "Root view must not clip the native glass perimeter")
        guard let materialContainer = Mirror(reflecting: root).children.first(where: { $0.label == "materialContainer" })?.value as? NSView else {
            fputs("FAIL: root must expose one internal materialContainer\n", stderr)
            exit(1)
        }
        require(materialContainer.layer?.borderWidth == 0, "Material container must not draw a border")
        require(materialContainer.layer?.shadowOpacity == 0, "Material container must not draw a shadow")
        require(root.diffusionBacking.superview === materialContainer, "Diffusion must be contained by materialContainer")
        require(root.smokedUnderlay.superview === materialContainer, "Smoke must be contained by materialContainer")
        require(root.diffusionBacking.layer?.borderWidth == 0, "Diffusion backing must have no border")
        require(root.diffusionBacking.layer?.cornerRadius == 0, "Diffusion backing must not create a second rounded perimeter")
        require(root.smokedUnderlay.layer?.borderWidth == 0, "Smoked underlay must have no border")
        require(root.smokedUnderlay.layer?.cornerRadius == 0, "Smoke must not create a second rounded perimeter")

        root.layoutSubtreeIfNeeded()
        require(materialContainer.frame == root.bounds, "Material container must align exactly with glass bounds")
        require(root.diffusionBacking.frame == materialContainer.bounds, "Diffusion must fill material container")
        require(root.smokedUnderlay.frame == materialContainer.bounds, "Smoke must fill material container")
        require(root.glassView.frame == root.bounds, "Glass view must occupy full root bounds as sole visual rim owner")

        // Backing VEV hidden at blur 0
        settings.backgroundBlur = 0
        require(root.diffusionBacking.isHidden == true, "Backing VEV must be hidden when blur is 0")
        require(root.diffusionBacking.alphaValue == 0.0, "Backing VEV alpha must be 0.0 when blur is 0")

        // Backing VEV active at blur > 0
        settings.backgroundBlur = 100
        require(root.diffusionBacking.isHidden == false, "Backing VEV must be visible when blur > 0")
        require(abs(root.diffusionBacking.alphaValue - 0.25) < 0.001, "Backing VEV alpha must be 0.25 at blur 100")

        // Background OFF must add foreground-only legibility contrast without rebuilding items.
        let titledWindow = WindowModel(
            id: 2, pid: getpid(), bundleIdentifier: "probe.background-off", appName: "Probe App",
            title: "Meaningful Window Title", frame: .zero, displayID: CGMainDisplayID(),
            spaceIDs: [1], iconKey: "probe.background-off"
        )
        settings.backgroundBlur = 0
        settings.glassDarkness = 0
        settings.showBackground = true
        NSApp.appearance = NSAppearance(named: .darkAqua)
        controller.show(windows: [titledWindow], selectedIndex: 0, sessionID: 2, mode: .windows)
        guard let beforeItems = Mirror(reflecting: controller).children.first(where: { $0.label == "itemViews" })?.value as? [SwitcherItemView],
              let reusedItem = beforeItems.first,
              let appLabel = reflectedView(named: "appNameLabel", in: reusedItem) as? NSTextField,
              let titleLabel = reflectedView(named: "windowTitleLabel", in: reusedItem) as? NSTextField else {
            fputs("FAIL: background-off label hierarchy unavailable\n", stderr); exit(1)
        }
        require(appLabel.shadow == nil && titleLabel.shadow == nil, "Background ON must preserve accepted shadow-free labels")
        require((reusedItem.selectionBackgroundView.layer?.borderWidth ?? 0) > 0,
                "Background ON must keep the selected accent indicator visible")
        settings.showBackground = false
        guard let afterItems = Mirror(reflecting: controller).children.first(where: { $0.label == "itemViews" })?.value as? [SwitcherItemView] else {
            fputs("FAIL: reused item hierarchy unavailable\n", stderr); exit(1)
        }
        require(afterItems.first === reusedItem, "Show Background toggle must reuse existing item hierarchy")
        require(appLabel.alphaValue == 1.0 && titleLabel.alphaValue == 1.0, "Background OFF labels must remain fully opaque")
        require(!appLabel.isHidden, "Applications/app-name label must remain visible when background is OFF")
        require(!titleLabel.isHidden, "Meaningful Windows-mode title must remain visible when background is OFF")
        require(appLabel.shadow != nil && titleLabel.shadow != nil, "Background OFF must activate foreground-only text contrast")
        require(abs((appLabel.shadow?.shadowBlurRadius ?? -1) - 1.5) < 0.001, "Background OFF primary text shadow blur must be 1.5")
        require(appLabel.shadow?.shadowOffset == .zero, "Background OFF primary text shadow must have zero offset")
        require(abs((appLabel.shadow?.shadowColor?.alphaComponent ?? -1) - 0.58) < 0.01, "Background OFF text shadow alpha must be 0.58")
        require(root.glassView.isHidden && root.diffusionBacking.isHidden && root.smokedUnderlay.isHidden, "Background OFF must not restore any panel material")
        if #available(macOS 26.0, *), let glass = root.glassView as? NSGlassEffectView {
            require(glass.contentView == nil, "Background OFF must detach reusable content from hidden native glass")
            require(root.foregroundView.superview === root, "Background OFF must reparent reusable content directly above the hidden glass")
        }
        require(root.foregroundView.alphaValue == 1.0 && panel.alphaValue == 1.0, "Background OFF foreground and panel alpha must remain 1")
        require((reusedItem.selectionBackgroundView.layer?.borderWidth ?? 0) > 0,
                "Background OFF must keep the selected accent indicator visible")
        settings.showBackground = true
        if #available(macOS 26.0, *), let glass = root.glassView as? NSGlassEffectView {
            require(glass.contentView === root.foregroundView, "Background ON must restore reusable content to native glass contentView")
            require(root.foregroundView.superview !== root, "Background ON content must not remain a sibling behind native glass")
        }
        require(appLabel.shadow == nil && titleLabel.shadow == nil, "Background ON must remove the background-off-only text contrast treatment")

        controller.close()
        print("AppearanceCustomizationTests passed")
    }
}
