import AppKit
import CoreGraphics

protocol HotKeyEventTapDelegate: AnyObject {
    var isSwitcherSessionActive: Bool { get }
    func commandTabPressed(reverse: Bool) -> Bool
    func commandKeyReleased() -> Bool
    func cancelSwitcher() -> Bool
    func arrowPressed(reverse: Bool) -> Bool
}

final class HotKeyEventTap {
    private weak var delegate: HotKeyEventTapDelegate?
    private let quickLaunchController: QuickLaunchController
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { eventTap != nil }

    init(delegate: HotKeyEventTapDelegate, quickLaunchController: QuickLaunchController) {
        self.delegate = delegate
        self.quickLaunchController = quickLaunchController
    }

    func start() -> Bool {
        guard AccessibilityPermission.isTrusted() else { return false }
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
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                Log.input.error("Event tap disabled; attempting safe re-enable")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let delegate else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let commandDown = flags.contains(.maskCommand)
        let shiftDown = flags.contains(.maskShift)

        if type == .keyDown, keyCode == KeyCode.tab, commandDown {
            return delegate.commandTabPressed(reverse: shiftDown) ? nil : Unmanaged.passUnretained(event)
        }

        if type == .keyDown,
           let slot = QuickLaunchShortcutPolicy.slot(
               forKeyCode: keyCode,
               flags: flags,
               switcherActive: delegate.isSwitcherSessionActive
           ) {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return quickLaunchController.handle(slot: slot, isRepeat: isRepeat)
                ? nil
                : Unmanaged.passUnretained(event)
        }

        if delegate.isSwitcherSessionActive {
            if type == .flagsChanged, !commandDown {
                return delegate.commandKeyReleased() ? nil : Unmanaged.passUnretained(event)
            }
            if type == .keyDown, keyCode == KeyCode.escape {
                return delegate.cancelSwitcher() ? nil : Unmanaged.passUnretained(event)
            }
            if type == .keyDown, KeyCode.forwardArrows.contains(keyCode) {
                return delegate.arrowPressed(reverse: false) ? nil : Unmanaged.passUnretained(event)
            }
            if type == .keyDown, KeyCode.reverseArrows.contains(keyCode) {
                return delegate.arrowPressed(reverse: true) ? nil : Unmanaged.passUnretained(event)
            }
            if type == .keyUp, KeyCode.consumedWhileActive.contains(keyCode) {
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

private enum KeyCode {
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
    static let forwardArrows: Set<UInt16> = [right, down]
    static let reverseArrows: Set<UInt16> = [left, up]
    static let consumedWhileActive: Set<UInt16> = [tab, escape, left, right, down, up]
}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<HotKeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return owner.handle(proxy: proxy, type: type, event: event)
}
