import AppKit
import CoreGraphics

@main
struct SpaceIdentityDiagnosticProbe {
    static func main() {
        let displays = DisplayResolver.activeDisplayIDs()
        guard let current = SpaceIdentityAdapter.currentSpaceByDisplay(displayIDs: displays) else {
            fputs("FAIL: current Space context unavailable\n", stderr)
            exit(1)
        }
        for (displayID, spaceID) in current.sorted(by: { $0.key < $1.key }) {
            print("CURRENT: display=\(displayID) currentSpace=\(spaceID)")
        }

        let visibleSpaces = Set(current.values)
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        let dictionaries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let currentPID = ProcessInfo.processInfo.processIdentifier

        for dictionary in dictionaries {
            guard let number = dictionary[kCGWindowNumber as String] as? NSNumber,
                  let pidNumber = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                  let bounds = dictionary[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { continue }

            let pid = pid_t(pidNumber.int32Value)
            let runningApp = NSRunningApplication(processIdentifier: pid)
            guard runningApp?.activationPolicy == .regular else { continue }
            let raw = RawWindowInfo(
                windowID: number.uint32Value,
                pid: pid,
                appName: dictionary[kCGWindowOwnerName as String] as? String ?? "",
                title: "",
                frame: frame,
                layer: (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                alpha: (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                isOnscreen: (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                activationPolicy: runningApp?.activationPolicy
            )
            let spaces = SpaceIdentityAdapter.spaceIDs(for: raw.windowID) ?? []
            let displayID = DisplayResolver.displayID(for: raw.frame)
            let publicEligible = WindowEligibilityPolicy.accepts(raw, currentPID: currentPID)
            let spaceEligible = !spaces.isEmpty && spaces.contains { visibleSpaces.contains($0) }
            let eligible = publicEligible && spaceEligible
            let display = displayID.map(String.init) ?? "unknown"
            print(
                "WINDOW: wid=\(raw.windowID) pid=\(raw.pid) app=\(raw.appName) " +
                "onscreen=\(raw.isOnscreen) display=\(display) spaces=\(spaces) eligible=\(eligible)"
            )
        }
    }
}
