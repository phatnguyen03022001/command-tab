import AppKit
import CoreGraphics

@main
struct WindowThumbnailPresentationTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func find(_ id: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == id { return view }
        for child in view.subviews {
            if let match = find(id, in: child) { return match }
        }
        return nil
    }

    static func window(id: CGWindowID = 42) -> WindowModel {
        WindowModel(id: id, pid: getpid(), bundleIdentifier: "com.microsoft.VSCode",
                    appName: "Code", title: "README.md",
                    frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                    displayID: CGMainDisplayID(), spaceIDs: [3], iconKey: "com.microsoft.VSCode")
    }

    static func main() {
        _ = NSApplication.shared
        let icon = NSImage(size: NSSize(width: 64, height: 64))
        let windows = SwitcherItemView(window: window(), icon: icon, mode: .windows)
        guard let thumbnail = find("windowThumbnail", in: windows) as? NSImageView else {
            fputs("FAIL: Windows mode must create a dedicated window-thumbnail view\n", stderr)
            exit(1)
        }
        require(thumbnail.isHidden && windows.previewContainer.isHidden,
                "Before capture, empty thumbnail boxes must not be visible")
        let noCaptureMetrics = SwitcherPresentationMetrics(iconSize: 96, itemSpacing: 24, mode: .windows, thumbnailsAvailable: false)
        let noCapture = SwitcherItemView(window: window(), icon: icon, mode: .windows, metrics: noCaptureMetrics)
        require(find("windowPreviewContainer", in: noCapture)?.isHidden == true,
                "Windows mode without Screen Recording must not show meaningless empty squares")
        require(noCapture.metrics.itemHeight < windows.metrics.itemHeight,
                "Windows mode without thumbnails must not reserve blank thumbnail height")
        require(noCapture.imageView.image != nil, "Windows mode without thumbnails must still show the app icon")
        require(thumbnail.image == nil, "Before capture, show a safe placeholder rather than a stale image")
        let sample = NSImage(size: NSSize(width: 240, height: 150))
        windows.setThumbnail(sample, forWindowID: 42)
        require(thumbnail.image === sample && !thumbnail.isHidden && !windows.previewContainer.isHidden,
                "A captured matching window must reveal its real thumbnail")
        windows.configure(window: window(id: 43), icon: icon, mode: .windows)
        require(thumbnail.image == nil && windows.previewContainer.isHidden,
                "Reusing a tile must hide the previous window thumbnail")
        windows.setThumbnail(sample, forWindowID: 42)
        require(thumbnail.image == nil, "Late capture from old window must never leak into reused tile")
        let applications = SwitcherItemView(window: window(), icon: icon, mode: .applications)
        require(find("windowThumbnail", in: applications)?.isHidden == true,
                "Applications mode must retain classic icon-only layout")

        require(!WindowThumbnailPolicy.mayCapture(WindowModel(id: 44, pid: 1,
                bundleIdentifier: "com.apple.Photos", appName: "Photos", title: "", frame: .zero,
                displayID: nil, iconKey: "com.apple.Photos")), "Photos app content must never be captured")
        require(!WindowThumbnailPolicy.mayCapture(WindowModel(id: 45, pid: 1,
                bundleIdentifier: nil, appName: "Ảnh", title: "", frame: .zero,
                displayID: nil, iconKey: "pid:1")), "unknown bundle identity must not permit a thumbnail")
        require(WindowThumbnailPolicy.mayCapture(window()), "verified non-Photos app can show a thumbnail")
        let metrics = SwitcherLayoutResolver.resolve(
            itemCount: 6, visibleWidth: 1512,
            preferredIconSize: 96, preferredSpacing: 24, mode: .windows
        )
        require(metrics.metrics.itemWidth >= 160, "Window previews must be wide enough to recognize")
        require(metrics.metrics.itemHeight >= 150, "Window previews need vertical space")
        require(metrics.panelWidth <= 1512 * 0.86, "Window preview panel must fit display")
        print("WindowThumbnailPresentationTests passed")
    }
}
