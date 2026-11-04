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

    static func translationX(_ item: SwitcherItemView) -> CGFloat {
        item.layer?.sublayerTransform.m41 ?? 0
    }

    static func allText(in view: NSView) -> [String] {
        var values: [String] = []
        if let field = view as? NSTextField, !field.isHidden { values.append(field.stringValue) }
        for child in view.subviews { values.append(contentsOf: allText(in: child)) }
        return values
    }

    static func findStack(in view: NSView) -> NSStackView? {
        if let stack = view as? NSStackView { return stack }
        for child in view.subviews {
            if let found = findStack(in: child) { return found }
        }
        return nil
    }

    static func main() {
        _ = NSApplication.shared
        let suite = "commandtab.reuse.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CommandTabSettings(defaults: defaults)
        let controller = SwitcherPanelController(settings: settings)
        let firstWindows = [
            window(id: 100, pid: 10),
            window(id: 101, pid: 11),
            window(id: 102, pid: 12)
        ]
        controller.show(windows: firstWindows, selectedIndex: 1, sessionID: 1, mode: .applications)
        guard let firstPanel = panel(of: controller), let firstRoot = firstPanel.contentView,
              let firstStack = findStack(in: firstRoot) else {
            fputs("FAIL: initial stable hierarchy unavailable\n", stderr)
            exit(1)
        }
        let firstItems = itemViews(of: controller)
        require(firstStack.layer?.masksToBounds != true, "stack must not clip selected visual scaling")
        require(firstItems.count == 3, "initial item pool must match required capacity")

        controller.close()
        let secondWindows = [
            window(id: 200, pid: 20),
            window(id: 201, pid: 21),
            window(id: 202, pid: 22)
        ]
        controller.show(windows: secondWindows, selectedIndex: 0, sessionID: 2, mode: .applications)
        guard let secondPanel = panel(of: controller), let secondRoot = secondPanel.contentView,
              let secondStack = findStack(in: secondRoot) else {
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
        let framesBeforeNavigation = secondItems.map(\.frame)
        let metricsBeforeNavigation = secondItems.map(\.metrics)
        controller.update(selectedIndex: 2, sessionID: 2)
        let navigatedItems = itemViews(of: controller)
        require(zip(secondItems, navigatedItems).allSatisfy { $0 === $1 },
                "selection navigation must not reconstruct item views")
        require(!navigatedItems[0].isSelected && navigatedItems[2].isSelected,
                "selection navigation must move selected state to the new item")
        require((navigatedItems[0].selectionBackgroundView.layer?.borderWidth ?? 0) == 0,
                "old selection ring must disappear after navigation")
        require((navigatedItems[2].selectionBackgroundView.layer?.borderWidth ?? 0) > 0,
                "new selection ring must appear after navigation")
        let oldScale = navigatedItems[0].iconContainer.layer?.sublayerTransform.m11 ?? 1.0
        let newScale = navigatedItems[2].iconContainer.layer?.sublayerTransform.m11 ?? 1.0
        require(abs(oldScale - 1.0) < 0.0001, "old selected iconContainer must reset immediately to 1.00")
        require(abs(newScale - 1.15) < 0.0001, "new selected iconContainer must derive canonical default 115% zoom")
        if let selectedLayer = navigatedItems[2].iconContainer.layer {
            let t = selectedLayer.sublayerTransform
            let center = navigatedItems[2].metrics.selectionPodSize * 0.5
            let mappedX = t.m11 * center + t.m21 * center + t.m41
            let mappedY = t.m12 * center + t.m22 * center + t.m42
            require(abs(mappedX - center) < 0.001 && abs(mappedY - center) < 0.001,
                    "selected iconContainer content transform must preserve its exact visual center")
            require(CATransform3DIsIdentity(selectedLayer.transform),
                    "selected scale must not mutate iconContainer frame geometry")
        } else {
            fputs("FAIL: selected iconContainer must be layer-backed\n", stderr)
            exit(1)
        }
        require(zip(framesBeforeNavigation, navigatedItems.map(\.frame)).allSatisfy { $0 == $1 },
                "selection scale must not move or resize item layout frames")
        require(zip(metricsBeforeNavigation, navigatedItems.map(\.metrics)).allSatisfy { $0 == $1 },
                "selection scale must not mutate item width, height, icon size, or App Spacing")

        controller.update(selectedIndex: 0, sessionID: 2)
        controller.update(selectedIndex: 1, sessionID: 2)
        controller.update(selectedIndex: 2, sessionID: 2)
        controller.update(selectedIndex: 0, sessionID: 2)
        let cycledItems = itemViews(of: controller)
        let cycledSelectedScale = cycledItems[0].iconContainer.layer?.sublayerTransform.m11 ?? 1.0
        require(abs(cycledSelectedScale - newScale) < 0.0001, "repeated navigation must not accumulate selected scale")
        require(abs((cycledItems[1].iconContainer.layer?.sublayerTransform.m11 ?? 1.0) - 1.0) < 0.0001,
                "intermediate item must return exactly to 1.00 after repeated navigation")
        require(abs((cycledItems[2].iconContainer.layer?.sublayerTransform.m11 ?? 1.0) - 1.0) < 0.0001,
                "previous selected item must return exactly to 1.00 after repeated navigation")

        controller.close()
        controller.show(windows: [window(id: 300, pid: 30)], selectedIndex: 0, sessionID: 3, mode: .applications)
        let thirdItems = itemViews(of: controller)
        require(thirdItems.count == 3, "high-water-mark item pool must be retained")
        require(thirdItems[0] === firstItems[0], "first pooled item must be reused after count shrinks")
        require(secondStack.arrangedSubviews.count == 3, "pooled arranged views must not accumulate duplicates")
        require(secondStack.arrangedSubviews.filter { !$0.isHidden }.count == 1, "unused pooled views must be hidden without layout gaps")
        let text = allText(in: thirdItems[0])
        require(text == ["App-30"], "reused item must show only the current application name")
        require(thirdItems[0].isSelected, "active reused item must carry current selection")
        require(!thirdItems[1].isSelected && !thirdItems[2].isSelected, "hidden pooled items must not keep stale selection")
        controller.close()

        // Custom zoom and breathing: presentation-only, deterministic, reversible.
        settings.selectedIconZoom = 115
        let breathingWindows = (0..<9).map { index in window(id: CGWindowID(400 + index), pid: pid_t(40 + index)) }
        controller.show(windows: breathingWindows, selectedIndex: 4, sessionID: 4, mode: .applications)
        let breathingItems = itemViews(of: controller)
        let panelWidth = panel(of: controller)?.frame.width ?? -1
        let panelHeight115 = panel(of: controller)?.frame.height ?? -1
        require(breathingItems.count >= 9, "breathing probe requires nine reusable items")
        let selectedScale115 = breathingItems[4].iconContainer.layer?.sublayerTransform.m11 ?? 1.0
        require(abs(selectedScale115 - 1.15) < 0.0001, "selected scale must derive from Selected Icon Zoom 115%")
        let extraHalf115 = breathingItems[4].metrics.selectionPodSize * 0.15 * 0.5
        let first115 = extraHalf115 + 2.0
        let second115 = first115 * 0.40
        let third115 = first115 * 0.15
        require(abs(translationX(breathingItems[3]) + first115) < 0.001, "first left neighbor must breathe outward")
        require(abs(translationX(breathingItems[5]) - first115) < 0.001, "first right neighbor must breathe outward")
        require(abs(translationX(breathingItems[2]) + second115) < 0.001, "second left neighbor must breathe outward less")
        require(abs(translationX(breathingItems[6]) - second115) < 0.001, "second right neighbor must breathe outward less")
        require(abs(translationX(breathingItems[1]) + third115) < 0.001, "third left neighbor must breathe outward slightly")
        require(abs(translationX(breathingItems[7]) - third115) < 0.001, "third right neighbor must breathe outward slightly")
        require(abs(translationX(breathingItems[0])) < 0.001 && abs(translationX(breathingItems[8])) < 0.001,
                "farther neighbors must not move")
        require(abs(translationX(breathingItems[4])) < 0.001, "selected item itself must not translate")
        require(breathingItems[2].subviews.count > 0 && breathingItems[4].subviews.count > 0,
                "neighbor translation must apply at item presentation level so labels move with icons")

        controller.update(selectedIndex: 5, sessionID: 4)
        let shifted = itemViews(of: controller)
        require(abs(translationX(shifted[3]) + second115) < 0.001, "old second-left transform must be recomputed, not accumulated")
        require(abs(translationX(shifted[4]) + first115) < 0.001, "old selected item must become first-left neighbor")
        require(abs(translationX(shifted[5])) < 0.001, "new selected item must have zero translation")
        require(abs(translationX(shifted[6]) - first115) < 0.001, "new first-right neighbor must receive breathing")
        require(abs(translationX(shifted[7]) - second115) < 0.001, "new second-right neighbor must receive lesser breathing")
        require(abs(translationX(shifted[8]) - third115) < 0.001, "new third-right neighbor must receive slight breathing")
        require(abs((panel(of: controller)?.frame.width ?? -2) - panelWidth) < 0.001,
                "selection navigation must not resize panel")

        settings.selectedIconZoom = 100
        let zoom100 = itemViews(of: controller)
        require(abs((zoom100[5].iconContainer.layer?.sublayerTransform.m11 ?? 0) - 1.0) < 0.0001,
                "100% zoom must produce selected scale 1.00")
        require(zoom100.prefix(9).allSatisfy { abs(translationX($0)) < 0.001 },
                "100% zoom must disable all breathing")

        settings.selectedIconZoom = 175
        let zoom175 = itemViews(of: controller)
        require(abs((zoom175[5].iconContainer.layer?.sublayerTransform.m11 ?? 0) - 1.75) < 0.0001,
                "175% zoom must produce selected scale 1.75 without silent clamp")
        let extraHalf175 = zoom175[5].metrics.selectionPodSize * 0.75 * 0.5
        let first175 = extraHalf175 + 2.0
        let second175 = first175 * 0.40
        let third175 = first175 * 0.15
        require(abs(translationX(zoom175[4]) + first175) < 0.001 && abs(translationX(zoom175[6]) - first175) < 0.001,
                "175% zoom must derive first-neighbor breathing from extra half-width")
        require(abs(translationX(zoom175[3]) + second175) < 0.001 && abs(translationX(zoom175[7]) - second175) < 0.001,
                "175% zoom must apply lesser second-neighbor breathing")
        require(abs(translationX(zoom175[2]) + third175) < 0.001 && abs(translationX(zoom175[8]) - third175) < 0.001,
                "175% zoom must apply slight third-neighbor breathing")
        let selected = zoom175[5]
        let rightNeighbor = zoom175[6]
        let selectedRight = selected.frame.midX + selected.metrics.selectionPodSize * 1.75 * 0.5
        let neighborLeft = rightNeighbor.frame.midX + translationX(rightNeighbor) - rightNeighbor.metrics.iconSize * 0.5
        require(neighborLeft >= selectedRight - 0.001, "175% selected pod must not visually overlap first right neighbor icon")
        require(abs((panel(of: controller)?.frame.width ?? -2) - panelWidth) < 0.001,
                "zoom changes must not resize panel width")
        require((panel(of: controller)?.frame.height ?? -1) > panelHeight115,
                "zoom above canonical 115% must add vertical presentation headroom to avoid clipping")

        controller.update(selectedIndex: 0, sessionID: 4)
        let firstEdge = itemViews(of: controller)
        require(abs(translationX(firstEdge[0])) < 0.001, "first selected item must remain unshifted")
        require(translationX(firstEdge[1]) > 0 && translationX(firstEdge[2]) > 0 && translationX(firstEdge[3]) > 0,
                "first selected item must breathe only the first three right-side neighbors outward")
        require((4..<9).allSatisfy { abs(translationX(firstEdge[$0])) < 0.001 },
                "first selected item must not shift farther items")

        controller.update(selectedIndex: 8, sessionID: 4)
        let lastEdge = itemViews(of: controller)
        require(abs(translationX(lastEdge[8])) < 0.001, "last selected item must remain unshifted")
        require(translationX(lastEdge[7]) < 0 && translationX(lastEdge[6]) < 0 && translationX(lastEdge[5]) < 0,
                "last selected item must breathe only the first three left-side neighbors outward")
        require((0..<5).allSatisfy { abs(translationX(lastEdge[$0])) < 0.001 },
                "last selected item must not shift farther items")

        controller.update(selectedIndex: 4, sessionID: 4)
        controller.update(selectedIndex: 5, sessionID: 4)
        controller.update(selectedIndex: 4, sessionID: 4)
        let noAccumulation = itemViews(of: controller)
        require(abs(translationX(noAccumulation[3]) + first175) < 0.001 && abs(translationX(noAccumulation[5]) - first175) < 0.001,
                "repeated navigation must not accumulate breathing transforms")

        settings.showAppNames = false
        let namesHidden = itemViews(of: controller)
        require(namesHidden.prefix(9).allSatisfy { allText(in: $0).isEmpty },
                "Applications mode must become icon-only live when Show App Names is OFF")
        require(abs((namesHidden[4].iconContainer.layer?.sublayerTransform.m11 ?? 0) - 1.75) < 0.0001,
                "selected zoom must remain active when app names are hidden")
        require(abs(translationX(namesHidden[3]) + first175) < 0.001 && abs(translationX(namesHidden[5]) - first175) < 0.001,
                "breathing must remain active when app names are hidden")
        settings.showAppNames = true
        require(allText(in: itemViews(of: controller)[4]) == ["App-44"],
                "Show App Names ON must restore application name without rebuilding hierarchy")
        controller.close()

        // 175% must remain coherent across small, typical, and overflow-sized app counts.
        settings.selectedIconZoom = 175
        for count in [3, 5, 12] {
            let windows = (0..<count).map { index in window(id: CGWindowID(700 + index), pid: pid_t(70 + index)) }
            let indices = Array(Set([0, min(1, count - 1), count / 2, max(0, count - 2), count - 1])).sorted()
            for selectedIndex in indices {
                controller.show(windows: windows, selectedIndex: selectedIndex, sessionID: 20 + count + selectedIndex, mode: .applications)
                let items = itemViews(of: controller)
                require(abs((items[selectedIndex].iconContainer.layer?.sublayerTransform.m11 ?? 0) - 1.75) < 0.0001,
                        "175% scale must hold for count \(count), selected \(selectedIndex)")
                require(abs(translationX(items[selectedIndex])) < 0.001,
                        "selected item must never translate while breathing neighbors")
                if selectedIndex + 1 < count {
                    let selectedRight = items[selectedIndex].frame.midX + items[selectedIndex].metrics.selectionPodSize * 1.75 * 0.5
                    let neighborLeft = items[selectedIndex + 1].frame.midX + translationX(items[selectedIndex + 1]) - items[selectedIndex + 1].metrics.iconSize * 0.5
                    require(neighborLeft >= selectedRight - 0.001,
                            "175% selected pod must not overlap first right neighbor for count \(count)")
                }
                controller.close()
            }
        }
        print("SwitcherReuseTests passed")
    }
}
