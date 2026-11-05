import AppKit
import CoreGraphics

private final class RoutingDelegate: HotKeyEventTapDelegate {
    var isSwitcherSessionActive = false
    var canStart = true
    var tabCount = 0
    var reverseCount = 0
    var commits = 0
    var cancels = 0
    var arrows: [Bool] = []
    var quits = 0

    func commandTabPressed(reverse: Bool) -> Bool {
        guard isSwitcherSessionActive || canStart else { return false }
        isSwitcherSessionActive = true
        tabCount += 1
        if reverse { reverseCount += 1 }
        return true
    }
    func commandKeyReleased() -> Bool {
        guard isSwitcherSessionActive else { return false }
        commits += 1
        isSwitcherSessionActive = false
        return true
    }
    func cancelSwitcher() -> Bool {
        cancels += 1
        isSwitcherSessionActive = false
        return true
    }
    func arrowPressed(reverse: Bool) -> Bool {
        arrows.append(reverse)
        return true
    }
    func quitSelectedApplication() -> Bool {
        quits += 1
        return true
    }
}

private final class RoutingQuickLaunchService: QuickLaunchApplicationServing {
    var resolvedURL: URL?
    var launches = 0
    func resolve(_ assignment: QuickLaunchAssignment) -> URL? { resolvedURL }
    func launchOrActivate(_ url: URL, assignment: QuickLaunchAssignment) { launches += 1 }
}

@main
struct HotKeyEventRoutingTests {
    static let proxy = OpaquePointer(bitPattern: 1)!
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func event(_ key: UInt16, _ flags: CGEventFlags = [], down: Bool = true, repeatKey: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)!
        event.flags = flags
        if repeatKey { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return event
    }
    @discardableResult
    static func send(_ tap: HotKeyEventTap, _ key: UInt16, _ flags: CGEventFlags = [],
                     down: Bool = true, repeatKey: Bool = false, type: CGEventType? = nil) -> Bool {
        tap.handle(proxy: proxy, type: type ?? (down ? .keyDown : .keyUp),
                   event: event(key, flags, down: down, repeatKey: repeatKey)) == nil
    }

