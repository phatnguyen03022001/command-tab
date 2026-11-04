import AppKit

final class SwitchSessionController: HotKeyEventTapDelegate {
    private let settings: CommandTabSettings
    private let enumerator: WindowEnumerator
    private let focusController: WindowFocusController
    private let switcher: SwitcherPanelController

    private var windows: [WindowModel] = []
    private var snapshot: WindowSessionSnapshot?
    private var sessionMode: SwitcherMode = .applications
    private var selectedIndex = 0
    private var sessionID = 0
    private var revealWorkItem: DispatchWorkItem?
    private var terminationObserver: NSObjectProtocol?
    private(set) var isSwitcherSessionActive = false

    var applicationTerminator: (pid_t) -> Bool = { pid in
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            return false
        }
        return app.terminate()
    }
    var finderWindowCloser: ((WindowModel) -> Bool)?

    init(
        settings: CommandTabSettings,
        enumerator: WindowEnumerator,
        focusController: WindowFocusController,
        switcher: SwitcherPanelController
    ) {
        self.settings = settings
        self.enumerator = enumerator
        self.focusController = focusController
        self.switcher = switcher

        self.terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.isSwitcherSessionActive else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.handleApplicationTerminated(pid: app.processIdentifier)
        }
    }

    deinit {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    func commandTabPressed(reverse: Bool) -> Bool {
        guard AccessibilityPermission.isTrusted() else {
            Log.input.error("Command-Tab ignored because Accessibility is unavailable")
            return false
        }
        if isSwitcherSessionActive {
            guard ensureSessionContextCurrent() else { return false }
            navigate(reverse: reverse)
            if !switcher.isVisible { revealNow() }
            return true
        }

        return startSession(reverse: reverse)
    }

    func commandKeyReleased() -> Bool {
        guard isSwitcherSessionActive else { return false }
        commitSelection()
        return true
    }

    func cancelSwitcher() -> Bool {
        guard isSwitcherSessionActive else { return false }
        endSession()
        return true
    }

    func arrowPressed(reverse: Bool) -> Bool {
        guard isSwitcherSessionActive else { return false }
        guard ensureSessionContextCurrent() else { return true }
        navigate(reverse: reverse)
        if !switcher.isVisible { revealNow() }
        return true
    }

    func quitSelectedApplication() -> Bool {
        guard isSwitcherSessionActive else { return false }
        guard ensureSessionContextCurrent() else { return true }
        guard let target = SwitchQuitPolicy.targetWindow(in: windows, selectedIndex: selectedIndex) else { return true }

        // A stale window/PID, unknown Space, or conflicting live identity cannot authorize a quit.
        guard let snapshot, enumerator.validateForFocus(target, snapshot: snapshot) else {
            Log.input.error("Selected quit target is no longer valid in its session context")
            return true
        }
        let liveApp = NSRunningApplication(processIdentifier: target.pid)
        if liveApp?.isTerminated == true {
            handleApplicationTerminated(pid: target.pid)
            return true
        }
        let permittedSpaceIDs = snapshot.visibleSpaceContext.permittedSpaceIDs(
            scope: snapshot.displayScope,
            activeDisplayID: snapshot.activeDisplayID
        )
        let result = SwitchQuitPolicy.execute(
            target: target,
            verifiedBundleIdentifier: liveApp?.bundleIdentifier,
            permittedSpaceIDs: permittedSpaceIDs,
            terminate: { [weak self] pid in
                guard let self,
                      let current = NSRunningApplication(processIdentifier: pid),
                      !current.isTerminated,
                      current.bundleIdentifier == target.bundleIdentifier else { return false }
                return self.applicationTerminator(pid)
            },
            closeFinderWindow: { [weak self] window in
                guard let self,
                      let current = NSRunningApplication(processIdentifier: window.pid),
                      !current.isTerminated,
                      current.bundleIdentifier == window.bundleIdentifier,
                      self.enumerator.validateForFocus(window, snapshot: snapshot) else { return false }
                return self.finderWindowCloser?(window)
                    ?? self.focusController.closeExactWindow(window, permittedSpaceIDs: permittedSpaceIDs)
            },
            finderCloseSucceeded: { [weak self] closedWindowID in
                self?.reconcileAfterFinderClose(closedWindowID: closedWindowID)
            }
        )

        if result.finderCloseAttempted {
            Log.input.notice(
                "Requested exact Finder window close wid=\(target.id) result=\(result.finderWindowClosed)"
            )
        } else {
            Log.input.notice(
                "Requested terminate for app=\(target.appName, privacy: .public) pid=\(target.pid) result=\(result.actionSucceeded)"
            )
        }
        if !switcher.isVisible { revealNow() }
        return true
    }

    static func hasValidSelection(_ windows: [WindowModel]) -> Bool {
        !windows.isEmpty && windows.allSatisfy { $0.id != 0 && $0.pid > 0 && !$0.spaceIDs.isEmpty }
    }

    @discardableResult
    private func startSession(reverse: Bool) -> Bool {
        sessionID += 1
        focusController.beginSession()
        let mode = settings.switcherMode
        guard let newSnapshot = enumerator.currentSnapshot(displayScope: settings.displayScope) else {
            focusController.endSession()
            Log.windows.error("Authoritative Space/window snapshot unavailable; switch session cancelled")
            return false
        }
        let newWindows = SwitcherModePolicy.items(from: newSnapshot.windows, mode: mode)
        guard Self.hasValidSelection(newWindows) else {
            focusController.endSession()
            Log.windows.error("No valid switch targets; passing Command-Tab to the system")
            return false
        }
        snapshot = newSnapshot
        sessionMode = mode
        windows = newWindows
        #if DEBUG
        for (displayID, spaceID) in newSnapshot.visibleSpaceContext.currentSpaceByDisplay.sorted(by: { $0.key < $1.key }) {
            Log.windows.debug("CURRENT: display=\(displayID) currentSpace=\(spaceID)")
        }
        for window in windows {
            let status = focusController.debugIdentityStatus(for: window)
            Log.windows.debug(
                "WINDOW: wid=\(window.id) pid=\(window.pid) app=\(window.appName, privacy: .public) onscreen=true display=\(String(describing: window.displayID), privacy: .public) spaces=\(String(describing: window.spaceIDs), privacy: .public) eligible=true ax=\(status, privacy: .public)"
            )
        }
        #endif
        Log.input.notice(
            "Window snapshot currentSpace=\(newSnapshot.currentSpaceLatencyMs, privacy: .public)ms membership=\(newSnapshot.membershipLatencyMs, privacy: .public)ms total=\(newSnapshot.totalLatencyMs, privacy: .public)ms"
        )
        isSwitcherSessionActive = true
        selectedIndex = nextIndexFromFront(reverse: reverse)
        scheduleReveal(for: sessionID)
        return isSwitcherSessionActive
    }

    private func nextIndexFromFront(reverse: Bool) -> Int {
        guard windows.count > 1 else { return 0 }
        return reverse ? windows.count - 1 : 1
    }

    private func navigate(reverse: Bool) {
        guard !windows.isEmpty else { return }
        if reverse {
            selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        } else {
            selectedIndex = (selectedIndex + 1) % windows.count
        }
        if switcher.isVisible {
            switcher.update(selectedIndex: selectedIndex, sessionID: sessionID)
        }
    }

    private func scheduleReveal(for id: Int) {
        revealWorkItem?.cancel()
        guard settings.revealDelay.seconds > 0 else {
            revealNow()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isSwitcherSessionActive, self.sessionID == id else { return }
            self.revealNow()
        }
        revealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.revealDelay.seconds, execute: workItem)
    }

    private func revealNow() {
        guard isSwitcherSessionActive else { return }
        guard ensureSessionContextCurrent() else { return }
        guard !windows.isEmpty else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        guard snapshot != nil else { return }
        switcher.show(
            windows: windows,
            selectedIndex: selectedIndex,
            sessionID: sessionID,
            mode: sessionMode
        )
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        Log.input.notice("Switcher rendered in \(elapsedMs, privacy: .public) ms")
    }

    private func commitSelection() {
        guard isSwitcherSessionActive else { return }
        revealWorkItem?.cancel()
        guard !windows.isEmpty else {
            endSession()
            return
        }

        selectedIndex = min(max(0, selectedIndex), windows.count - 1)
        let target = windows[selectedIndex]
        guard let snapshot, enumerator.validateForFocus(target, snapshot: snapshot) else {
            Log.windows.error("Selected window or Space context became stale; refusing focus")
            endSession()
            return
        }
        let permittedSpaceIDs = snapshot.visibleSpaceContext.permittedSpaceIDs(
            scope: snapshot.displayScope,
            activeDisplayID: snapshot.activeDisplayID
        )
        let focused = focusController.focus(
            target,
            permittedSpaceIDs: permittedSpaceIDs,
            spaceContextIsCurrent: { [enumerator] in enumerator.isSpaceContextCurrent(snapshot) }
        )
        if !focused {
            Log.focus.error("Focus operation failed for selected window")
        }
        endSession()
    }

    private func ensureSessionContextCurrent() -> Bool {
        guard let snapshot, enumerator.isSpaceContextCurrent(snapshot) else {
            Log.windows.error("Space context changed during active switch session; invalidating session")
            endSession()
            return false
        }
        return true
    }

    private func endSession() {
        revealWorkItem?.cancel()
        revealWorkItem = nil
        isSwitcherSessionActive = false
        focusController.endSession()
        snapshot = nil
        windows.removeAll(keepingCapacity: true)
        switcher.close()
    }

    private func reconcileAfterFinderClose(closedWindowID: CGWindowID) {
        let previousWindows = windows
        let previousSelectedIndex = selectedIndex
        let mode = settings.switcherMode
        guard let refreshedSnapshot = enumerator.currentSnapshot(displayScope: settings.displayScope) else {
            Log.windows.error("Finder window closed but bounded snapshot refresh failed; ending switch session")
            endSession()
            return
        }

        let result = SwitchQuitPolicy.reconcileAfterFinderClose(
            previousWindows: previousWindows,
            selectedIndex: previousSelectedIndex,
            closedWindowID: closedWindowID,
            refreshedWindows: SwitcherModePolicy.items(from: refreshedSnapshot.windows, mode: mode)
        )
        snapshot = refreshedSnapshot
        sessionMode = mode
        windows = result.remainingWindows
        selectedIndex = result.newSelectedIndex

        if result.shouldEndSession {
            endSession()
            return
        }
        if switcher.isVisible {
            switcher.show(
                windows: windows,
                selectedIndex: selectedIndex,
                sessionID: sessionID,
                mode: sessionMode
            )
        }
    }

    func handleApplicationTerminated(pid: pid_t) {
        guard isSwitcherSessionActive else { return }
        let result = SwitchQuitPolicy.reconcile(
            windows: windows,
            selectedIndex: selectedIndex,
            terminatedPID: pid
        )
        guard result.remainingWindows.count != windows.count else { return }

        windows = result.remainingWindows
        selectedIndex = result.newSelectedIndex

        if result.shouldEndSession {
            Log.input.notice("All switch targets terminated; closing session without focus")
            endSession()
            return
        }

        if switcher.isVisible, snapshot != nil {
            switcher.show(
                windows: windows,
                selectedIndex: selectedIndex,
                sessionID: sessionID,
                mode: sessionMode
            )
        }
    }
}
