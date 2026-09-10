import AppKit

final class SwitcherItemView: NSView {
    private let imageView = NSImageView()
    private let appNameLabel = NSTextField(labelWithString: "")
    private let windowTitleLabel = NSTextField(labelWithString: "")
    private let selectionFillLayer = CALayer()

    var isSelected: Bool = false {
        didSet { updateSelection() }
    }

    init(window: WindowModel, icon: NSImage, mode: SwitcherMode) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false

        appNameLabel.alignment = .center
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.maximumNumberOfLines = 1
        appNameLabel.usesSingleLineMode = true
        appNameLabel.font = .systemFont(ofSize: 11, weight: .semibold)

        windowTitleLabel.alignment = .center
        windowTitleLabel.lineBreakMode = .byTruncatingMiddle
        windowTitleLabel.maximumNumberOfLines = 1
        windowTitleLabel.usesSingleLineMode = true
        windowTitleLabel.font = .systemFont(ofSize: 10, weight: .regular)

        let stack = NSStackView(views: [imageView, appNameLabel, windowTitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 108),
            heightAnchor.constraint(equalToConstant: 76),
            imageView.widthAnchor.constraint(equalToConstant: 40),
            imageView.heightAnchor.constraint(equalToConstant: 40),
            appNameLabel.widthAnchor.constraint(equalToConstant: 92),
            windowTitleLabel.widthAnchor.constraint(equalToConstant: 98),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        selectionFillLayer.cornerRadius = 9
        selectionFillLayer.cornerCurve = .continuous
        layer?.insertSublayer(selectionFillLayer, at: 0)

        configure(window: window, icon: icon, mode: mode)
        updateSelection()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        selectionFillLayer.frame = bounds.insetBy(dx: 2, dy: 2)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSelection()
    }

    func configure(window: WindowModel, icon: NSImage, mode: SwitcherMode) {
        imageView.image = icon
        appNameLabel.stringValue = window.appName

        if mode == .windows, let title = Self.meaningfulWindowTitle(window.title, appName: window.appName) {
            windowTitleLabel.stringValue = title
            windowTitleLabel.isHidden = false
        } else {
            windowTitleLabel.stringValue = ""
            windowTitleLabel.isHidden = true
        }
        updateSelection()
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

    private func updateSelection() {
        if isSelected {
            let dark = usesDarkAppearance
            let selectedBackground = dark
                ? NSColor(white: 0.94, alpha: 1.0)
                : NSColor(white: 0.08, alpha: 1.0)
            let selectedPrimaryText = dark ? NSColor.black : NSColor.white
            let selectedSecondaryText = selectedPrimaryText.withAlphaComponent(dark ? 0.70 : 0.76)

            layer?.backgroundColor = resolvedCGColor(.clear)
            selectionFillLayer.backgroundColor = resolvedCGColor(selectedBackground)
            selectionFillLayer.borderWidth = 1
            selectionFillLayer.borderColor = resolvedCGColor(dark
                ? NSColor.black.withAlphaComponent(0.10)
                : NSColor.white.withAlphaComponent(0.12))
            appNameLabel.textColor = selectedPrimaryText
            windowTitleLabel.textColor = selectedSecondaryText
        } else {
            layer?.backgroundColor = resolvedCGColor(.clear)
            selectionFillLayer.backgroundColor = resolvedCGColor(.clear)
            selectionFillLayer.borderWidth = 0
            selectionFillLayer.borderColor = nil
            appNameLabel.textColor = .labelColor
            windowTitleLabel.textColor = .secondaryLabelColor
        }
    }
}
