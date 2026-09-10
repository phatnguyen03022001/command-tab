import AppKit
import CoreGraphics
import UniformTypeIdentifiers

final class SwitcherPanelController {
    private var panel: NSPanel?
    private var itemViews: [SwitcherItemView] = []
    private var iconCache: [String: NSImage] = [:]
    private var visibleSessionID: Int?

    private lazy var stackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var rootView: NSVisualEffectView = {
        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.cornerCurve = .continuous
        root.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stackView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
        return root
    }()

    var isVisible: Bool { panel?.isVisible == true }

    func show(windows: [WindowModel], selectedIndex: Int, sessionID: Int) {
        visibleSessionID = sessionID
        let panel = makePanelIfNeeded()
        configureContent(windows: windows, selectedIndex: selectedIndex)
        position(panel: panel, itemCount: windows.count, contextDisplayID: windows.first?.displayID)
        panel.orderFrontRegardless()
    }

    func update(selectedIndex: Int, sessionID: Int) {
        guard visibleSessionID == sessionID else { return }
        for (index, view) in itemViews.enumerated() {
            view.isSelected = !view.isHidden && index == selectedIndex
        }
    }

    func close() {
        visibleSessionID = nil
        panel?.orderOut(nil)
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }
        let newPanel = NonActivatingPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.level = .modalPanel
        newPanel.hasShadow = true
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        newPanel.contentView = rootView
        panel = newPanel
        return newPanel
    }

    private func configureContent(windows: [WindowModel], selectedIndex: Int) {
        for (index, window) in windows.enumerated() {
            let item: SwitcherItemView
            let icon = icon(for: window)
            if index < itemViews.count {
                item = itemViews[index]
                item.configure(window: window, icon: icon)
            } else {
                item = SwitcherItemView(window: window, icon: icon)
                itemViews.append(item)
                stackView.addArrangedSubview(item)
            }
            item.isHidden = false
            item.isSelected = index == selectedIndex
        }

        if windows.count < itemViews.count {
            for index in windows.count..<itemViews.count {
                itemViews[index].isSelected = false
                itemViews[index].isHidden = true
            }
        }
    }

    private func icon(for window: WindowModel) -> NSImage {
        if let cached = iconCache[window.iconKey] { return cached }
        let icon = NSRunningApplication(processIdentifier: window.pid)?.icon
            ?? NSWorkspace.shared.icon(for: UTType.applicationBundle)
        iconCache[window.iconKey] = icon
        return icon
    }

    private func position(
        panel: NSPanel,
        itemCount: Int,
        contextDisplayID: CGDirectDisplayID?
    ) {
        let screen = NSScreen.screens.first { screen in
            guard let contextDisplayID,
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == contextDisplayID
        } ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(CGFloat(max(1, itemCount)) * 124 + 32, visibleFrame.width * 0.86)
        let height: CGFloat = 122
        let frame = NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
