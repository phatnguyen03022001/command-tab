import AppKit

enum WindowEligibilityPolicy {
    private static let rejectedOwners: Set<String> = [
        "Window Server",
        "Dock",
        "SystemUIServer",
        "Control Center",
        "NotificationCenter",
        "loginwindow",
        "CommandTab"
    ]

    static func accepts(_ window: RawWindowInfo, currentPID: pid_t) -> Bool {
        guard window.isOnscreen else { return false }
        guard window.layer == 0 else { return false }
        guard window.alpha > 0.01 else { return false }
        guard window.pid > 0, window.pid != currentPID else { return false }
        guard !rejectedOwners.contains(window.appName) else { return false }
        guard window.activationPolicy == .regular else { return false }
        guard window.frame.width >= 96, window.frame.height >= 64 else { return false }
        guard window.frame.isNull == false, window.frame.isInfinite == false else { return false }
        return true
    }
}
