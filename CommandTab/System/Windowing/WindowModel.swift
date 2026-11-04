import AppKit
import CoreGraphics

struct RawWindowInfo {
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let frame: CGRect
    let layer: Int
    let alpha: Double
    let isOnscreen: Bool
    let activationPolicy: NSApplication.ActivationPolicy?
}

struct WindowModel: Equatable, Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    let title: String
    let frame: CGRect
    let displayID: CGDirectDisplayID?
    let spaceIDs: [UInt64]
    let iconKey: String

    init(
        id: CGWindowID,
        pid: pid_t,
        bundleIdentifier: String?,
        appName: String,
        title: String,
        frame: CGRect,
        displayID: CGDirectDisplayID?,
        spaceIDs: [UInt64] = [],
        iconKey: String
    ) {
        self.id = id
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.frame = frame
        self.displayID = displayID
        self.spaceIDs = spaceIDs
        self.iconKey = iconKey
    }

    var displayTitle: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? appName : cleanTitle
    }
}
