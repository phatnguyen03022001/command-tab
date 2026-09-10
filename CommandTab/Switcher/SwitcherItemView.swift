import AppKit

final class SwitcherItemView: NSView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "")

    var isSelected: Bool = false {
        didSet { updateSelection() }
    }

    init(window: WindowModel, icon: NSImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)

        appLabel.alignment = .center
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.maximumNumberOfLines = 1
        appLabel.font = .systemFont(ofSize: 10)
        appLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [imageView, titleLabel, appLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 116),
            heightAnchor.constraint(equalToConstant: 94),
            imageView.widthAnchor.constraint(equalToConstant: 42),
            imageView.heightAnchor.constraint(equalToConstant: 42),
            titleLabel.widthAnchor.constraint(equalToConstant: 94),
            appLabel.widthAnchor.constraint(equalToConstant: 94),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        configure(window: window, icon: icon)
        updateSelection()
    }

    required init?(coder: NSCoder) { nil }

    func configure(window: WindowModel, icon: NSImage) {
        imageView.image = icon
        titleLabel.stringValue = window.displayTitle
        appLabel.stringValue = window.appName
    }

    private func updateSelection() {
        layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.28).cgColor
            : NSColor.clear.cgColor
    }
}
