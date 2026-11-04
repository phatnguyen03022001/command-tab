import AppKit
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

final class SwitcherPanelController {
    private let settings: CommandTabSettings
    private var panel: NSPanel?
    private var itemViews: [SwitcherItemView] = []
    private var iconCache: [String: NSImage] = [:]
    private var visibleSessionID: Int?
    private var currentMetrics: SwitcherPresentationMetrics
    private var currentLayout: SwitcherLayoutResult?
    private var lastItemCount: Int = 1
    private var lastSelectedIndex: Int = 0
    private var lastContextDisplayID: CGDirectDisplayID?
    private var lastMode: SwitcherMode = .applications
    private var lastThumbnailsAvailable = false
    private var thumbnailTask: Task<Void, Never>?

    private var backingVEV: NSVisualEffectView?
    private var smokedUnderlay: NSView?
    private var presentationRoot: SwitcherPresentationRootView?

    private lazy var stackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = currentMetrics.itemSpacing
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var stackContainer: NSView = {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = true
        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: currentMetrics.horizontalInset),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -currentMetrics.horizontalInset),
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        return container
    }()

    private lazy var contentViewport: NSClipView = {
        let clip = NSClipView()
        clip.drawsBackground = false
        clip.wantsLayer = true
        clip.layer?.backgroundColor = NSColor.clear.cgColor
        clip.documentView = stackContainer
        return clip
    }()

    private lazy var rootView: NSView = {
        makeRootView()
    }()

    var isVisible: Bool { panel?.isVisible == true }

    init(settings: CommandTabSettings = .shared) {
        self.settings = settings
        self.currentMetrics = SwitcherPresentationMetrics(
            iconSize: CGFloat(settings.iconSize),
            itemSpacing: CGFloat(settings.appSpacing)
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChangeNotification),
            name: CommandTabSettings.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func settingsDidChangeNotification() {
        handleSettingsChanged()
    }

    private func handleSettingsChanged() {
        updatePresentationProperties()
        guard let panel, panel.isVisible else {
            let preferred = SwitcherPresentationMetrics(
                iconSize: CGFloat(settings.iconSize),
                itemSpacing: CGFloat(settings.appSpacing)
            )
            if preferred != currentMetrics { applyMetrics(preferred) }
            return
        }

        let layout = resolveLayout(itemCount: lastItemCount, contextDisplayID: lastContextDisplayID)
        if layout.metrics != currentMetrics { applyMetrics(layout.metrics) }
        position(panel: panel, layout: layout, contextDisplayID: lastContextDisplayID)
        applySelectionPresentation(selectedIndex: lastSelectedIndex, itemCount: lastItemCount)
        ensureSelectionVisible(selectedIndex: lastSelectedIndex, itemCount: lastItemCount)
    }

    private func applyMetrics(_ newMetrics: SwitcherPresentationMetrics) {
        currentMetrics = newMetrics
        stackView.spacing = newMetrics.itemSpacing
        for item in itemViews { item.applyMetrics(newMetrics) }
    }

    func show(windows: [WindowModel], selectedIndex: Int, sessionID: Int, mode: SwitcherMode) {
        visibleSessionID = sessionID
        lastItemCount = windows.count
        lastSelectedIndex = selectedIndex
        lastContextDisplayID = windows.first?.displayID
        lastMode = mode
        lastThumbnailsAvailable = mode == .windows && CGPreflightScreenCaptureAccess()
        thumbnailTask?.cancel()
        thumbnailTask = nil

        let panel = makePanelIfNeeded()
        updatePresentationProperties()

        let layout = resolveLayout(itemCount: windows.count, contextDisplayID: windows.first?.displayID)
        if layout.metrics != currentMetrics { applyMetrics(layout.metrics) }

        // Size the document view before adding constrained tiles (avoids a transient 0pt width).
        position(panel: panel, layout: layout, contextDisplayID: windows.first?.displayID)
        configureContent(windows: windows, selectedIndex: selectedIndex, mode: mode)
        panel.orderFrontRegardless()
        rootView.layoutSubtreeIfNeeded()
        stackContainer.layoutSubtreeIfNeeded()
        applySelectionPresentation(selectedIndex: selectedIndex, itemCount: windows.count)
        ensureSelectionVisible(selectedIndex: selectedIndex, itemCount: windows.count)
        loadThumbnails(windows: windows, sessionID: sessionID, mode: mode)
    }

    func update(selectedIndex: Int, sessionID: Int) {
        guard visibleSessionID == sessionID else { return }
        lastSelectedIndex = selectedIndex
        for (index, view) in itemViews.enumerated() {
            view.isSelected = !view.isHidden && index == selectedIndex
        }
        applySelectionPresentation(selectedIndex: selectedIndex, itemCount: lastItemCount)
        ensureSelectionVisible(selectedIndex: selectedIndex, itemCount: lastItemCount)
    }

    func close() {
        visibleSessionID = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        panel?.orderOut(nil)
        for item in itemViews { item.previewImageView.image = nil }
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
                item = SwitcherItemView(window: window, icon: icon, mode: mode, metrics: currentMetrics)
                itemViews.append(item)
                stackView.addArrangedSubview(item)
            }
            item.setBackgroundVisible(settings.showBackground)
            item.setShowAppNames(settings.showAppNames)
            item.setSelectedIconScale(settings.selectedIconScale)
            item.isHidden = false
            item.isSelected = index == selectedIndex
        }

        if windows.count < itemViews.count {
            for index in windows.count..<itemViews.count {
                itemViews[index].isSelected = false
                itemViews[index].setBreathingOffsetX(0)
                itemViews[index].isHidden = true
            }
        }
    }

    // Window previews are opt-in at the OS level: never request screen-capture permission.
    // Captures are ephemeral, bounded, and never written to disk.
    private func loadThumbnails(windows: [WindowModel], sessionID: Int, mode: SwitcherMode) {
        guard mode == .windows, lastThumbnailsAvailable else { return }
        let allowed = windows.enumerated().filter { WindowThumbnailPolicy.mayCapture($0.element) }
        guard !allowed.isEmpty else { return }

        thumbnailTask = Task { [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
            let available = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            for (index, target) in allowed.prefix(16) {
                guard !Task.isCancelled else { return }
                guard let shareable = available[target.id],
                      let owner = shareable.owningApplication,
                      WindowThumbnailPolicy.mayCapture(
                          target, captureProcessID: owner.processID,
                          captureBundleIdentifier: owner.bundleIdentifier
                      ) else { continue }
                let config = SCStreamConfiguration()
                config.width = 256
                config.height = max(96, min(256, Int(256 * target.frame.height / max(1, target.frame.width))))
                config.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: shareable)
                guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                    continue
                }
                guard !Task.isCancelled else { return }
                let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run { [weak self] in
                    guard let self, self.visibleSessionID == sessionID,
                          self.itemViews.indices.contains(index), !self.itemViews[index].isHidden else { return }
                    self.itemViews[index].setThumbnail(thumbnail, forWindowID: target.id)
                }
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

    private func visibleFrame(contextDisplayID: CGDirectDisplayID?) -> NSRect {
        let screen = NSScreen.screens.first { screen in
            guard let contextDisplayID,
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == contextDisplayID
        } ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private func resolveLayout(itemCount: Int, contextDisplayID: CGDirectDisplayID?) -> SwitcherLayoutResult {
        SwitcherLayoutResolver.resolve(
            itemCount: itemCount,
            visibleWidth: visibleFrame(contextDisplayID: contextDisplayID).width,
            preferredIconSize: CGFloat(settings.iconSize),
            preferredSpacing: CGFloat(settings.appSpacing),
            mode: lastMode,
            thumbnailsAvailable: lastThumbnailsAvailable
        )
    }

    private func position(
        panel: NSPanel,
        layout: SwitcherLayoutResult,
        contextDisplayID: CGDirectDisplayID?
    ) {
        currentLayout = layout
        let visibleFrame = visibleFrame(contextDisplayID: contextDisplayID)
        let zoomHeadroom = layout.metrics.selectionPodSize * max(0, settings.selectedIconScale - 1.15) * 0.5
        let presentationHeight = layout.metrics.panelHeight + zoomHeadroom * 2
        let frame = NSRect(
            x: visibleFrame.midX - layout.panelWidth / 2,
            y: visibleFrame.midY - presentationHeight / 2,
            width: layout.panelWidth,
            height: presentationHeight
        )
        panel.setFrame(frame, display: true)
        stackContainer.frame = NSRect(
            x: 0,
            y: 0,
            width: layout.contentWidth,
            height: presentationHeight
        )
    }

    private func applySelectionPresentation(selectedIndex: Int, itemCount: Int) {
        let scale = settings.selectedIconScale
        let extraHalfWidth = currentMetrics.selectionPodSize * max(0, scale - 1.0) * 0.5
        let firstNeighborPush = scale > 1.0 ? extraHalfWidth + 2.0 : 0.0
        let secondNeighborPush = firstNeighborPush * 0.40
        let thirdNeighborPush = firstNeighborPush * 0.15
        let visibleCount = min(itemCount, itemViews.count)

        for (index, item) in itemViews.enumerated() {
            item.setSelectedIconScale(scale)
            guard index < visibleCount, !item.isHidden else {
                item.setBreathingOffsetX(0)
                continue
            }
            let distance = abs(index - selectedIndex)
            let magnitude: CGFloat
            switch distance {
            case 1: magnitude = firstNeighborPush
            case 2: magnitude = secondNeighborPush
            case 3: magnitude = thirdNeighborPush
            default: magnitude = 0
            }
            let direction: CGFloat = index < selectedIndex ? -1 : (index > selectedIndex ? 1 : 0)
            item.setBreathingOffsetX(direction * magnitude)
        }
    }

    private func ensureSelectionVisible(selectedIndex: Int, itemCount: Int) {
        guard let layout = currentLayout else { return }
        let currentOffset = contentViewport.bounds.origin.x
        let scaledPodHalfWidth = layout.metrics.selectionPodSize * settings.selectedIconScale * 0.5
        let visualMargin = max(0, scaledPodHalfWidth - layout.metrics.itemWidth * 0.5)
        let offset = SwitcherViewportPolicy.offset(
            selectedIndex: selectedIndex,
            itemCount: itemCount,
            metrics: layout.metrics,
            viewportWidth: layout.panelWidth,
            contentWidth: layout.contentWidth,
            currentOffset: currentOffset,
            visualMargin: visualMargin
        )
        contentViewport.setBoundsOrigin(NSPoint(x: offset, y: 0))
    }

    private func updatePresentationProperties() {
        guard let backingVEV, let smokedUnderlay, let presentationRoot else { return }

        let showBackground = settings.showBackground
        for item in itemViews {
            item.setBackgroundVisible(showBackground)
            item.setShowAppNames(settings.showAppNames)
        }
        presentationRoot.setBackgroundVisible(showBackground)
        presentationRoot.glassView.alphaValue = 1.0
        presentationRoot.foregroundView.alphaValue = 1.0
        panel?.alphaValue = 1.0
        panel?.hasShadow = showBackground

        guard showBackground else {
            backingVEV.isHidden = true
            backingVEV.alphaValue = 0.0
            backingVEV.state = .inactive
            smokedUnderlay.isHidden = true
            smokedUnderlay.layer?.backgroundColor = NSColor.clear.cgColor
            return
        }

        if settings.backgroundBlur == 0 {
            backingVEV.isHidden = true
            backingVEV.alphaValue = 0.0
            backingVEV.state = .inactive
        } else {
            backingVEV.isHidden = false
            backingVEV.alphaValue = settings.diffusionBackingAlpha
            backingVEV.state = .active
        }

        let isDark: Bool
        if let match = panel?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            isDark = (match == .darkAqua)
        } else {
            isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        }
        let smokeAlpha = settings.smokeAlpha(isDark: isDark)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        smokedUnderlay.isHidden = smokeAlpha == 0
        smokedUnderlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(smokeAlpha).cgColor
        CATransaction.commit()
    }

    private func makeRootView() -> NSView {
        let backing = NSVisualEffectView()
        backing.material = .hudWindow
        backing.blendingMode = .behindWindow
        backing.state = .active
        backing.wantsLayer = true
        backing.layer?.cornerRadius = 0
        backing.layer?.masksToBounds = false
        backing.layer?.borderWidth = 0
        backing.layer?.borderColor = nil
        self.backingVEV = backing

        let underlay = NSView()
        underlay.wantsLayer = true
        underlay.layer?.cornerRadius = 0
        underlay.layer?.masksToBounds = false
        underlay.layer?.borderWidth = 0
        underlay.layer?.borderColor = nil
        self.smokedUnderlay = underlay

        let materialContainer = NSView()
        materialContainer.wantsLayer = true
        materialContainer.layer?.cornerRadius = SwitcherPresentationRootView.outerCornerRadius
        materialContainer.layer?.cornerCurve = .continuous
        materialContainer.layer?.masksToBounds = true
        materialContainer.layer?.borderWidth = 0
        materialContainer.layer?.borderColor = nil
        materialContainer.layer?.backgroundColor = nil
        materialContainer.layer?.shadowOpacity = 0
        materialContainer.addSubview(backing)
        materialContainer.addSubview(underlay)

        let glass: NSView
        if #available(macOS 26.0, *) {
            let g = NSGlassEffectView()
            g.style = .clear
            g.cornerRadius = SwitcherPresentationRootView.outerCornerRadius
            g.tintColor = nil
            if #available(macOS 27.0, *) {
                g.effectIsInteractive = true
            }
            g.contentView = contentViewport
            glass = g
        } else {
            glass = SwitcherPanelFallbackRootView()
        }

        let root = SwitcherPresentationRootView(
            materialContainer: materialContainer,
            diffusionBacking: backing,
            smokedUnderlay: underlay,
            glassView: glass,
            foregroundView: contentViewport
        )
        root.onAppearanceChange = { [weak self] in
            self?.updatePresentationProperties()
        }
        self.presentationRoot = root
        updatePresentationProperties()
        return root
    }

}

enum WindowThumbnailPolicy {
    static func mayCapture(_ window: WindowModel) -> Bool {
        // Do not inspect or capture the Photos app, including thumbnail content.
        // Unknown bundle identity cannot prove a window is safe to screenshot.
        guard let bundleID = window.bundleIdentifier else { return false }
        return bundleID.caseInsensitiveCompare("com.apple.Photos") != .orderedSame
    }

    // ScreenCaptureKit metadata must still identify the snapshotted PID and app.
    // A WindowServer ID match alone is insufficient to authorize a later capture.
    static func mayCapture(
        _ window: WindowModel,
        captureProcessID: pid_t,
        captureBundleIdentifier: String
    ) -> Bool {
        guard mayCapture(window), let expectedID = window.bundleIdentifier else { return false }
        return window.pid == captureProcessID
            && expectedID.caseInsensitiveCompare(captureBundleIdentifier) == .orderedSame
    }
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
