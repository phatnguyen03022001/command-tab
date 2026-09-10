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

enum DisplayScope: String, CaseIterable {
    case allVisible
    case activeOnly

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
    }

    private let defaults: UserDefaults
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showMenuBarIcon: true,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.revealDelay: RevealDelay.ms80.rawValue,
            Key.displayScope: DisplayScope.allVisible.rawValue,
            Key.switcherMode: SwitcherMode.applications.rawValue
        ])
    }

    var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: Key.showMenuBarIcon) }
        set { defaults.set(newValue, forKey: Key.showMenuBarIcon); onChange?() }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance); onChange?() }
    }

    var revealDelay: RevealDelay {
        get { RevealDelay(rawValue: defaults.string(forKey: Key.revealDelay) ?? "") ?? .ms80 }
        set { defaults.set(newValue.rawValue, forKey: Key.revealDelay); onChange?() }
    }

    var displayScope: DisplayScope {
        get { DisplayScope(rawValue: defaults.string(forKey: Key.displayScope) ?? "") ?? .allVisible }
        set { defaults.set(newValue.rawValue, forKey: Key.displayScope); onChange?() }
    }

    var switcherMode: SwitcherMode {
        get { SwitcherMode(rawValue: defaults.string(forKey: Key.switcherMode) ?? "") ?? .applications }
        set { defaults.set(newValue.rawValue, forKey: Key.switcherMode); onChange?() }
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