    static func main() {
        let delegate = RoutingDelegate()
        var launches = 0
        let tap = HotKeyEventTap(delegate: delegate) { key, flags, active, repeatKey in
            guard key == 18, flags.contains(.maskCommand), !active, !repeatKey else { return false }
            launches += 1
            return true
        }
        let command: CGEventFlags = [.maskCommand]
        let shiftCommand: CGEventFlags = [.maskCommand, .maskShift]

        // Failed initialization and inactive state never capture the native shortcuts.
        delegate.canStart = false
        require(!send(tap, 48, command), "failed Command-Tab start passes through")
        require(!send(tap, 48, command, down: false), "failed Tab up passes through")
        require(!send(tap, 48, shiftCommand), "failed Shift-Tab start passes through")
        require(!send(tap, 48, shiftCommand, down: false), "failed reverse Tab up passes through")
        for key: UInt16 in [13, 1, 36, 6] { // W, S, Return, Z
            require(!send(tap, key, command), "inactive Command shortcut down passes through \(key)")
            require(!send(tap, key, command, down: false), "inactive Command shortcut up passes through \(key)")
        }
        require(!send(tap, 12, command), "inactive Command-Q passes through")
        require(!send(tap, 12, command, down: false), "inactive Q up passes through")
        require(send(tap, 18, command), "Quick Launch owns configured Command-1")
        require(send(tap, 18, command, down: false), "Quick Launch owns matching up")
        require(launches == 1, "Quick Launch runs only once")

        delegate.canStart = true
        require(send(tap, 48, command), "valid Command-Tab starts active session")
        require(delegate.isSwitcherSessionActive && delegate.tabCount == 1, "session started")
        require(send(tap, 48, command, down: false), "owned Tab up consumed")
        require(send(tap, 48, shiftCommand), "Shift-Command-Tab consumed")
        require(delegate.reverseCount == 1, "reverse navigation invoked")
        require(send(tap, 48, shiftCommand, down: false), "reverse Tab up consumed")
        require(send(tap, 48, command, repeatKey: true), "Tab autorepeat stays owned")
        require(delegate.tabCount == 3, "Tab autorepeat navigates")
        require(send(tap, 48, command, down: false), "repeat Tab up consumed")

        for key: UInt16 in [13, 1, 36, 6] {
            require(send(tap, key, command), "active Command shortcut down must not leak \(key)")
            require(send(tap, key, command, repeatKey: true), "active shortcut autorepeat consumed \(key)")
            require(send(tap, key, command, down: false), "owned shortcut up consumed \(key)")
        }
        require(send(tap, 18, command), "unassigned Quick Launch during session does not leak")
        require(send(tap, 18, command, down: false), "active Quick Launch up owned")
        require(launches == 1, "active session never invokes Quick Launch")
        for key: UInt16 in [123, 125, 124, 126] {
            require(send(tap, key, command), "arrow navigation consumed \(key)")
            require(send(tap, key, command, down: false), "arrow up consumed \(key)")
        }
        require(delegate.arrows == [true, false, false, true], "arrow direction preserved")
        require(send(tap, 124, command), "Switcher arrow starts a held navigation")
        require(send(tap, 124, command, repeatKey: true), "Switcher arrow repeat stays owned")
        require(send(tap, 124, command, down: false), "Switcher arrow up stays owned")
        require(Array(delegate.arrows.suffix(2)) == [false, false], "Switcher arrow repeat still navigates")
        require(send(tap, 12, command), "Command-Q owned")
        require(send(tap, 12, command, repeatKey: true), "Command-Q repeat owned")
        require(delegate.quits == 1, "Command-Q repeats do not re-quit")
        require(send(tap, 12, command, down: false), "Q up owned")

        require(!send(tap, 56, shiftCommand, type: .flagsChanged), "unrelated modifier changes pass")
        require(delegate.commits == 0, "Shift alone does not commit")
        require(!send(tap, 55, [], down: false, type: .flagsChanged), "Command release must pass to native app")
        require(delegate.commits == 1 && !delegate.isSwitcherSessionActive, "Command release commits")
        require(!send(tap, 13, command), "Command-W passes after session ends")
        require(!send(tap, 13, command, down: false), "W up passes after session ends")

        require(send(tap, 48, command), "subsequent session starts")
        require(send(tap, 53, [], down: true), "Escape cancels session")
        require(delegate.cancels == 1 && !delegate.isSwitcherSessionActive, "Escape ended session")
        require(send(tap, 53, [], down: false), "Escape up remains owned after cancellation")
        require(send(tap, 48, command, down: false), "Tab up remains owned after cancellation")

        // A key pressed before the session must receive its up, even when its repeats
        // are suppressed to prevent a background Command shortcut action.
        require(!send(tap, 13, command), "pre-session W down passes")
        require(send(tap, 48, command), "third session starts")
        require(send(tap, 13, command, repeatKey: true), "pre-held W repeat suppressed")
        require(!send(tap, 13, command, down: false), "pre-held W up must still pass")
        require(send(tap, 48, command, down: false), "third session Tab up consumed")
        require(!send(tap, 55, [], down: false, type: .flagsChanged), "release forwarded after third session")
        require(send(tap, 48, command), "session can restart after release")
        require(!send(tap, 0, [], type: .tapDisabledByTimeout), "tap disable callback does not consume event")
        require(delegate.cancels == 2 && !delegate.isSwitcherSessionActive,
                "timeout cancels active session rather than committing")
        require(!send(tap, 48, command, down: false), "failed recovery clears old key ownership")
        tap.stop()
        require(!tap.isRunning, "test does not install an event tap")
        testInterruptedInputContinuity()
        testQuickLaunchFailureOwnership()
        print("HotKeyEventRoutingTests passed")
    }

    static func testQuickLaunchFailureOwnership() {
        let suite = "commandtab.routing.quicklaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let assignments = QuickLaunchSettings(defaults: defaults)
        let service = RoutingQuickLaunchService()
        var feedback = 0
        let quickLaunch = QuickLaunchController(settings: assignments, applicationService: service) {
            feedback += 1
        }
        let delegate = RoutingDelegate()
        let tap = HotKeyEventTap(delegate: delegate) { key, flags, active, isRepeat in
            guard let slot = QuickLaunchShortcutPolicy.slot(
                forKeyCode: key, flags: flags, switcherActive: active
            ) else { return false }
            return quickLaunch.handle(slot: slot, isRepeat: isRepeat)
        }
        let command: CGEventFlags = [.maskCommand]
        let shifted: CGEventFlags = [.maskCommand, .maskShift]
        require(!send(tap, 18, command), "unconfigured Command-1 down passes through")
        require(!send(tap, 18, command, down: false), "unconfigured Command-1 up passes through")

        let assignment = QuickLaunchAssignment(bundleIdentifier: "com.example.Missing",
            applicationURL: URL(fileURLWithPath: "/nonexistent/QuickLaunch.app"), displayName: "Missing")
        assignments.setAssignment(assignment, for: 1)
        require(!send(tap, 18, shifted), "invalid modifiers do not capture Command-Shift-1")
        require(!send(tap, 18, shifted, down: false), "invalid modifiers preserve key up")
        require(send(tap, 18, command), "missing configured app owns Command-1 down")
        require(send(tap, 18, command, repeatKey: true), "missing app owns autorepeat")
        require(send(tap, 18, command, down: false), "missing app owns matching key up")
        require(feedback == 1 && service.launches == 0, "missing app beeps once without launching")

        service.resolvedURL = assignment.applicationURL
        require(send(tap, 18, command), "resolvable configured app owns Command-1")
        require(send(tap, 18, command, repeatKey: true), "resolvable app owns repeat")
        require(send(tap, 18, command, down: false), "resolvable app owns key up")
        require(service.launches == 1 && feedback == 1, "resolvable app launches once without failure")

        delegate.isSwitcherSessionActive = true
        require(send(tap, 18, command), "Switcher owns Command-1 while active")
        require(send(tap, 18, command, down: false), "Switcher owns matching key up")
        require(service.launches == 1 && feedback == 1, "Switcher blocks Quick Launch side effects")
        delegate.isSwitcherSessionActive = false

        require(send(tap, 18, command), "configured shortcut owns initial key down")
        assignments.clearAssignment(for: 1)
        require(send(tap, 18, command, repeatKey: true),
                "assignment clearing mid-press cannot leak a repeat")
        require(send(tap, 18, command, down: false),
                "assignment clearing mid-press cannot leak owned key up")
        require(!send(tap, 18, command), "cleared assignment passes on next fresh key down")
        require(!send(tap, 18, command, down: false), "cleared assignment passes matching up")
        require(service.launches == 2 && feedback == 1, "mid-press clearing triggers no extra launch or alert")
        tap.stop()
    }

