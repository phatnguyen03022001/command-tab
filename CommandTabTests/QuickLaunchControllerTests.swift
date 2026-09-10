import Foundation
import CoreGraphics

private final class StubAssignments: QuickLaunchAssignmentProviding {
    var values: [Int: QuickLaunchAssignment] = [:]
    func assignment(for slot: Int) -> QuickLaunchAssignment? { values[slot] }
}

private final class StubApplicationService: QuickLaunchApplicationServing {
    var resolvedURL: URL?
    var resolvedAssignments: [QuickLaunchAssignment] = []
    var launched: [(URL, QuickLaunchAssignment)] = []

    func resolve(_ assignment: QuickLaunchAssignment) -> URL? {
        resolvedAssignments.append(assignment)
        return resolvedURL
    }

    func launchOrActivate(_ url: URL, assignment: QuickLaunchAssignment) {
        launched.append((url, assignment))
    }
}

@main
struct QuickLaunchControllerTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func sample() -> QuickLaunchAssignment {
        QuickLaunchAssignment(
            bundleIdentifier: "com.example.App",
            applicationURL: URL(fileURLWithPath: "/Applications/Example.app"),
            displayName: "Example"
        )
    }

    static func main() {
        let assignments = StubAssignments()
        let service = StubApplicationService()
        service.resolvedURL = URL(fileURLWithPath: "/Applications/Example.app")
        let controller = QuickLaunchController(settings: assignments, applicationService: service)

        require(!controller.handle(slot: 1, isRepeat: false), "empty slot must pass through")
        require(service.resolvedAssignments.isEmpty, "empty slot must not resolve an app")

        let configured = sample()
        assignments.values[1] = configured
        require(controller.handle(slot: 1, isRepeat: false), "configured resolvable slot must be handled")
        require(service.launched.count == 1, "configured press must launch or activate exactly once")
        require(service.launched[0].1 == configured, "controller must use configured assignment")

        require(controller.handle(slot: 1, isRepeat: true), "repeat for valid configured slot must be consumed")
        require(service.launched.count == 1, "key repeat must not launch or activate again")

        service.resolvedURL = nil
        require(!controller.handle(slot: 1, isRepeat: false), "unresolvable assignment must pass through")
        require(service.launched.count == 1, "unresolvable assignment must not launch anything")

        assignments.values[1] = nil
        require(!controller.handle(slot: 1, isRepeat: false), "cleared assignment must pass through")

        let command: CGEventFlags = [.maskCommand]
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 20, flags: command, switcherActive: false) == 3,
                "Command-3 must map to slot 3")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 21, flags: command, switcherActive: false) == 4,
                "Command-4 must map to slot 4")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 20, flags: [.maskCommand, .maskShift], switcherActive: false) == nil,
                "Command-Shift-3 must pass through")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 21, flags: [.maskCommand, .maskShift], switcherActive: false) == nil,
                "Command-Shift-4 must pass through")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 20, flags: [.maskCommand, .maskAlternate], switcherActive: false) == nil,
                "Command-Option-3 must pass through")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 20, flags: [.maskCommand, .maskControl], switcherActive: false) == nil,
                "Command-Control-3 must pass through")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 20, flags: [.maskCommand, .maskSecondaryFn], switcherActive: false) == nil,
                "Command-Fn-3 must pass through")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 20, flags: [.maskCommand, .maskAlphaShift], switcherActive: false) == 3,
                "Caps Lock must not block Command-3")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 20, flags: [.maskCommand, .maskNumericPad, .maskNonCoalesced], switcherActive: false) == 3,
                "unrelated event-state flags must not block Command-3")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 20, flags: [], switcherActive: false) == nil,
                "digit without Command must pass through")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 48, flags: command, switcherActive: false) == nil,
                "Command-Tab must remain outside quick launch")
        require(QuickLaunchShortcutPolicy.slot(forKeyCode: 20, flags: command, switcherActive: true) == nil,
                "active switcher session must suppress quick launch handling")

        print("QuickLaunchControllerTests passed")
    }
}
