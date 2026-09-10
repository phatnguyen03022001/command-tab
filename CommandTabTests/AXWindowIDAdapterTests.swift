import ApplicationServices

@main
struct AXWindowIDAdapterTests {
    static func main() {
        guard AXWindowIDAdapter.isAvailable else {
            fputs("FAIL: _AXUIElementGetWindow unavailable on this macOS build\n", stderr)
            exit(1)
        }
        print("AXWindowIDAdapterTests passed symbol=\(AXWindowIDAdapter.symbolName)")
    }
}
