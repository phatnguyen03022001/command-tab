import AppKit
import CoreGraphics
import Foundation

@main
struct SwitcherAdaptiveFitTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        _ = NSApplication.shared
        testMatrix()
        testCompressionOrder()
        testViewportVisibility()
        testPreferencesRemainPersistent()
        print("SwitcherAdaptiveFitTests passed")
    }

    static func testMatrix() {
        for width in [1280, 1440, 1728, 1920] {
            for count in [1, 4, 8, 12, 16, 24, 32] {
                for icon in [48, 72, 96] {
                    for spacing in [4, 10, 24] {
                        let result = SwitcherLayoutResolver.resolve(
                            itemCount: count,
                            visibleWidth: CGFloat(width),
                            preferredIconSize: CGFloat(icon),
                            preferredSpacing: CGFloat(spacing)
                        )
                        require(result.panelWidth <= CGFloat(width) * 0.86 + 0.001,
                                "panel must stay within 86% visible width: width=\(width) count=\(count) icon=\(icon) spacing=\(spacing)")
                        require(result.metrics.iconSize >= 48, "effective icon size must never drop below 48")
                        require(result.metrics.itemSpacing >= 4, "effective spacing must never drop below 4")
                        let maxZoomOverflow = result.metrics.selectionPodSize * 1.75 * 0.5 - result.metrics.itemWidth * 0.5
                        require(result.metrics.horizontalInset >= max(0, maxZoomOverflow),
                                "fixed horizontal inset must protect 175% selected visual without selection-time reflow")
                        if !result.overflow {
                            require(result.contentWidth <= result.maxPanelWidth + 0.001,
                                    "non-overflow content must fit bounded panel")
                        }
                    }
                }
            }
        }
    }

    static func testCompressionOrder() {
        let fits = SwitcherLayoutResolver.resolve(
            itemCount: 4, visibleWidth: 1280, preferredIconSize: 96, preferredSpacing: 24
        )
        require(fits.metrics.iconSize == 96 && fits.metrics.itemSpacing == 24,
                "preferences must be used exactly when they fit")

        let spacingOnly = SwitcherLayoutResolver.resolve(
            itemCount: 8, visibleWidth: 1280, preferredIconSize: 96, preferredSpacing: 24
        )
        require(spacingOnly.metrics.iconSize == 96, "spacing must compress before icon size")
        require(spacingOnly.metrics.itemSpacing < 24 && spacingOnly.metrics.itemSpacing >= 4,
                "spacing-only fit must reduce spacing within bounds")

        let iconCompressed = SwitcherLayoutResolver.resolve(
            itemCount: 12, visibleWidth: 1280, preferredIconSize: 96, preferredSpacing: 24
        )
        require(iconCompressed.metrics.itemSpacing == 4, "icon reduction may start only after spacing reaches 4")
        require(iconCompressed.metrics.iconSize < 96 && iconCompressed.metrics.iconSize >= 48,
                "icon must reduce coherently only after spacing compression")

        let overflow = SwitcherLayoutResolver.resolve(
            itemCount: 32, visibleWidth: 1280, preferredIconSize: 96, preferredSpacing: 24
        )
        require(overflow.overflow, "overflow must activate only after minimum spacing/icon cannot fit")
        require(overflow.metrics.iconSize == 48, "overflow must use minimum 48pt icon")
        require(overflow.metrics.itemSpacing == 4, "overflow must use minimum 4pt spacing")
    }

    static func testViewportVisibility() {
        let result = SwitcherLayoutResolver.resolve(
            itemCount: 32, visibleWidth: 1280, preferredIconSize: 96, preferredSpacing: 24
        )
        require(result.overflow, "viewport visibility test requires overflow")
        for scale in [1.15, 1.50, 1.75] as [CGFloat] {
            var offset: CGFloat = 0
            let margin = max(0, result.metrics.selectionPodSize * scale * 0.5 - result.metrics.itemWidth * 0.5)
            for index in [0, 15, 31, 8, 24] {
                offset = SwitcherViewportPolicy.offset(
                    selectedIndex: index,
                    itemCount: 32,
                    metrics: result.metrics,
                    viewportWidth: result.panelWidth,
                    contentWidth: result.contentWidth,
                    currentOffset: offset,
                    visualMargin: margin
                )
                let frame = SwitcherViewportPolicy.itemFrame(index: index, metrics: result.metrics)
                let leftAvailable = frame.minX - margin
                let rightAvailable = frame.maxX + margin
                require(leftAvailable >= 0, "zoomed selected visual must remain inside content bounds at left edge")
                require(rightAvailable <= result.contentWidth, "zoomed selected visual must remain inside content bounds at right edge")
                require(leftAvailable >= offset - 0.001, "zoomed selected item \(index) must not clip left")
                require(rightAvailable <= offset + result.panelWidth + 0.001, "zoomed selected item \(index) must not clip right")
            }
        }
    }
    static func testPreferencesRemainPersistent() {
        let suite = "commandtab.fit.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CommandTabSettings(defaults: defaults)
        settings.iconSize = 96
        settings.appSpacing = 24

        _ = SwitcherLayoutResolver.resolve(
            itemCount: 32,
            visibleWidth: 1280,
            preferredIconSize: CGFloat(settings.iconSize),
            preferredSpacing: CGFloat(settings.appSpacing)
        )

        require(settings.iconSize == 96, "runtime fit must not persist compressed icon size")
        require(settings.appSpacing == 24, "runtime fit must not persist compressed spacing")
        require(defaults.integer(forKey: "iconSize") == 96, "stored icon preference must remain unchanged")
        require(defaults.integer(forKey: "appSpacing") == 24, "stored spacing preference must remain unchanged")
    }
}
