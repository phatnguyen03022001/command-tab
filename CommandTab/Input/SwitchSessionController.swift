import AppKit

final class SwitchSessionController: HotKeyEventTapDelegate {
    private let settings: CommandTabSettings
    private let enumerator: WindowEnumerator
    private let focusController: WindowFocusController
    private let switcher: SwitcherPanelController

    private var windows: [WindowModel] = []
    private var snapshot: WindowSessionSnapshot?
    private var selectedIndex = 0
    private var sessionID = 0
    private var revealWorkItem: DispatchWorkItem?
    private(set) var isSwitcherSessionActive = false

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
    }

    func commandTabPressed(reverse: Bool) -> Bool {
        guard AccessibilityPermission.isTrusted() else {
            Log.input.error("Command-Tab ignored because Accessibility is unavailable")
            return false
        }
        if isSwitcherSessionActive {
            guard ensureSessionContextCurrent() else { return true }
            navigate(reverse: reverse)
            if !switcher.isVisible { revealNow() }
            return true
        }

        startSession(reverse: reverse)
        return true
    }

    func commandKeyReleased() -> Bool {
        guard isSwitcherSessionActive else { return false }
        commitSelection()
        return true
    }

    func cancelSwitcher() -> Bool {
        guard isSwitcherSessionActive else { return false }
        endSession(focusSelected: false)
        return true
    }

    func arrowPressed(reverse: Bool) -> Bool {
        guard isSwitcherSessionActive else { return false }
        guard ensureSessionContextCurrent() else { return true }
        navigate(reverse: reverse)
        if !switcher.isVisible { revealNow() }
        return true
    }

    func noteFrontmostApplicationChange() {
        // Public APIs do not expose reliable cross-app per-window MRU cheaply.
        // Snapshot z-order remains the deterministic ordering source for v1.
    }

    private func startSession(reverse: Bool) {
        sessionID += 1
        focusController.beginSession()
        guard let newSnapshot = enumerator.currentSnapshot(settings: settings) else {
            focusController.endSession()
            Log.windows.error("Authoritative Space/window snapshot unavailable; switch session cancelled")
            return
        }
        snapshot = newSnapshot
        windows = newSnapshot.windows
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
        switcher.show(windows: windows, selectedIndex: selectedIndex, sessionID: sessionID)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        Log.input.notice("Switcher rendered in \(elapsedMs, privacy: .public) ms")
    }

    private func commitSelection() {
        guard isSwitcherSessionActive else { return }
        revealWorkItem?.cancel()
        guard !windows.isEmpty else {
            endSession(focusSelected: false)
            return
        }

        selectedIndex = min(max(0, selectedIndex), windows.count - 1)
        let target = windows[selectedIndex]
        guard let snapshot, enumerator.validateForFocus(target, snapshot: snapshot) else {
            Log.windows.error("Selected window or Space context became stale; refusing focus")
            endSession(focusSelected: false)
            return
        }
        let permittedSpaceIDs = snapshot.visibleSpaceContext.permittedSpaceIDs(
            scope: snapshot.displayScope,
            activeDisplayID: snapshot.activeDisplayID
        )
        let focused = focusController.focus(target, permittedSpaceIDs: permittedSpaceIDs)
        if !focused {
            Log.focus.error("Focus operation failed for selected window")
        }
        endSession(focusSelected: false)
    }

    private func ensureSessionContextCurrent() -> Bool {
        guard let snapshot, enumerator.isSpaceContextCurrent(snapshot) else {
            Log.windows.error("Space context changed during active switch session; invalidating session")
            endSession(focusSelected: false)
            return false
        }
        return true
    }

    private func endSession(focusSelected: Bool) {
        revealWorkItem?.cancel()
        revealWorkItem = nil
        isSwitcherSessionActive = false
        focusController.endSession()
        snapshot = nil
        windows.removeAll(keepingCapacity: true)
        switcher.close()
    }
}
