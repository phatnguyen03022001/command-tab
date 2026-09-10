import CoreGraphics

struct WindowIdentityCandidate {
    let index: Int
    let exactWindowID: CGWindowID?
}

enum WindowIdentityResolution: Equatable {
    case exact(index: Int)
    case ambiguous
    case notFound
}

enum WindowIdentityMatcher {
    static func resolve(
        target: WindowModel,
        candidates: [WindowIdentityCandidate]
    ) -> WindowIdentityResolution {
        let exact = candidates.filter { $0.exactWindowID == target.id }
        if exact.count == 1 { return .exact(index: exact[0].index) }
        if exact.count > 1 { return .ambiguous }
        return .notFound
    }
}
