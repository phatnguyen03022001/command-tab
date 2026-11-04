import AppKit
import ServiceManagement

enum RevealDelay: String, CaseIterable {
    case instant
    case ms80
    case ms150

    var seconds: TimeInterval {
        switch self {
        case .instant: return 0
        case .ms80: return 0.080
        case .ms150: return 0.150
        }
    }

    var title: String {
        switch self {
        case .instant: return "Instant"
        case .ms80: return "80 ms"
        case .ms150: return "150 ms"
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

extension DisplayScope {
    var title: String {
        switch self {
        case .allVisible: return "All Currently Visible Displays"
        case .activeOnly: return "Active Display Only"
        }
    }
}

enum SwitcherMode: String, CaseIterable {
    case applications
    case windows

    var title: String {
        switch self {
        case .applications: return "Applications"
        case .windows: return "Windows"
        }
    }
}

final class CommandTabSettings {
    static let shared = CommandTabSettings()

    private enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let appearance = "appearance"
        static let revealDelay = "revealDelay"
        static let displayScope = "displayScope"
        static let switcherMode = "switcherMode"
        static let showBackground = "showBackground"
        static let glassDarkness = "glassDarkness"
        static let backgroundBlur = "backgroundBlur"
        static let iconSize = "iconSize"
        static let appSpacing = "appSpacing"
        static let selectedIconZoom = "selectedIconZoom"
        static let showAppNames = "showAppNames"
    }

    static let didChangeNotification = Notification.Name("CommandTabSettingsDidChangeNotification")

    private let defaults: UserDefaults
    var onChange: (() -> Void)?

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        onChange?()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showMenuBarIcon: true,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.revealDelay: RevealDelay.instant.rawValue,
            Key.displayScope: DisplayScope.allVisible.rawValue,
            Key.switcherMode: SwitcherMode.applications.rawValue,
            Key.showBackground: true,
            Key.glassDarkness: 10,
            Key.backgroundBlur: 0,
            Key.iconSize: 72,
            Key.appSpacing: 10,
            Key.selectedIconZoom: 115,
            Key.showAppNames: true
        ])
    }

    var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: Key.showMenuBarIcon) }
        set { defaults.set(newValue, forKey: Key.showMenuBarIcon); notifyChanged() }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance); notifyChanged() }
    }

    var revealDelay: RevealDelay {
        get { RevealDelay(rawValue: defaults.string(forKey: Key.revealDelay) ?? "") ?? .instant }
        set { defaults.set(newValue.rawValue, forKey: Key.revealDelay); notifyChanged() }
    }

    var displayScope: DisplayScope {
        get { DisplayScope(rawValue: defaults.string(forKey: Key.displayScope) ?? "") ?? .allVisible }
        set { defaults.set(newValue.rawValue, forKey: Key.displayScope); notifyChanged() }
    }

    var switcherMode: SwitcherMode {
        get { SwitcherMode(rawValue: defaults.string(forKey: Key.switcherMode) ?? "") ?? .applications }
        set { defaults.set(newValue.rawValue, forKey: Key.switcherMode); notifyChanged() }
    }

    var showBackground: Bool {
        get { defaults.bool(forKey: Key.showBackground) }
        set { defaults.set(newValue, forKey: Key.showBackground); notifyChanged() }
    }

    var glassDarkness: Int {
        get {
            let val = defaults.integer(forKey: Key.glassDarkness)
            return max(0, min(100, val))
        }
        set {
            let clamped = max(0, min(100, newValue))
            defaults.set(clamped, forKey: Key.glassDarkness)
            notifyChanged()
        }
    }

    var glassDarknessNormalized: Double {
        Double(glassDarkness) / 100.0
    }

    func smokeAlpha(isDark: Bool) -> CGFloat {
        let normalized = glassDarknessNormalized
        return CGFloat(isDark ? normalized * 0.18 : normalized * 0.30)
    }

    var backgroundBlur: Int {
        get {
            let val = defaults.integer(forKey: Key.backgroundBlur)
            return max(0, min(100, val))
        }
        set {
            let clamped = max(0, min(100, newValue))
            defaults.set(clamped, forKey: Key.backgroundBlur)
            notifyChanged()
        }
    }

    var backgroundBlurNormalized: Double {
        Double(backgroundBlur) / 100.0
    }

    var diffusionBackingAlpha: CGFloat {
        CGFloat(backgroundBlurNormalized * 0.25)
    }

    var iconSize: Int {
        get {
            let val = defaults.integer(forKey: Key.iconSize)
            return Self.normalizeIconSize(val)
        }
        set {
            let normalized = Self.normalizeIconSize(newValue)
            defaults.set(normalized, forKey: Key.iconSize)
            notifyChanged()
        }
    }

    static func normalizeIconSize(_ value: Int) -> Int {
        let clamped = max(48, min(96, value))
        let stepOffset = clamped - 48
        let snappedOffset = Int(round(Double(stepOffset) / 4.0)) * 4
        return max(48, min(96, 48 + snappedOffset))
    }

    var appSpacing: Int {
        get { Self.normalizeAppSpacing(defaults.integer(forKey: Key.appSpacing)) }
        set {
            defaults.set(Self.normalizeAppSpacing(newValue), forKey: Key.appSpacing)
            notifyChanged()
        }
    }

    static func normalizeAppSpacing(_ value: Int) -> Int {
        let clamped = max(4, min(24, value))
        let snapped = Int(round(Double(clamped - 4) / 2.0)) * 2 + 4
        return max(4, min(24, snapped))
    }

    var selectedIconZoom: Int {
        get { Self.normalizeSelectedIconZoom(defaults.integer(forKey: Key.selectedIconZoom)) }
        set {
            defaults.set(Self.normalizeSelectedIconZoom(newValue), forKey: Key.selectedIconZoom)
            notifyChanged()
        }
    }

    var selectedIconScale: CGFloat {
        CGFloat(selectedIconZoom) / 100.0
    }

    static func normalizeSelectedIconZoom(_ value: Int) -> Int {
        max(100, min(175, value))
    }

    var showAppNames: Bool {
        get { defaults.bool(forKey: Key.showAppNames) }
        set { defaults.set(newValue, forKey: Key.showAppNames); notifyChanged() }
    }

    func resetAppearance() {
        defaults.set(AppearanceMode.system.rawValue, forKey: Key.appearance)
        defaults.set(true, forKey: Key.showBackground)
        defaults.set(10, forKey: Key.glassDarkness)
        defaults.set(0, forKey: Key.backgroundBlur)
        defaults.set(72, forKey: Key.iconSize)
        defaults.set(10, forKey: Key.appSpacing)
        defaults.set(115, forKey: Key.selectedIconZoom)
        defaults.set(true, forKey: Key.showAppNames)
        notifyChanged()
    }

    func applyAppearance() {
        NSApp.appearance = appearanceMode.appearance
    }

    func launchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
