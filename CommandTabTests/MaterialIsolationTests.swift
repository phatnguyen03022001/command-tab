import AppKit
import CoreGraphics
import Foundation

@main
struct MaterialIsolationTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func panel(of controller: SwitcherPanelController) -> NSPanel? {
        guard let value = Mirror(reflecting: controller).children.first(where: { $0.label == "panel" })?.value else { return nil }
        return Mirror(reflecting: value).children.first?.value as? NSPanel
    }

    static func sampleWindow() -> WindowModel {
        WindowModel(
            id: 7001, pid: getpid(), bundleIdentifier: "probe.material",
            appName: "Probe", title: "Probe Window",
            frame: .zero, displayID: CGMainDisplayID(), spaceIDs: [1], iconKey: "probe.material"
        )
    }

    static func configureProbe(_ name: String, root: SwitcherPresentationRootView, dark: Bool) {
        root.diffusionBacking.isHidden = true
        root.diffusionBacking.alphaValue = 0
        root.diffusionBacking.state = .inactive
        root.glassView.alphaValue = 1.0
        root.smokedUnderlay.isHidden = name != "M3"
        root.smokedUnderlay.layer?.backgroundColor = name == "M3"
            ? NSColor.black.withAlphaComponent(dark ? 0.02 : 0.03).cgColor
            : NSColor.clear.cgColor
        if #available(macOS 27.0, *), let glass = root.glassView as? NSGlassEffectView {
            glass.effectIsInteractive = name != "M1"
        }
    }

    static func smokeAlpha(_ view: NSView) -> CGFloat {
        guard let color = view.layer?.backgroundColor,
              let nsColor = NSColor(cgColor: color) else { return -1 }
        return nsColor.alphaComponent
    }

    static func main() {
        _ = NSApplication.shared
        let suite = "commandtab.material.isolation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CommandTabSettings(defaults: defaults)

        require(settings.glassDarkness == 10, "canonical Clear glass must default to minimal dimming")
        require(settings.backgroundBlur == 0, "M1 canonical default must have no backing diffusion")
        require(settings.iconSize == 72, "material isolation must preserve 72pt icon default")

        let controller = SwitcherPanelController(settings: settings)
        controller.show(windows: [sampleWindow()], selectedIndex: 0, sessionID: 77, mode: .applications)
        guard let panel = panel(of: controller), let root = panel.contentView as? SwitcherPresentationRootView else {
            fputs("FAIL: material isolation root unavailable\n", stderr)
            exit(1)
        }

        require(panel.alphaValue == 1.0, "panel alpha must remain 1.0")
        require(abs(root.glassView.alphaValue - 1.0) < 0.001, "canonical native glass must render at full alpha")
        require(root.diffusionBacking.isHidden, "Blur 0 must hide backing VEV")
        require(root.diffusionBacking.alphaValue == 0.0, "Blur 0 must zero backing VEV alpha")
        require(root.diffusionBacking.state == .inactive, "hidden backing VEV must not remain active")
        let defaultIsDark = panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let expectedDefaultSmoke = settings.smokeAlpha(isDark: defaultIsDark)
        require(!root.smokedUnderlay.isHidden, "canonical Clear glass must include minimal dimming")
        require(abs(smokeAlpha(root.smokedUnderlay) - expectedDefaultSmoke) < 0.001, "canonical Clear glass dimming must match settings mapping")

        for name in ["M1", "M2", "M3"] {
            configureProbe(name, root: root, dark: false)
            require(root.diffusionBacking.isHidden, "\(name) must disable backing VEV")
            require(root.diffusionBacking.alphaValue == 0.0, "\(name) backing alpha must be zero")
            require(root.diffusionBacking.state == .inactive, "\(name) backing VEV must be inactive")
            require(root.glassView.alphaValue == 1.0, "\(name) glass alpha must stay 1.0")
            require(panel.alphaValue == 1.0, "\(name) panel alpha must stay 1.0")
            if name == "M3" {
                require(!root.smokedUnderlay.isHidden, "M3 must include minimal smoke")
                require(abs(smokeAlpha(root.smokedUnderlay) - 0.03) < 0.001, "M3 Light smoke must be exactly 0.03")
                configureProbe(name, root: root, dark: true)
                require(abs(smokeAlpha(root.smokedUnderlay) - 0.02) < 0.001, "M3 Dark smoke must be exactly 0.02")
            } else {
                require(root.smokedUnderlay.isHidden, "\(name) must have no visible smoke")
                require(smokeAlpha(root.smokedUnderlay) == 0.0, "\(name) smoke alpha must be zero")
            }
        }

        if #available(macOS 27.0, *), let glass = root.glassView as? NSGlassEffectView {
            configureProbe("M1", root: root, dark: false)
            require(glass.effectIsInteractive == false, "M1 must keep interactive glass disabled")
            configureProbe("M2", root: root, dark: false)
            require(glass.effectIsInteractive == true, "M2 must enable interactive glass")
            configureProbe("M3", root: root, dark: false)
            require(glass.effectIsInteractive == true, "M3 must enable interactive glass")
        }

        controller.close()
        print("MaterialIsolationTests passed")
    }
}