    static func testInterruptedInputContinuity() {
        let command: CGEventFlags = [.maskCommand]
        let delegate = RoutingDelegate()
        var recoveryAttempts = 0
        let tap = HotKeyEventTap(delegate: delegate, reenableDisabledTap: { _ in
            recoveryAttempts += 1
            return true
        }) { _, _, _, _ in false }

        require(!send(tap, 0, type: .tapDisabledByTimeout), "inactive timeout forwards event")
        require(delegate.cancels == 0 && recoveryAttempts == 1, "inactive timeout preserves inactivity")
        require(send(tap, 48, command), "session owns Tab down")
        require(!send(tap, 0, type: .tapDisabledByTimeout), "active timeout forwards callback")
        require(!delegate.isSwitcherSessionActive && delegate.cancels == 1,
                "active timeout cancels exactly once")
        require(send(tap, 48, command, down: false), "recovered tap pairs owned Tab up")
        require(!send(tap, 55, [], down: false, type: .flagsChanged), "missed Command release passes")
        require(delegate.commits == 0, "lost Command release cannot commit a stale selection")
        require(!send(tap, 0, type: .tapDisabledByTimeout), "repeated timeout forwards event")
        require(delegate.cancels == 1, "repeated timeout cannot double-cancel")

        require(!send(tap, 13, command), "pre-session W down forwarded")
        require(send(tap, 48, command), "new session Tab down owned")
        require(!send(tap, 0, type: .tapDisabledByUserInput), "user-input interruption forwarded")
        require(delegate.cancels == 2, "user-input interruption cancels session")
        require(!send(tap, 13, command, down: false), "pre-forwarded W up is never swallowed")
        require(send(tap, 48, command, down: false), "owned Tab up stays paired")

        require(send(tap, 48, command), "another session Tab down owned")
        require(!send(tap, 0, type: .tapDisabledByTimeout), "another interruption forwarded")
        require(!send(tap, 48, [], down: true), "unowned new Tab down passes after timeout")
        require(!send(tap, 48, [], down: false), "unowned Tab up is not swallowed")
        require(delegate.cancels == 3 && delegate.commits == 0,
                "recovery never commits an interrupted session")
        require(recoveryAttempts == 5, "each notification gets one bounded re-enable attempt")
        tap.stop()

        let failingDelegate = RoutingDelegate()
        var failures = 0
        let failingTap = HotKeyEventTap(delegate: failingDelegate, reenableDisabledTap: { _ in
            failures += 1
            return false
        }) { _, _, _, _ in false }
        require(send(failingTap, 48, command), "failed-recovery session starts")
        require(!send(failingTap, 0, type: .tapDisabledByUserInput), "failed recovery forwards event")
        require(failingDelegate.cancels == 1 && !failingDelegate.isSwitcherSessionActive,
                "failed enable closes session")
        require(!send(failingTap, 48, command, down: false), "failed enable clears stale ownership")
        require(!send(failingTap, 55, [], down: false, type: .flagsChanged), "release forwarded after failure")
        require(failingDelegate.commits == 0 && failures == 1, "failed enable never selects")
        require(!failingTap.isRunning, "failed enable must not report running")
        failingTap.stop()
    }
}
