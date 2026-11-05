import AppKit

struct SwitcherDisplayPreferences: Equatable {
    var reduceMotion = false
    var reduceTransparency = false
    var increaseContrast = false

    static var current: Self {
        let workspace = NSWorkspace.shared
        return Self(
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

final class SwitcherItemView: NSView {
    private var selectedIconScale: CGFloat = 1.15
    private var showAppNames = true
    private var currentMode: SwitcherMode = .applications

    let iconContainer = NSView()
    let selectionBackgroundView = NSView()
    let imageView = NSImageView()
    let previewContainer = NSView()
    let previewImageView = NSImageView()
    private var currentWindowID: CGWindowID?
    private let appNameLabel = NSTextField(labelWithString: "")
    private let windowTitleLabel = NSTextField(labelWithString: "")
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var iconContainerWidthConstraint: NSLayoutConstraint?
    private var iconContainerHeightConstraint: NSLayoutConstraint?
    private var selectionWidthConstraint: NSLayoutConstraint?
    private var selectionHeightConstraint: NSLayoutConstraint?
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private var previewWidthConstraint: NSLayoutConstraint?
    private var previewHeightConstraint: NSLayoutConstraint?
    private(set) var metrics: SwitcherPresentationMetrics = SwitcherPresentationMetrics()
    private var backgroundVisible = true
    private var displayPreferences = SwitcherDisplayPreferences()
    private var stackTopConstraint: NSLayoutConstraint?

    var isSelected: Bool = false {
        didSet {
            setAccessibilitySelected(isSelected)
            updateSelection()
        }
    }

    init(window: WindowModel, icon: NSImage, mode: SwitcherMode, metrics: SwitcherPresentationMetrics? = nil) {
        let resolvedMetrics = metrics ?? SwitcherPresentationMetrics(mode: mode)
        self.metrics = resolvedMetrics
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false

        iconContainer.wantsLayer = true
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer?.masksToBounds = false

        selectionBackgroundView.wantsLayer = true
        selectionBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        selectionBackgroundView.layer?.cornerCurve = .continuous
        selectionBackgroundView.layer?.borderWidth = 0
        selectionBackgroundView.layer?.borderColor = nil

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false

        iconContainer.addSubview(selectionBackgroundView)
        iconContainer.addSubview(imageView, positioned: .above, relativeTo: selectionBackgroundView)

        previewContainer.identifier = NSUserInterfaceItemIdentifier("windowPreviewContainer")
        previewContainer.wantsLayer = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.layer?.cornerRadius = 10
        previewContainer.layer?.cornerCurve = .continuous
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.36).cgColor
        previewContainer.layer?.borderWidth = 1
        previewContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        previewImageView.identifier = NSUserInterfaceItemIdentifier("windowThumbnail")
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewImageView)
        NSLayoutConstraint.activate([
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
        ])

        appNameLabel.alignment = .center
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.maximumNumberOfLines = 1
        appNameLabel.usesSingleLineMode = true
        appNameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        appNameLabel.wantsLayer = true
        appNameLabel.layer?.cornerRadius = 4

        windowTitleLabel.alignment = .center
        windowTitleLabel.lineBreakMode = .byTruncatingMiddle
        windowTitleLabel.maximumNumberOfLines = 1
        windowTitleLabel.usesSingleLineMode = true
        windowTitleLabel.font = .systemFont(ofSize: 10, weight: .regular)
        windowTitleLabel.wantsLayer = true
        windowTitleLabel.layer?.cornerRadius = 4

        let stack = NSStackView(views: [iconContainer, previewContainer, appNameLabel, windowTitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        // The tile is one semantic choice, not a collection of unrelated image/text elements.
        setAccessibilityChildren([])

        let widthC = widthAnchor.constraint(equalToConstant: resolvedMetrics.itemWidth)
        let heightC = heightAnchor.constraint(equalToConstant: resolvedMetrics.itemHeight)
        let containerWidthC = iconContainer.widthAnchor.constraint(equalToConstant: resolvedMetrics.selectionPodSize)
        let containerHeightC = iconContainer.heightAnchor.constraint(equalToConstant: resolvedMetrics.selectionPodSize)
        let selectionWidthC = selectionBackgroundView.widthAnchor.constraint(equalToConstant: resolvedMetrics.selectionPodSize)
        let selectionHeightC = selectionBackgroundView.heightAnchor.constraint(equalToConstant: resolvedMetrics.selectionPodSize)
        let imageWidthC = imageView.widthAnchor.constraint(equalToConstant: resolvedMetrics.previewWidth > 0 ? 28 : resolvedMetrics.iconSize)
        let imageHeightC = imageView.heightAnchor.constraint(equalToConstant: resolvedMetrics.previewWidth > 0 ? 28 : resolvedMetrics.iconSize)
        let previewWidthC = previewContainer.widthAnchor.constraint(equalToConstant: resolvedMetrics.previewWidth)
        let previewHeightC = previewContainer.heightAnchor.constraint(equalToConstant: resolvedMetrics.previewHeight)
        self.widthConstraint = widthC
        self.heightConstraint = heightC
        self.iconContainerWidthConstraint = containerWidthC
        self.iconContainerHeightConstraint = containerHeightC
        self.selectionWidthConstraint = selectionWidthC
        self.selectionHeightConstraint = selectionHeightC
        self.imageWidthConstraint = imageWidthC
        self.imageHeightConstraint = imageHeightC
        self.previewWidthConstraint = previewWidthC
        self.previewHeightConstraint = previewHeightC
        let stackTop = stack.topAnchor.constraint(
            equalTo: topAnchor,
            constant: Self.stackTopInset(metrics: resolvedMetrics, showAppNames: true)
        )
        self.stackTopConstraint = stackTop

        NSLayoutConstraint.activate([
            widthC,
            heightC,
            containerWidthC,
            containerHeightC,
            selectionWidthC,
            selectionHeightC,
            selectionBackgroundView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            selectionBackgroundView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            imageWidthC,
            imageHeightC,
            previewWidthC,
            previewHeightC,
            imageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            appNameLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -4),
            windowTitleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stackTop,
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        selectionBackgroundView.layer?.cornerRadius = round(resolvedMetrics.selectionPodSize * 0.30)
        configure(window: window, icon: icon, mode: mode)
        updateSelection()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func setBackgroundVisible(_ visible: Bool) {
        guard backgroundVisible != visible else { return }
        backgroundVisible = visible
        updateSelection()
    }

    func setDisplayPreferences(_ preferences: SwitcherDisplayPreferences) {
        guard displayPreferences != preferences else { return }
        displayPreferences = preferences
        updateSelection()
    }

    func setSelectedIconScale(_ scale: CGFloat) {
        let normalized = max(1.0, min(1.75, scale))
        guard abs(selectedIconScale - normalized) > 0.0001 else { return }
        selectedIconScale = normalized
        applySelectionScale()
    }

    func setShowAppNames(_ visible: Bool) {
        guard showAppNames != visible else { return }
        showAppNames = visible
        applyLabelVisibility()
    }

    func setBreathingOffsetX(_ offset: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.sublayerTransform = CATransform3DMakeTranslation(offset, 0, 0)
        CATransaction.commit()
    }

    func applyMetrics(_ newMetrics: SwitcherPresentationMetrics) {
        guard metrics != newMetrics else { return }
        metrics = newMetrics
        widthConstraint?.constant = newMetrics.itemWidth
        heightConstraint?.constant = newMetrics.itemHeight
        iconContainerWidthConstraint?.constant = newMetrics.selectionPodSize
        iconContainerHeightConstraint?.constant = newMetrics.selectionPodSize
        selectionWidthConstraint?.constant = newMetrics.selectionPodSize
        selectionHeightConstraint?.constant = newMetrics.selectionPodSize
        imageWidthConstraint?.constant = newMetrics.previewWidth > 0 ? 28 : newMetrics.iconSize
        imageHeightConstraint?.constant = newMetrics.previewWidth > 0 ? 28 : newMetrics.iconSize
        previewContainer.isHidden = newMetrics.previewWidth == 0 || previewImageView.image == nil
        previewImageView.isHidden = previewContainer.isHidden
        previewWidthConstraint?.constant = newMetrics.previewWidth
        previewHeightConstraint?.constant = newMetrics.previewHeight
        selectionBackgroundView.layer?.cornerRadius = round(newMetrics.selectionPodSize * 0.30)
        updateStackTopInset()
        applySelectionScale()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSelection()
    }

    func configure(window: WindowModel, icon: NSImage, mode: SwitcherMode) {
        currentMode = mode
        currentWindowID = window.id
        previewContainer.isHidden = true
        previewImageView.isHidden = true
        previewImageView.image = nil
        imageView.image = icon
        appNameLabel.stringValue = window.appName

        if mode == .windows, let title = Self.meaningfulWindowTitle(window.title, appName: window.appName) {
            windowTitleLabel.stringValue = title
        } else {
            windowTitleLabel.stringValue = ""
        }
        let appName = window.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = appName.isEmpty ? "Unknown application" : appName
        let title = windowTitleLabel.stringValue
        setAccessibilityLabel(title.isEmpty ? name : "\(name), \(title)")
        setAccessibilitySelected(isSelected)
        applyLabelVisibility()
        updateSelection()
    }

    func setThumbnail(_ image: NSImage, forWindowID id: CGWindowID) {
        guard currentMode == .windows, metrics.previewWidth > 0, currentWindowID == id else { return }
        previewImageView.image = image
        previewContainer.isHidden = false
        previewImageView.isHidden = false
    }

    private func applyLabelVisibility() {
        appNameLabel.isHidden = !showAppNames
        windowTitleLabel.isHidden = currentMode != .windows || windowTitleLabel.stringValue.isEmpty
        updateStackTopInset()
    }

    private static func stackTopInset(metrics: SwitcherPresentationMetrics, showAppNames: Bool) -> CGFloat {
        if metrics.mode == .applications {
            return showAppNames ? 12 : (metrics.itemHeight - metrics.selectionPodSize) / 2
        }
        return metrics.previewWidth > 0 ? 0 : 4
    }

    private func updateStackTopInset() {
        stackTopConstraint?.constant = Self.stackTopInset(metrics: metrics, showAppNames: showAppNames)
    }

    private static func meaningfulWindowTitle(_ title: String, appName: String) -> String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let normalizedTitle = normalize(cleanTitle)
        let normalizedAppName = normalize(appName)
        guard normalizedTitle != normalizedAppName else { return nil }
        return cleanTitle
    }

    private static func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private func resolvedCGColor(_ color: NSColor) -> CGColor {
        var result: CGColor!
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    private var usesDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var primaryTextColor: NSColor { NSColor.labelColor.withAlphaComponent(1) }

    private var secondaryTextColor: NSColor {
        (displayPreferences.increaseContrast ? NSColor.labelColor : .secondaryLabelColor)
            .withAlphaComponent(1)
    }

    private func applySelectionScale() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = isSelected ? selectedIconScale : 1.0
        let size = metrics.selectionPodSize
        let offset = (1.0 - scale) * size * 0.5
        let affine = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset, ty: offset)
        iconContainer.layer?.sublayerTransform = CATransform3DMakeAffineTransform(affine)
        CATransaction.commit()
    }

    private func updateSelection() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isSelected {
            let neutralFill = usesDarkAppearance
                ? NSColor(calibratedWhite: 1.0, alpha: displayPreferences.increaseContrast ? 0.24 : 0.11)
                : NSColor(calibratedWhite: 0.0, alpha: displayPreferences.increaseContrast ? 0.20 : 0.07)
            layer?.backgroundColor = resolvedCGColor(.clear)
            selectionBackgroundView.layer?.backgroundColor = resolvedCGColor(neutralFill)
            selectionBackgroundView.layer?.borderWidth = displayPreferences.increaseContrast ? 2.0 : 1.0
            selectionBackgroundView.layer?.borderColor = resolvedCGColor(
                displayPreferences.increaseContrast ? .labelColor : NSColor.white.withAlphaComponent(0.24)
            )
            selectionBackgroundView.layer?.shadowColor = resolvedCGColor(.black)
            selectionBackgroundView.layer?.shadowOpacity = 0.30
            selectionBackgroundView.layer?.shadowRadius = 2.0
            selectionBackgroundView.layer?.shadowOffset = .zero
            selectionBackgroundView.layer?.transform = CATransform3DIdentity
            appNameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            appNameLabel.textColor = primaryTextColor
            windowTitleLabel.textColor = secondaryTextColor
            previewContainer.layer?.borderColor = resolvedCGColor(NSColor.white.withAlphaComponent(0.62))
            previewContainer.layer?.borderWidth = 2
        } else {
            layer?.backgroundColor = resolvedCGColor(.clear)
            selectionBackgroundView.layer?.backgroundColor = resolvedCGColor(.clear)
            selectionBackgroundView.layer?.borderWidth = 0
            selectionBackgroundView.layer?.borderColor = nil
            selectionBackgroundView.layer?.shadowColor = nil
            selectionBackgroundView.layer?.shadowOpacity = 0
            selectionBackgroundView.layer?.shadowRadius = 0
            selectionBackgroundView.layer?.shadowOffset = .zero
            selectionBackgroundView.layer?.transform = CATransform3DIdentity
            appNameLabel.font = .systemFont(ofSize: 12, weight: .medium)
            appNameLabel.textColor = primaryTextColor
            windowTitleLabel.textColor = secondaryTextColor
            previewContainer.layer?.borderColor = resolvedCGColor(NSColor.separatorColor)
            previewContainer.layer?.borderWidth = 1
        }
        applySelectionScale()
        applyTextContrastTreatment()
        CATransaction.commit()
    }

    private func applyTextContrastTreatment() {
        // The wallpaper is unconstrained in transparent mode. Back only the glyph bounds,
        // not the switcher surface, so semantic label colors remain legible without a second shadow.
        let backing = backgroundVisible
            ? NSColor.clear
            : NSColor.windowBackgroundColor.withAlphaComponent(0.88)
        appNameLabel.layer?.backgroundColor = resolvedCGColor(backing)
        windowTitleLabel.layer?.backgroundColor = resolvedCGColor(backing)
        appNameLabel.shadow = nil
        windowTitleLabel.shadow = nil
    }
}
