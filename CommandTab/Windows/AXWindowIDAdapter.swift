import ApplicationServices
import Darwin

enum AXWindowIDAdapter {
    static let symbolName = "_AXUIElementGetWindow"
    private typealias Function = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<CGWindowID>
    ) -> AXError

    private static let function: Function? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, symbolName) else {
            return nil
        }
        return unsafeBitCast(symbol, to: Function.self)
    }()

    static var isAvailable: Bool { function != nil }

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        guard let function else { return nil }
        var windowID: CGWindowID = 0
        guard function(element, &windowID) == .success, windowID != 0 else {
            return nil
        }
        return windowID
    }
}
