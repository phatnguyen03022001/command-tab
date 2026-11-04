import CoreGraphics

enum SwitcherModePolicy {
    static func items(from windows: [WindowModel], mode: SwitcherMode) -> [WindowModel] {
        switch mode {
        case .applications:
            return ApplicationWindowDedupePolicy.representatives(from: windows)
        case .windows:
            return windows
        }
    }
}

enum ApplicationWindowDedupePolicy {
    static func representatives(from windows: [WindowModel]) -> [WindowModel] {
        var seenPIDs = Set<pid_t>()
        var representatives: [WindowModel] = []
        representatives.reserveCapacity(windows.count)

        for window in windows where seenPIDs.insert(window.pid).inserted {
            representatives.append(window)
        }
        return representatives
    }
}
