import AppKit
import ApplicationServices

// Only ordinary user windows belong in the switcher. Some applications expose
// transient system dialogs as full-size, layer-zero WindowServer windows.
enum WindowRoleFilter {
    static func excludingAuxiliaryWindows(
        _ windows: [WindowModel],
        subrolesByWindowID: [CGWindowID: String]
    ) -> [WindowModel] {
        windows.filter { window in
            guard let subrole = subrolesByWindowID[window.id] else { return true }
            return subrole == (kAXStandardWindowSubrole as String)
        }
    }

    static func visibleUserWindows(from windows: [WindowModel]) -> [WindowModel] {
        let grouped = Dictionary(grouping: windows, by: \.pid)
        var subroles: [CGWindowID: String] = [:]

        // Single-window apps have no duplicate UI to disambiguate; only ask AX
        // for apps with multiple eligible WindowServer surfaces.
        for (pid, group) in grouped where group.count > 1 {
            let candidateIDs = Set(group.map(\.id))
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.05)
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &result) == .success,
                  let elements = result as? [AXUIElement] else { continue }

            for element in elements {
                guard let id = AXWindowIDAdapter.windowID(for: element),
                      candidateIDs.contains(id) else { continue }
                var subroleValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                      let subrole = subroleValue as? String else { continue }
                subroles[id] = subrole
            }
        }

        return excludingAuxiliaryWindows(windows, subrolesByWindowID: subroles)
    }
}
