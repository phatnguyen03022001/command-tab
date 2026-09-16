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
        spacing = 5
        translatesAutoresizingMaskIntoConstraints = false
        for slot in 1...9 {
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

    func refresh() {
        for slot in 1...9 { refresh(slot: slot) }
    }

    private func refresh(slot: Int) {
        guard let row = rows[slot] else { return }
        guard let assignment = settings.assignment(for: slot) else {
            row.configure(name: "Not Assigned", icon: nil, assigned: false)
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

private final class QuickLaunchSlotRowView: NSStackView {
    private let nameLabel = NSTextField(labelWithString: "Not Assigned")
    private let iconView = NSImageView()
    private let shortcutLabel: NSTextField
    private let chooseButton: NSButton
    private let clearButton: NSButton

    init(slot: Int, choose: @escaping () -> Void, clear: @escaping () -> Void) {
        shortcutLabel = NSTextField(labelWithString: "⌘\(slot)")
        chooseButton = ClosureButton(title: "Choose…", action: choose)
        clearButton = ClosureButton(title: "Clear", action: clear)
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        translatesAutoresizingMaskIntoConstraints = false

        shortcutLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignCenter
        iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        [chooseButton, clearButton].forEach { button in
            button.controlSize = .small
            button.font = .systemFont(ofSize: 12)
            button.bezelStyle = .rounded
        }
        chooseButton.widthAnchor.constraint(equalToConstant: 82).isActive = true
        clearButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        chooseButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        heightAnchor.constraint(equalToConstant: 28).isActive = true

        addArrangedSubview(shortcutLabel)
        addArrangedSubview(iconView)
        addArrangedSubview(nameLabel)
        addArrangedSubview(chooseButton)
        addArrangedSubview(clearButton)
    }

    required init?(coder: NSCoder) { nil }

    func configure(name: String, icon: NSImage?, assigned: Bool) {
        nameLabel.stringValue = name
        nameLabel.textColor = assigned ? .labelColor : .secondaryLabelColor
        iconView.image = icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        iconView.contentTintColor = assigned ? nil : .tertiaryLabelColor
        chooseButton.title = assigned ? "Change…" : "Choose…"
        clearButton.isEnabled = assigned
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
