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
        spacing = 6
        translatesAutoresizingMaskIntoConstraints = false
        for slot in 1...9 {
            let row = QuickLaunchSlotRowView(
                slot: slot,
                choose: { [weak self] in self?.chooseApplication(for: slot) },
                clear: { [weak self] in self?.clearApplication(for: slot) }
            )
            rows[slot] = row
            addArrangedSubview(row)
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
    private let chooseButton: NSButton
    private let clearButton: NSButton

    init(slot: Int, choose: @escaping () -> Void, clear: @escaping () -> Void) {
        chooseButton = ClosureButton(title: "Choose…", action: choose)
        clearButton = ClosureButton(title: "Clear", action: clear)
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8

        let shortcut = NSTextField(labelWithString: "⌘\(slot)")
        shortcut.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        shortcut.widthAnchor.constraint(equalToConstant: 34).isActive = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.widthAnchor.constraint(equalToConstant: 190).isActive = true
        chooseButton.widthAnchor.constraint(equalToConstant: 78).isActive = true
        clearButton.widthAnchor.constraint(equalToConstant: 58).isActive = true

        addArrangedSubview(shortcut)
        addArrangedSubview(iconView)
        addArrangedSubview(nameLabel)
        addArrangedSubview(chooseButton)
        addArrangedSubview(clearButton)
    }

    required init?(coder: NSCoder) { nil }

    func configure(name: String, icon: NSImage?, assigned: Bool) {
        nameLabel.stringValue = name
        iconView.image = icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
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
