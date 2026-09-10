import AppKit

final class SwitcherItemView: NSView {
    private let imageView = NSImageView()
    private let appNameLabel = NSTextField(labelWithString: "")
    private let windowTitleLabel = NSTextField(labelWithString: "")
    var isSelected: Bool = false {
        didSet { updateSelection() }
    }

    init(window: WindowModel, icon: NSImage, mode: SwitcherMode) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        appNameLabel.alignment = .center
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.maximumNumberOfLines = 1
        appNameLabel.font = .systemFont(ofSize: 11, weight: .medium)

        windowTitleLabel.alignment = .center
        windowTitleLabel.lineBreakMode = .byTruncatingTail
        windowTitleLabel.maximumNumberOfLines = 1
        windowTitleLabel.font = .systemFont(ofSize: 10, weight: .regular)

        let stack = NSStackView(views: [imageView, appNameLabel, windowTitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 116),
            heightAnchor.constraint(equalToConstant: 82),
            imageView.widthAnchor.constraint(equalToConstant: 42),
            imageView.heightAnchor.constraint(equalToConstant: 42),
            appNameLabel.widthAnchor.constraint(equalToConstant: 94),
            windowTitleLabel.widthAnchor.constraint(equalToConstant: 104),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        configure(window: window, icon: icon, mode: mode)
        updateSelection()
    }

    required init?(coder: NSCoder) { nil }

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

    private func updateSelection() {
        if isSelected {
            layer?.backgroundColor = resolvedCGColor(.selectedContentBackgroundColor)
            appNameLabel.textColor = .alternateSelectedControlTextColor
            windowTitleLabel.textColor = .alternateSelectedControlTextColor
        } else {
            layer?.backgroundColor = resolvedCGColor(.controlBackgroundColor)
            appNameLabel.textColor = .labelColor
            windowTitleLabel.textColor = .secondaryLabelColor
        }
    }
}
