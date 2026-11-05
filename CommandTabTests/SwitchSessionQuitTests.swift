import AppKit
import CoreGraphics
import Foundation

final class MockHotKeyEventTapDelegate: HotKeyEventTapDelegate {
    var isSwitcherSessionActive: Bool = false
    var commandTabCount = 0
    var lastReverse = false
    var handlesCommandTab = true
    var commandKeyReleasedCount = 0
    var cancelSwitcherCount = 0
    var arrowPressedCount = 0
    var quitRequestedCount = 0

    func commandTabPressed(reverse: Bool) -> Bool {
        commandTabCount += 1
        lastReverse = reverse
        return handlesCommandTab
    }

    func commandKeyReleased() -> Bool {
        commandKeyReleasedCount += 1
        return true
    }

    func cancelSwitcher() -> Bool {
        cancelSwitcherCount += 1
        return true
    }

    func arrowPressed(reverse: Bool) -> Bool {
        arrowPressedCount += 1
        lastReverse = reverse
        return true
    }

    func quitSelectedApplication() -> Bool {
        quitRequestedCount += 1
        return true
    }
}

@main
struct SwitchSessionQuitTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func makeWindow(
        id: CGWindowID,
        pid: pid_t,
        bundleIdentifier: String?,
        appName: String,
        title: String
    ) -> WindowModel {
        WindowModel(
            id: id,
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            title: title,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            displayID: CGMainDisplayID(),
            spaceIDs: [1],
            iconKey: bundleIdentifier ?? "pid:\(pid)"
        )
    }

    static func main() {
        _ = NSApplication.shared
        testEventTapBehavior()
        testSwitchQuitPolicy()
        testWindowSpaceMembership()
        testFocusEvidence()
        testSessionStartPreconditions()
        testExactAXCloseAction()
        testScreenChangeRecovery()
        testSingleEventTapConstraint()
        print("SwitchSessionQuitTests passed")
    }

    // Requirements 1, 2, 3, 4, 13, 14, 15, 16
    static func testEventTapBehavior() {
        let delegate = MockHotKeyEventTapDelegate()
        let qlSettings = QuickLaunchSettings(defaults: UserDefaults(suiteName: "test.ql.quit")!)
        let qlService = QuickLaunchApplicationService()
        let qlController = QuickLaunchController(settings: qlSettings, applicationService: qlService)
        let tap = HotKeyEventTap(delegate: delegate) { keyCode, flags, switcherActive, isRepeat in
            guard let slot = QuickLaunchShortcutPolicy.slot(
                forKeyCode: keyCode, flags: flags, switcherActive: switcherActive
            ) else { return false }
            return qlController.handle(slot: slot, isRepeat: isRepeat)
        }
        let fakeProxy = OpaquePointer(bitPattern: 1)!

        // 1. Q outside switcher session passes through normally
        delegate.isSwitcherSessionActive = false
        let qDownOutside = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)!
        qDownOutside.flags = [.maskCommand]
        let resOutside = tap.handle(proxy: fakeProxy, type: .keyDown, event: qDownOutside)
        require(resOutside != nil, "1. Q outside switcher session must pass through normally")
        require(delegate.quitRequestedCount == 0, "1. Q outside switcher session must not call quit")
        let qUpOutside = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: false)!
        require(tap.handle(proxy: fakeProxy, type: .keyUp, event: qUpOutside) != nil,
                "1. Q keyUp outside switcher session must pass through with its down")

        // 2. Q inside active switcher session is consumed
        delegate.isSwitcherSessionActive = true
        let qDownInside = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)!
        qDownInside.flags = [.maskCommand]
        let resInside = tap.handle(proxy: fakeProxy, type: .keyDown, event: qDownInside)
        require(resInside == nil, "2. Q inside active switcher session must be consumed (return nil)")
        require(delegate.quitRequestedCount == 1, "2. Q inside active switcher session must call quitSelectedApplication")

        // 3. Q keyUp consumed while active
        let qUpInside = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: false)!
        let resUp = tap.handle(proxy: fakeProxy, type: .keyUp, event: qUpInside)
        require(resUp == nil, "3. Q keyUp inside active switcher session must be consumed (return nil)")

        // 4. Q autorepeat does not issue repeated quit requests
        let qRepeat = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)!
        qRepeat.flags = [.maskCommand]
        qRepeat.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        let resRepeat = tap.handle(proxy: fakeProxy, type: .keyDown, event: qRepeat)
        require(resRepeat == nil, "4. Q autorepeat inside active session must be consumed")
        require(delegate.quitRequestedCount == 1, "4. Q autorepeat must NOT issue repeated quit requests")

        // 13. Escape unchanged
        let escEvent = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        let resEsc = tap.handle(proxy: fakeProxy, type: .keyDown, event: escEvent)
        require(resEsc == nil, "13. Escape must be consumed")
        require(delegate.cancelSwitcherCount == 1, "13. Escape must call cancelSwitcher")

        // 14. Command release commits and passes through to avoid stuck modifiers
        let releaseEvent = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false)!
        releaseEvent.flags = []
        let resRelease = tap.handle(proxy: fakeProxy, type: .flagsChanged, event: releaseEvent)
        require(resRelease != nil, "14. Command release must reach the background app")
        require(delegate.commandKeyReleasedCount == 1, "14. Command release must call commandKeyReleased")

        // 15. Tab / Shift-Tab behavior unchanged
        let tabEvent = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
        tabEvent.flags = [.maskCommand]
        let resTab = tap.handle(proxy: fakeProxy, type: .keyDown, event: tabEvent)
        require(resTab == nil, "15. Command-Tab must be consumed")
        require(delegate.commandTabCount == 1 && !delegate.lastReverse, "15. Command-Tab must advance forward")

        let shiftTabEvent = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
        shiftTabEvent.flags = [.maskCommand, .maskShift]
        let resShiftTab = tap.handle(proxy: fakeProxy, type: .keyDown, event: shiftTabEvent)
        require(resShiftTab == nil, "15. Command-Shift-Tab must be consumed")
        require(delegate.commandTabCount == 2 && delegate.lastReverse, "15. Command-Shift-Tab must advance reverse")

        delegate.isSwitcherSessionActive = false
        delegate.handlesCommandTab = false
        require(tap.handle(proxy: fakeProxy, type: .keyDown, event: tabEvent) != nil,
                "failed start must not swallow Command-Tab")
        require(tap.handle(proxy: fakeProxy, type: .keyDown, event: shiftTabEvent) != nil,
                "failed start must not swallow Shift-Command-Tab")
        delegate.handlesCommandTab = true
        require(!tap.isRunning, "unstarted event tap must never report running")
        tap.stop()
        tap.stop()
        require(!tap.isRunning, "stop is idempotent")

        // 16. Quick Launch unchanged
        let key1Event = CGEvent(keyboardEventSource: nil, virtualKey: 18, keyDown: true)!
        key1Event.flags = [.maskCommand]
        _ = tap.handle(proxy: fakeProxy, type: .keyDown, event: key1Event)
    }

    // Requirements 5, 6, 7, 8, 9, 10, 11, 12
    static func testSwitchQuitPolicy() {
        // 5. Normal selected app calls graceful terminator (is quittable)
        require(SwitchQuitPolicy.canQuit(bundleIdentifier: "com.microsoft.VSCode"),
                "5. Normal app must be eligible for quit")
        require(!SwitchQuitPolicy.isProtected(bundleIdentifier: "com.microsoft.VSCode"),
                "5. Normal app must not be protected")
        require(!SwitchQuitPolicy.canQuit(bundleIdentifier: nil), "unknown bundle ID must fail closed")
        require(!SwitchQuitPolicy.canQuit(bundleIdentifier: "  "), "empty bundle ID must fail closed")

        // 6 & 7. Finder selected is protected from process termination by bundle ID.
        require(!SwitchQuitPolicy.canQuit(bundleIdentifier: "com.apple.finder"),
                "6. Finder must NOT be eligible for process termination")
        require(SwitchQuitPolicy.isProtected(bundleIdentifier: "com.apple.finder"),
                "6. Finder must be marked protected")
        require(SwitchQuitPolicy.isProtected(bundleIdentifier: "COM.APPLE.FINDER"),
                "7. Finder check must be case-insensitive on bundle identifier")

        // 7. Non-Finder app with localized name "Finder" is still eligible
        let fakeFinderApp = makeWindow(id: 1, pid: 101, bundleIdentifier: "com.other.manager", appName: "Finder", title: "Window")
        require(SwitchQuitPolicy.canQuit(bundleIdentifier: fakeFinderApp.bundleIdentifier),
                "7. App named 'Finder' with non-Finder bundle ID must be eligible for quit")

        // 7. Finder with alternate localized name is still protected
        let renamedFinder = makeWindow(id: 2, pid: 657, bundleIdentifier: "com.apple.finder", appName: "Trình tìm kiếm", title: "Desktop")
        require(!SwitchQuitPolicy.canQuit(bundleIdentifier: renamedFinder.bundleIdentifier),
                "7. Finder with localized app name must still be protected by bundle ID")

        // 8. Windows mode Finder window also does NOT quit Finder
        let finderWin1 = makeWindow(id: 11, pid: 657, bundleIdentifier: "com.apple.finder", appName: "Finder", title: "Downloads")
        let finderWin2 = makeWindow(id: 12, pid: 657, bundleIdentifier: "com.apple.finder", appName: "Finder", title: "Documents")
        require(!SwitchQuitPolicy.canQuit(bundleIdentifier: finderWin1.bundleIdentifier),
                "8. Finder window in Windows mode must NOT quit Finder")
        require(!SwitchQuitPolicy.canQuit(bundleIdentifier: finderWin2.bundleIdentifier),
                "8. All Finder windows in Windows mode must NOT quit Finder")

        var terminatedPIDs: [pid_t] = []
        var closedWindowIDs: [CGWindowID] = []
        var reconciledFinderIDs: [CGWindowID] = []
        let finderSuccess = SwitchQuitPolicy.execute(
            target: finderWin2,
            verifiedBundleIdentifier: "com.apple.finder",
            permittedSpaceIDs: [1],
            terminate: { pid in terminatedPIDs.append(pid); return true },
            closeFinderWindow: { target in closedWindowIDs.append(target.id); return true },
            finderCloseSucceeded: { reconciledFinderIDs.append($0) }
        )
        require(terminatedPIDs.isEmpty, "Finder must never be sent application terminate")
        require(closedWindowIDs == [12], "Finder must route the exact selected CGWindowID to close")
        require(reconciledFinderIDs == [12], "successful Finder close must trigger exactly one bounded reconciliation")
        require(finderSuccess.finderWindowClosed, "successful exact Finder close must be reported")

        let finderFailure = SwitchQuitPolicy.execute(
            target: finderWin1,
            verifiedBundleIdentifier: "com.apple.finder",
            permittedSpaceIDs: [1],
            terminate: { pid in terminatedPIDs.append(pid); return true },
            closeFinderWindow: { _ in false },
            finderCloseSucceeded: { reconciledFinderIDs.append($0) }
        )
        require(terminatedPIDs.isEmpty, "non-closable Finder window must still never terminate Finder")
        require(reconciledFinderIDs == [12], "failed Finder close must perform no reconciliation")
        require(!finderFailure.finderWindowClosed, "non-closable Finder target must fail closed")

        // 9. Normal Windows mode still quits owning non-Finder app
        let codeWin1 = makeWindow(id: 21, pid: 2001, bundleIdentifier: "com.microsoft.VSCode", appName: "Code", title: "file1.swift")
        let codeWin2 = makeWindow(id: 22, pid: 2001, bundleIdentifier: "com.microsoft.VSCode", appName: "Code", title: "file2.swift")
        let chromeWin = makeWindow(id: 23, pid: 3001, bundleIdentifier: "com.google.Chrome", appName: "Chrome", title: "Google")
        let multiWindowList = [codeWin1, codeWin2, chromeWin]

        let target = SwitchQuitPolicy.targetWindow(in: multiWindowList, selectedIndex: 1)
        require(target?.pid == 2001, "9. Target window resolution must resolve owning app PID")
        require(SwitchQuitPolicy.canQuit(bundleIdentifier: target?.bundleIdentifier),
                "9. Normal Windows mode window must be eligible for quit")
        terminatedPIDs.removeAll()
        closedWindowIDs.removeAll()
        let ordinaryResult = SwitchQuitPolicy.execute(
            target: target!,
            verifiedBundleIdentifier: "com.microsoft.VSCode",
            permittedSpaceIDs: [1],
            terminate: { pid in terminatedPIDs.append(pid); return true },
            closeFinderWindow: { window in closedWindowIDs.append(window.id); return true }
        )
        require(terminatedPIDs == [2001], "ordinary app must use graceful application terminate")
        require(closedWindowIDs.isEmpty, "ordinary app must never use Finder exact-window close path")
        require(ordinaryResult.applicationTerminateRequested, "ordinary app termination request must be reported")

        // Unknown, missing, conflicting and stale identities may not authorize a callback.
        let unknown = makeWindow(id: 24, pid: 2002, bundleIdentifier: nil, appName: "Unknown", title: "")
        let rejected: [(WindowModel, String?)] = [
            (unknown, nil),
            (unknown, "com.microsoft.VSCode"),
            (codeWin1, nil),
            (codeWin1, "com.apple.finder"),
            (finderWin1, "com.microsoft.VSCode"),
            (makeWindow(id: 0, pid: 2001, bundleIdentifier: "com.microsoft.VSCode", appName: "Code", title: ""), "com.microsoft.VSCode"),
            (makeWindow(id: 42, pid: 0, bundleIdentifier: "com.microsoft.VSCode", appName: "Code", title: ""), "com.microsoft.VSCode")
        ]
        terminatedPIDs.removeAll()
        closedWindowIDs.removeAll()
        for (badTarget, verifiedID) in rejected {
            let result = SwitchQuitPolicy.execute(
                target: badTarget,
                verifiedBundleIdentifier: verifiedID,
                permittedSpaceIDs: [1],
                terminate: { terminatedPIDs.append($0); return true },
                closeFinderWindow: { closedWindowIDs.append($0.id); return true }
            )
            require(!result.applicationTerminateRequested && !result.finderCloseAttempted && !result.actionSucceeded,
                    "unverified identity must never invoke a destructive operation")
        }
        require(terminatedPIDs.isEmpty && closedWindowIDs.isEmpty,
                "unknown/contradictory identities never reach termination or Finder close")
        let staleSpace = SwitchQuitPolicy.execute(
            target: finderWin1, verifiedBundleIdentifier: "com.apple.finder",
            permittedSpaceIDs: [2],
            terminate: { terminatedPIDs.append($0); return true },
            closeFinderWindow: { closedWindowIDs.append($0.id); return true }
        )
        require(!staleSpace.actionSucceeded && !staleSpace.finderCloseAttempted,
                "Finder window outside permitted Space cannot be closed")
        require(terminatedPIDs.isEmpty && closedWindowIDs.isEmpty,
                "stale Space never invokes a destructive operation")
        require(SwitchQuitPolicy.targetWindow(in: multiWindowList, selectedIndex: -1) == nil,
                "negative destructive target selection must fail closed")
        require(SwitchQuitPolicy.targetWindow(in: multiWindowList, selectedIndex: 99) == nil,
                "out-of-bounds destructive target selection must fail closed")

        // Finder close reconciliation uses exactly one refreshed snapshot and never another Finder window by ID.
        let refreshedFinder = makeWindow(id: 13, pid: 657, bundleIdentifier: "com.apple.finder", appName: "Finder", title: "Other")
        let afterFinderClose = SwitchQuitPolicy.reconcileAfterFinderClose(
            previousWindows: [codeWin1, finderWin2, chromeWin],
            selectedIndex: 1,
            closedWindowID: finderWin2.id,
            refreshedWindows: [codeWin1, refreshedFinder, chromeWin]
        )
        require(afterFinderClose.remainingWindows.map(\.id) == [21, 13, 23],
                "Finder reconciliation must trust one refreshed canonical window list")
        require(afterFinderClose.newSelectedIndex == 1,
                "selection must remain valid at the closed representative position")
        require(afterFinderClose.remainingWindows[1].id == 13,
                "another eligible Finder window may become the representative without touching a different window directly")
        require(!afterFinderClose.shouldEndSession, "session must remain active while eligible targets remain")

        // 10. Actual non-Finder termination reconciles items (removes all windows of that PID)
        let reconcileMulti = SwitchQuitPolicy.reconcile(windows: multiWindowList, selectedIndex: 1, terminatedPID: 2001)
        require(reconcileMulti.remainingWindows.map(\.id) == [23],
                "10. Termination must remove all windows belonging to terminated PID")
        require(reconcileMulti.newSelectedIndex == 0,
                "10. Selection must adjust to remaining window at index 0")
        require(!reconcileMulti.shouldEndSession,
                "10. Session must remain active when other apps remain")

        // 10b. Reconciliation retains selection when currently selected item is NOT the terminated PID
        let threeAppList = [
            makeWindow(id: 31, pid: 4001, bundleIdentifier: "com.test.a", appName: "A", title: "A"),
            makeWindow(id: 32, pid: 4002, bundleIdentifier: "com.test.b", appName: "B", title: "B"),
            makeWindow(id: 33, pid: 4003, bundleIdentifier: "com.test.c", appName: "C", title: "C")
        ]
        // Currently selected: C at index 2. Terminated: A at PID 4001.
        let reconcileOther = SwitchQuitPolicy.reconcile(windows: threeAppList, selectedIndex: 2, terminatedPID: 4001)
        require(reconcileOther.remainingWindows.map(\.pid) == [4002, 4003], "PID 4001 must be removed")
        require(reconcileOther.newSelectedIndex == 1, "Selection must follow PID 4003 to new index 1")
        require(reconcileOther.remainingWindows[reconcileOther.newSelectedIndex].pid == 4003, "C must remain selected")

        // 11. Failed / delayed non-Finder quit remains represented
        // If PID is never terminated, list is untouched
        let noTermResult = SwitchQuitPolicy.reconcile(windows: threeAppList, selectedIndex: 1, terminatedPID: 9999)
        require(noTermResult.remainingWindows.count == 3,
                "11. Unterminated PID leaves window list intact")
        require(noTermResult.newSelectedIndex == 1,
                "11. Selection remains intact when no termination occurs")

        // 12. Last-item behavior remains safe
        let soloList = [makeWindow(id: 41, pid: 5001, bundleIdentifier: "com.test.solo", appName: "Solo", title: "Solo")]
        let soloReconcile = SwitchQuitPolicy.reconcile(windows: soloList, selectedIndex: 0, terminatedPID: 5001)
        require(soloReconcile.remainingWindows.isEmpty, "12. Last remaining item termination results in empty list")
        require(soloReconcile.shouldEndSession, "12. Last item termination must signal shouldEndSession = true")
    }

    static func testWindowSpaceMembership() {
        let permitted: Set<UInt64> = [4, 7]
        require(!WindowFocusController.allowsSpaceMembership(nil, permittedSpaceIDs: permitted),
                "unknown Space membership must fail closed")
        require(!WindowFocusController.allowsSpaceMembership([], permittedSpaceIDs: permitted),
                "empty Space membership must fail closed")
        require(!WindowFocusController.allowsSpaceMembership([1, 2], permittedSpaceIDs: permitted),
                "windows outside the permitted Space must never be closed")
        require(WindowFocusController.allowsSpaceMembership([2, 7], permittedSpaceIDs: permitted),
                "exact window with permitted Space membership may proceed to AX validation")
        require(!WindowFocusController.allowsSpaceMembership([7], permittedSpaceIDs: []),
                "empty permitted Space context must fail closed")
    }

    static func testSessionStartPreconditions() {
        let valid = makeWindow(id: 500, pid: 400, bundleIdentifier: "org.example.app", appName: "App", title: "")
        require(!SwitchSessionController.hasValidSelection([]), "empty snapshot cannot start a session")
        require(SwitchSessionController.hasValidSelection([valid]), "valid selection starts a session")
        let invalidID = makeWindow(id: 0, pid: 400, bundleIdentifier: "org.example.app", appName: "App", title: "")
        require(!SwitchSessionController.hasValidSelection([invalidID]), "invalid window cannot start a session")
        let invalidPID = makeWindow(id: 501, pid: 0, bundleIdentifier: "org.example.app", appName: "App", title: "")
        require(!SwitchSessionController.hasValidSelection([invalidPID]), "invalid PID cannot start a session")
        let unknownSpace = WindowModel(
            id: 502, pid: 400, bundleIdentifier: "org.example.app", appName: "App", title: "",
            frame: .zero, displayID: nil, spaceIDs: [], iconKey: "org.example.app"
        )
        require(!SwitchSessionController.hasValidSelection([unknownSpace]), "unknown Space cannot start a session")
    }

    static func testFocusEvidence() {
        func evidence(_ observed: CGWindowID?, activated: Bool, axAccepted: Bool,
                      visible: Bool = true, space: Bool = true,
                      context: Bool = true) -> ExactWindowFocusEvidence {
            ExactWindowFocusEvidence(
                targetWindowID: 500, focusedWindowID: observed, activationAccepted: activated,
                axFocusAccepted: axAccepted, targetStillVisible: visible, spaceStillPermitted: space,
                sessionContextStillCurrent: context
            )
        }
        require(!evidence(nil, activated: true, axAccepted: false).isConfirmed, "activation alone must fail")
        require(!evidence(nil, activated: true, axAccepted: true).isConfirmed, "AX accepted without proof fails")
        require(!evidence(501, activated: true, axAccepted: true).isConfirmed, "wrong AX window fails")
        require(!evidence(500, activated: true, axAccepted: true, visible: false).isConfirmed, "stale window fails")
        require(!evidence(500, activated: true, axAccepted: true, space: false).isConfirmed, "stale Space fails")
        require(!evidence(500, activated: true, axAccepted: true, context: false).isConfirmed,
                "changed session display-to-Space mapping fails")
        require(evidence(500, activated: true, axAccepted: true).isConfirmed, "exact verified window succeeds")
        require(evidence(500, activated: false, axAccepted: true).isConfirmed, "AX verified focus independent of activation")
        require(!evidence(nil, activated: false, axAccepted: true).isConfirmed, "unverifiable focus fails")
    }

    static func testExactAXCloseAction() {
        let exactWindow = AXUIElementCreateSystemWide()
        let closeButton = AXUIElementCreateSystemWide()
        var pressCount = 0

        let missing = ExactAXWindowCloseAction.perform(
            on: exactWindow,
            closeButton: { _ in nil },
            supportedActions: { _ in [kAXPressAction as String] },
            press: { _ in pressCount += 1; return .success }
        )
        require(missing == .missingCloseButton && pressCount == 0,
                "missing exact-window close button must fail closed without press")

        let unsupported = ExactAXWindowCloseAction.perform(
            on: exactWindow,
            closeButton: { _ in closeButton },
            supportedActions: { _ in [kAXRaiseAction as String] },
            press: { _ in pressCount += 1; return .success }
        )
        require(unsupported == .unsupportedPressAction && pressCount == 0,
                "close button without AXPress must fail closed")

        let failed = ExactAXWindowCloseAction.perform(
            on: exactWindow,
            closeButton: { _ in closeButton },
            supportedActions: { _ in [kAXPressAction as String] },
            press: { button in
                require(CFEqual(button, closeButton), "AXPress must target the exact window's returned close button")
                pressCount += 1
                return .cannotComplete
            }
        )
        require(failed == .pressFailed && pressCount == 1,
                "failed AXPress must fail closed after exactly one press attempt")

        let succeeded = ExactAXWindowCloseAction.perform(
            on: exactWindow,
            closeButton: { window in
                require(CFEqual(window, exactWindow), "close-button lookup must originate from exact resolved AX window")
                return closeButton
            },
            supportedActions: { _ in [kAXPressAction as String] },
            press: { _ in pressCount += 1; return .success }
        )
        require(succeeded == .success && pressCount == 2,
                "supported exact close button must succeed with one AXPress")
    }

    static func testScreenChangeRecovery() {
        let suite = "commandtab.display.recovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CommandTabSettings(defaults: defaults)
        let displayID = CGMainDisplayID()
        let window = makeWindow(id: 901, pid: getpid(), bundleIdentifier: "test.commandtab.display",
                                appName: "Synthetic", title: "Synthetic")
        let context = VisibleSpaceContext(currentSpaceByDisplay: [displayID: 1])
        let snapshot = WindowSessionSnapshot(
            visibleSpaceContext: context, displayScope: .allVisible, activeDisplayID: nil,
            windows: [window], currentSpaceLatencyMs: 0, membershipLatencyMs: 0, totalLatencyMs: 0
        )
        let enumerator = WindowEnumerator()
        let focus = WindowFocusController()
        let switcher = SwitcherPanelController(settings: settings)
        var controller: SwitchSessionController? = SwitchSessionController(
            settings: settings, enumerator: enumerator, focusController: focus, switcher: switcher
        )
        controller!.isAccessibilityTrusted = { true } // No changes to real system permissions.
        controller!.snapshotProvider = { _ in snapshot } // No live window enumeration.
        var spaceMapping = context.currentSpaceByDisplay
        var targetIsValid = true
        var validationCalls = 0
        controller!.contextIsCurrent = { $0.visibleSpaceContext.matches(currentSpaceByDisplay: spaceMapping) }
        controller!.selectionIsCurrent = { target, _ in
            validationCalls += 1
            return target.id == window.id && targetIsValid
        }
        let postChange = {
            NotificationCenter.default.post(
                name: NSApplication.didChangeScreenParametersNotification, object: NSApp
            )
        }

        postChange()
        require(validationCalls == 0, "inactive display change must not validate or create UI")
        settings.revealDelay = .ms150
        require(controller!.commandTabPressed(reverse: false), "synthetic session starts")
        require(!switcher.isVisible, "session starts before delayed reveal")
        targetIsValid = false
        postChange()
        postChange()
        require(!controller!.isSwitcherSessionActive && !switcher.isVisible,
                "invalid target cancels pre-reveal session on repeated notifications")
        require(!controller!.commandKeyReleased(), "invalid session cannot commit on Command release")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        require(!switcher.isVisible, "cancelled delayed reveal must never resurrect panel")

        targetIsValid = true
        require(controller!.commandTabPressed(reverse: false), "new delayed session starts")
        postChange()
        require(controller!.isSwitcherSessionActive && !switcher.isVisible,
                "unchanged display and Space identity preserve delayed session")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        require(switcher.isVisible, "valid delayed reveal uses current panel geometry")
        _ = controller!.cancelSwitcher()

        settings.revealDelay = .instant
        require(controller!.commandTabPressed(reverse: false), "visible synthetic session starts")
        require(switcher.isVisible, "instant reveal creates synthetic panel")
        guard let panel = Mirror(reflecting: switcher).children.first(where: { $0.label == "panel" })?.value as? NSPanel else {
            require(false, "synthetic panel must exist")
            return
        }
        panel.setFrameOrigin(NSPoint(x: 100_000, y: 100_000))
        postChange()
        require(controller!.isSwitcherSessionActive && switcher.isVisible,
                "geometry-only change preserves valid session")
        require(NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }),
                "geometry-only change repositions panel onto available screen")
        postChange()
        require(controller!.isSwitcherSessionActive, "repeated valid notifications do not cancel")
        _ = controller!.cancelSwitcher()

        require(controller!.commandTabPressed(reverse: false), "session before display identity change")
        spaceMapping = [displayID: 2]
        postChange()
        require(!controller!.isSwitcherSessionActive && !switcher.isVisible,
                "Space change cancels stale session and dismisses overlay")
        require(!controller!.commandKeyReleased(), "Space change cannot commit")
        spaceMapping = context.currentSpaceByDisplay
        require(controller!.commandTabPressed(reverse: false), "session before display identity change starts")
        spaceMapping = [CGDirectDisplayID(4_000_000_000): 1]
        postChange()
        require(!controller!.isSwitcherSessionActive, "display identity change cancels session")
        spaceMapping = context.currentSpaceByDisplay

        // A disconnected presentation display must cancel even if injected Space probes
        // report a nominally matching mapping; no physical monitor is accessed.
        let missingDisplay = CGDirectDisplayID(4_000_000_000)
        let missingWindow = WindowModel(
            id: 902, pid: getpid(), bundleIdentifier: "test.commandtab.display", appName: "Synthetic",
            title: "Detached", frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            displayID: missingDisplay, spaceIDs: [1], iconKey: "test.commandtab.display"
        )
        let missingSnapshot = WindowSessionSnapshot(
            visibleSpaceContext: context, displayScope: .allVisible, activeDisplayID: nil,
            windows: [missingWindow], currentSpaceLatencyMs: 0, membershipLatencyMs: 0, totalLatencyMs: 0
        )
        controller!.snapshotProvider = { _ in missingSnapshot }
        controller!.selectionIsCurrent = { _, _ in true }
        require(controller!.commandTabPressed(reverse: false), "missing display synthetic session starts")
        postChange()
        require(!controller!.isSwitcherSessionActive && !switcher.isVisible,
                "disconnected context display cancels instead of stranding panel")

        weak var weakController = controller
        controller = nil
        require(weakController == nil, "screen observer must not retain controller")
        postChange() // Deallocated observer must not invoke its former owner.
    }

    // Requirement 17: One CGEvent tap only
    static func testSingleEventTapConstraint() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let commandTabDir = root.appendingPathComponent("CommandTab")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        task.arguments = ["-R", "-h", "CGEvent\\.tapCreate", commandTabDir.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let tapCount = output.split(separator: "\n").count
        require(tapCount == 1, "17. Exactly ONE CGEvent tap must be created across production codebase")
    }
}
