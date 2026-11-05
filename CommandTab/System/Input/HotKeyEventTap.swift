import AppKit
import CoreGraphics

protocol HotKeyEventTapDelegate: AnyObject {
    var isSwitcherSessionActive: Bool { get }
    func commandTabPressed(reverse: Bool) -> Bool
    func commandKeyReleased() -> Bool
    func cancelSwitcher() -> Bool
    func arrowPressed(reverse: Bool) -> Bool
    func quitSelectedApplication() -> Bool
}

final class HotKeyEventTap {
    private weak var delegate: HotKeyEventTapDelegate?
    private let handleQuickLaunch: (UInt16, CGEventFlags, Bool, Bool) -> Bool
    private let reenableDisabledTap: (CFMachPort?) -> Bool
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    // Only pair keyUp with keyDown events actually consumed by this tap.
    private var ownedKeyUps = Set<UInt16>()
    private var forwardedKeyDowns = Set<UInt16>()

    var isRunning: Bool {
        guard let tap = eventTap, let source = runLoopSource else { return false }
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
            && CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes)
    }

    init(
        delegate: HotKeyEventTapDelegate,
        reenableDisabledTap: @escaping (CFMachPort?) -> Bool = { tap in
            guard let tap, CFMachPortIsValid(tap), AccessibilityPermission.isTrusted() else { return false }
            CGEvent.tapEnable(tap: tap, enable: true)
            return CGEvent.tapIsEnabled(tap: tap)
        },
        handleQuickLaunch: @escaping (UInt16, CGEventFlags, Bool, Bool) -> Bool
    ) {
        self.delegate = delegate
        self.handleQuickLaunch = handleQuickLaunch
        self.reenableDisabledTap = reenableDisabledTap
    }

    deinit { stop() }

    func start() -> Bool {
        if isRunning { return true }
        if eventTap != nil || runLoopSource != nil { stop() }
        guard Thread.isMainThread, AccessibilityPermission.isTrusted() else { return false }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: selfPointer
        ) else {
            Log.input.error("CGEvent tap creation failed")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            Log.input.error("CGEvent tap run-loop source creation failed")
            return false
        }
        let loop = CFRunLoopGetMain()
        CFRunLoopAddSource(loop, source, .commonModes)
        guard CFRunLoopContainsSource(loop, source, .commonModes) else {
            CFMachPortInvalidate(tap)
            CFRunLoopRemoveSource(loop, source, .commonModes)
            Log.input.error("CGEvent tap run-loop registration failed")
            return false
        }
        eventTap = tap
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            stop()
            Log.input.error("CGEvent tap could not be enabled")
            return false
        }
        return true
    }

    func stop() {
        // Stopping input delivery also invalidates any in-flight keyboard session.
        if delegate?.isSwitcherSessionActive == true { _ = delegate?.cancelSwitcher() }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        eventTap = nil
        runLoopSource = nil
        ownedKeyUps.removeAll()
        forwardedKeyDowns.removeAll()
    }

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Command release may be missed while the tap is disabled. Never commit
            // a selection after losing input continuity; keep owned ups if restored.
            if delegate?.isSwitcherSessionActive == true { _ = delegate?.cancelSwitcher() }
            if !reenableDisabledTap(eventTap) {
                Log.input.error("Event tap could not be re-enabled; stopping until permission recovery")
                stop()
            } else {
                Log.input.notice("Event tap re-enabled after interruption")
            }
            return Unmanaged.passUnretained(event)
        }

        guard let delegate else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let commandDown = flags.contains(.maskCommand)

        if type == .keyUp {
            if forwardedKeyDowns.remove(keyCode) != nil {
                ownedKeyUps.remove(keyCode)
                return Unmanaged.passUnretained(event)
            }
            return ownedKeyUps.remove(keyCode) != nil ? nil : Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            // Never hide modifier transitions from the foreground app. In particular, it
            // must see Command released even when that release commits a selection.
            if delegate.isSwitcherSessionActive && !commandDown {
                _ = delegate.commandKeyReleased()
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat && forwardedKeyDowns.contains(keyCode) {
            // The background app saw the original down: always deliver its eventual up.
            // Suppress Command repeats only while the Switcher owns the session.
            return delegate.isSwitcherSessionActive && commandDown ? nil : Unmanaged.passUnretained(event)
        }
        // A previous swallowed keyUp may have been lost if the tap was disabled.
        // An unowned new down must never cause its later up to be swallowed.
        ownedKeyUps.remove(keyCode)
        if keyCode == KeyCode.tab && commandDown {
            if delegate.commandTabPressed(reverse: flags.contains(.maskShift)) {
                ownedKeyUps.insert(keyCode)
                return nil
            }
            forwardedKeyDowns.insert(keyCode)
            return Unmanaged.passUnretained(event)
        }

        if handleQuickLaunch(keyCode, flags, delegate.isSwitcherSessionActive, isRepeat) {
            ownedKeyUps.insert(keyCode)
            return nil
        }

        guard delegate.isSwitcherSessionActive else {
            forwardedKeyDowns.insert(keyCode)
            return Unmanaged.passUnretained(event)
        }
        if keyCode == KeyCode.escape {
            if delegate.cancelSwitcher() {
                ownedKeyUps.insert(keyCode)
                return nil
            }
        } else if KeyCode.forwardArrows.contains(keyCode) || KeyCode.reverseArrows.contains(keyCode) {
            if delegate.arrowPressed(reverse: KeyCode.reverseArrows.contains(keyCode)) {
                ownedKeyUps.insert(keyCode)
                return nil
            }
        } else if keyCode == KeyCode.q && commandDown {
            if !isRepeat { _ = delegate.quitSelectedApplication() }
            ownedKeyUps.insert(keyCode)
            return nil
        }

        // The non-activating panel leaves the previous app as key recipient. During a
        // valid session it must not receive arbitrary Command shortcuts (W/S/Z/Return...).
        if commandDown {
            ownedKeyUps.insert(keyCode)
            return nil
        }
        forwardedKeyDowns.insert(keyCode)
        return Unmanaged.passUnretained(event)
    }
}

private enum KeyCode {
    static let q: UInt16 = 12
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
    static let forwardArrows: Set<UInt16> = [right, down]
    static let reverseArrows: Set<UInt16> = [left, up]
}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<HotKeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return owner.handle(proxy: proxy, type: type, event: event)
}
