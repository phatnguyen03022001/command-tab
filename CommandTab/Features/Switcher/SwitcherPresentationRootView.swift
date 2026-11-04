import AppKit

final class SwitcherPresentationRootView: NSView {
    static let outerCornerRadius: CGFloat = 28.0

    let materialContainer: NSView
    let diffusionBacking: NSVisualEffectView
    let smokedUnderlay: NSView
    let glassView: NSView
    let foregroundView: NSView
    var onAppearanceChange: (() -> Void)?

    init(
        materialContainer: NSView,
        diffusionBacking: NSVisualEffectView,
        smokedUnderlay: NSView,
        glassView: NSView,
        foregroundView: NSView
    ) {
        self.materialContainer = materialContainer
        self.diffusionBacking = diffusionBacking
        self.smokedUnderlay = smokedUnderlay
        self.glassView = glassView
        self.foregroundView = foregroundView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.masksToBounds = false
        layer?.borderWidth = 0
        layer?.borderColor = nil
        layer?.backgroundColor = nil

        addSubview(materialContainer)
        addSubview(glassView)
        if !Self.nativeGlassOwnsContent(glassView) {
            addSubview(foregroundView)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        materialContainer.frame = bounds
        diffusionBacking.frame = materialContainer.bounds
        smokedUnderlay.frame = materialContainer.bounds
        glassView.frame = bounds
        if foregroundView.superview === self {
            foregroundView.frame = bounds
        }
    }

    func setBackgroundVisible(_ visible: Bool) {
        materialContainer.isHidden = !visible

        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            if visible {
                if glass.contentView !== foregroundView {
                    foregroundView.removeFromSuperview()
                    glass.contentView = foregroundView
                }
                glass.isHidden = false
            } else {
                if glass.contentView === foregroundView {
                    glass.contentView = nil
                }
                glass.isHidden = true
                if foregroundView.superview !== self {
                    addSubview(foregroundView, positioned: .above, relativeTo: glassView)
                }
                foregroundView.frame = bounds
            }
        } else {
            glassView.isHidden = !visible
        }
    }

    private static func nativeGlassOwnsContent(_ view: NSView) -> Bool {
        if #available(macOS 26.0, *) {
            return view is NSGlassEffectView
        }
        return false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

}

final class SwitcherPanelFallbackRootView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 28
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
            border = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        }
        layer?.borderColor = border
    }
}
