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
        require(send(tap, 48, command, down: false), "temporary tap disable preserves owed Tab up")
        tap.stop()
        require(!tap.isRunning, "test does not install an event tap")
        print("HotKeyEventRoutingTests passed")
    }
}
