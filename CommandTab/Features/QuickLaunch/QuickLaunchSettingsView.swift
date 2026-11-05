import AppKit
import UniformTypeIdentifiers

final class QuickLaunchSettingsView: NSStackView {
    private let settings: QuickLaunchSettings
    private var rows: [Int: QuickLaunchSlotRowView] = [:]
    private var iconCache: [String: NSImage] = [:]

    init(settings: QuickLaunchSettings) {
        self.settings = settings
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        updateColors()

        for slot in 1...9 {
            if slot > 1 {
                let separator = makeSeparator()
                addArrangedSubview(separator)
                separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12).isActive = true
                separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12).isActive = true
            }

            let row = QuickLaunchSlotRowView(
                slot: slot,
                choose: { [weak self] in self?.chooseApplication(for: slot) },
                clear: { [weak self] in self?.clearApplication(for: slot) }
            )
            rows[slot] = row
            addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        }
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        }
    }

    private func makeSeparator() -> NSView {
        let line = SeparatorLineView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    func refresh() {
        for slot in 1...9 { refresh(slot: slot) }
    }

    private func refresh(slot: Int) {
        guard let row = rows[slot] else { return }
        guard let assignment = settings.assignment(for: slot) else {
            row.configure(name: "Not Configured", icon: nil, assigned: false)
            return
        }
        let path = assignment.applicationURL.standardizedFileURL.path
        let icon: NSImage
        if let cached = iconCache[path] {
            icon = cached
        } else {
            icon = NSWorkspace.shared.icon(forFile: path)
            iconCache[path] = icon
        }
        row.configure(name: assignment.displayName, icon: icon, assigned: true)
    }

    private func chooseApplication(for slot: Int) {
        let panel = NSOpenPanel()
        panel.title = "Choose Application for ⌘\(slot)"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url,
                  let assignment = QuickLaunchAssignment.fromApplicationURL(url) else { return }
            self?.settings.setAssignment(assignment, for: slot)
            self?.refresh(slot: slot)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func clearApplication(for slot: Int) {
        settings.clearAssignment(for: slot)
        refresh(slot: slot)
    }
}

private final class SeparatorLineView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        updateColor()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        }
    }
}

private final class QuickLaunchSlotRowView: NSStackView {
    private let slot: Int
    private let nameLabel = NSTextField(labelWithString: "Not Configured")
    private let iconView = NSImageView()
    private let badgeView = ShortcutBadgeView()
    private let chooseButton: NSButton
    private let clearButton: NSButton

    init(slot: Int, choose: @escaping () -> Void, clear: @escaping () -> Void) {
        self.slot = slot
        chooseButton = ClosureButton(title: "Assign…", action: choose)
        clearButton = ClosureButton(title: "Clear", action: clear)
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 10
        translatesAutoresizingMaskIntoConstraints = false

        badgeView.setShortcut("⌘\(slot)")

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignCenter
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true

        nameLabel.font = .systemFont(ofSize: 13, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        [chooseButton, clearButton].forEach { button in
            button.controlSize = .small
            button.font = .systemFont(ofSize: 12)
            button.bezelStyle = .rounded
        }
        chooseButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
        clearButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
        chooseButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        heightAnchor.constraint(equalToConstant: 34).isActive = true

        let leadingSpacer = NSView()
        leadingSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadingSpacer.widthAnchor.constraint(equalToConstant: 2).isActive = true

        let trailingSpacer = NSView()
        trailingSpacer.translatesAutoresizingMaskIntoConstraints = false
        trailingSpacer.widthAnchor.constraint(equalToConstant: 2).isActive = true

        addArrangedSubview(leadingSpacer)
        addArrangedSubview(badgeView)
        addArrangedSubview(iconView)
        addArrangedSubview(nameLabel)
        addArrangedSubview(chooseButton)
        addArrangedSubview(clearButton)
        addArrangedSubview(trailingSpacer)
    }

    required init?(coder: NSCoder) { nil }

    func configure(name: String, icon: NSImage?, assigned: Bool) {
        nameLabel.stringValue = name
        nameLabel.textColor = assigned ? .labelColor : .secondaryLabelColor
        nameLabel.font = .systemFont(ofSize: 13, weight: assigned ? .medium : .regular)
        iconView.image = icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Unassigned")
        iconView.contentTintColor = assigned ? nil : .secondaryLabelColor
        chooseButton.title = assigned ? "Change…" : "Assign…"
        clearButton.isEnabled = assigned
        chooseButton.setAccessibilityLabel(
            assigned ? "Change application for Command+\(slot), currently \(name)"
                     : "Assign application to Command+\(slot)"
        )
        clearButton.setAccessibilityLabel("Clear application from Command+\(slot), \(name)")
    }
}

private final class ShortcutBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        label.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .bold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 22),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateColor()
    }

    required init?(coder: NSCoder) { nil }

    func setShortcut(_ shortcut: String) {
        label.stringValue = shortcut
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        }
    }
}

private final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.handler = action
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        self.action = #selector(performAction)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func performAction() {
        handler()
    }
}
