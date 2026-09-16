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
        stack.spacing = 6
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var rootView: NSVisualEffectView = {
        let root = SwitcherPanelRootView()
        root.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])
        return root
    }()

    var isVisible: Bool { panel?.isVisible == true }

    func show(windows: [WindowModel], selectedIndex: Int, sessionID: Int, mode: SwitcherMode) {
        visibleSessionID = sessionID
        let panel = makePanelIfNeeded()
        configureContent(windows: windows, selectedIndex: selectedIndex, mode: mode)
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

    private func configureContent(windows: [WindowModel], selectedIndex: Int, mode: SwitcherMode) {
        for (index, window) in windows.enumerated() {
            let item: SwitcherItemView
            let icon = icon(for: window)
            if index < itemViews.count {
                item = itemViews[index]
                item.configure(window: window, icon: icon, mode: mode)
            } else {
                item = SwitcherItemView(window: window, icon: icon, mode: mode)
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
        let count = max(1, itemCount)
        let contentWidth = CGFloat(count) * 108 + CGFloat(count - 1) * 6 + 20
        let width = min(contentWidth, visibleFrame.width * 0.86)
        let height: CGFloat = 96
        let frame = NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }

}



private final class SwitcherPanelRootView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        updateBorder()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    private func updateBorder() {
        var border: CGColor!
        effectiveAppearance.performAsCurrentDrawingAppearance {
            border = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        }
        layer?.borderColor = border
    }
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
