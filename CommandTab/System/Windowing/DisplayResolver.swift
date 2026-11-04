import AppKit
import CoreGraphics

enum DisplayResolver {
    static func keyboardContextDisplayID(from orderedWindows: [WindowModel]) -> CGDirectDisplayID? {
        if let displayID = orderedWindows.first(where: { $0.displayID != nil })?.displayID {
            return displayID
        }
        return pointerFallbackDisplayID()
    }

    static func pointerFallbackDisplayID() -> CGDirectDisplayID? {
        let mouseLocation = CGEvent(source: nil)?.location ?? .zero
        for displayID in activeDisplayIDs() {
            if CGDisplayBounds(displayID).contains(mouseLocation) {
                return displayID
            }
        }
        return CGMainDisplayID()
    }

    static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGMainDisplayID()]
        }
        var displays = Array(repeating: CGDirectDisplayID(0), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return [CGMainDisplayID()]
        }
        return Array(displays.prefix(Int(count)))
    }

    static func displayID(for frame: CGRect) -> CGDirectDisplayID? {
        var bestDisplay: CGDirectDisplayID?
        var bestArea: CGFloat = 0
        for displayID in activeDisplayIDs() {
            let intersection = CGDisplayBounds(displayID).intersection(frame)
            let area = max(0, intersection.width) * max(0, intersection.height)
            if area > bestArea {
                bestArea = area
                bestDisplay = displayID
            }
        }
        return bestDisplay
    }

    static func frame(_ frame: CGRect, intersects displayID: CGDirectDisplayID) -> Bool {
        !CGDisplayBounds(displayID).intersection(frame).isNull
    }
}
