import AppKit
import Foundation

struct SwitcherPresentationMetrics: Equatable {
    let iconSize: CGFloat
    let mode: SwitcherMode
    let previewWidth: CGFloat
    let previewHeight: CGFloat
    let selectionPodSize: CGFloat
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let panelHeight: CGFloat
    let itemSpacing: CGFloat
    let horizontalInset: CGFloat = 32
    let verticalInset: CGFloat = 10

    init(iconSize: CGFloat = 72, itemSpacing: CGFloat = 10, mode: SwitcherMode = .applications, thumbnailsAvailable: Bool = true) {
        let normalizedIcon = CGFloat(CommandTabSettings.normalizeIconSize(Int(iconSize.rounded())))
        let normalizedSpacing = CGFloat(CommandTabSettings.normalizeAppSpacing(Int(itemSpacing.rounded())))
        self.mode = mode
        self.iconSize = normalizedIcon
        self.itemSpacing = normalizedSpacing
        if mode == .windows && thumbnailsAvailable {
            let width = normalizedIcon + 84
            self.previewWidth = width
            self.previewHeight = round(width * 0.58)
            self.selectionPodSize = 36
            self.itemWidth = width + 12
            self.itemHeight = round(width * 0.58) + 76
            self.panelHeight = round(width * 0.58) + 96
        } else {
            self.previewWidth = 0
            self.previewHeight = 0
            self.selectionPodSize = normalizedIcon + 8
            self.itemWidth = normalizedIcon + (mode == .windows ? 48 : 24)
            self.itemHeight = normalizedIcon + 52
            self.panelHeight = normalizedIcon + 72
        }
    }

    func contentWidth(itemCount: Int) -> CGFloat {
        let count = max(1, itemCount)
        return CGFloat(count) * itemWidth
            + CGFloat(count - 1) * itemSpacing
            + horizontalInset * 2
    }
}
struct SwitcherLayoutResult: Equatable {
    let metrics: SwitcherPresentationMetrics
    let contentWidth: CGFloat
    let panelWidth: CGFloat
    let maxPanelWidth: CGFloat
    let overflow: Bool
}

enum SwitcherLayoutResolver {
    static func resolve(
        itemCount: Int,
        visibleWidth: CGFloat,
        preferredIconSize: CGFloat,
        preferredSpacing: CGFloat,
        mode: SwitcherMode = .applications,
        thumbnailsAvailable: Bool = true
    ) -> SwitcherLayoutResult {
        let maxPanelWidth = max(1, visibleWidth * 0.86)
        let preferredIcon = CGFloat(CommandTabSettings.normalizeIconSize(Int(preferredIconSize.rounded())))
        let preferredGap = CGFloat(CommandTabSettings.normalizeAppSpacing(Int(preferredSpacing.rounded())))

        func makeResult(icon: CGFloat, spacing: CGFloat, overflow: Bool = false) -> SwitcherLayoutResult {
            let metrics = SwitcherPresentationMetrics(iconSize: icon, itemSpacing: spacing, mode: mode, thumbnailsAvailable: thumbnailsAvailable)
            let contentWidth = metrics.contentWidth(itemCount: itemCount)
            return SwitcherLayoutResult(
                metrics: metrics,
                contentWidth: contentWidth,
                panelWidth: min(contentWidth, maxPanelWidth),
                maxPanelWidth: maxPanelWidth,
                overflow: overflow
            )
        }

        var result = makeResult(icon: preferredIcon, spacing: preferredGap)
        if result.contentWidth <= maxPanelWidth { return result }
        var spacing = preferredGap
        while spacing > 4 {
            spacing = max(4, spacing - 2)
            result = makeResult(icon: preferredIcon, spacing: spacing)
            if result.contentWidth <= maxPanelWidth { return result }
        }

        var icon = preferredIcon
        while icon > 48 {
            icon = max(48, icon - 4)
            result = makeResult(icon: icon, spacing: 4)
            if result.contentWidth <= maxPanelWidth { return result }
        }

        return makeResult(icon: 48, spacing: 4, overflow: true)
    }
}

enum SwitcherViewportPolicy {
    static func itemFrame(index: Int, metrics: SwitcherPresentationMetrics) -> CGRect {
        let safeIndex = max(0, index)
        let x = metrics.horizontalInset
            + CGFloat(safeIndex) * (metrics.itemWidth + metrics.itemSpacing)
        return CGRect(x: x, y: metrics.verticalInset, width: metrics.itemWidth, height: metrics.itemHeight)
    }

    static func offset(
        selectedIndex: Int,
        itemCount: Int,
        metrics: SwitcherPresentationMetrics,
        viewportWidth: CGFloat,
        contentWidth: CGFloat,
        currentOffset: CGFloat,
        visualMargin: CGFloat = 0
    ) -> CGFloat {
        let count = max(1, itemCount)
        let index = min(max(0, selectedIndex), count - 1)
        let selectedFrame = itemFrame(index: index, metrics: metrics)
        let maxOffset = max(0, contentWidth - viewportWidth)
        var offset = min(max(0, currentOffset), maxOffset)

        let margin = max(0, visualMargin)
        let visibleMinX = selectedFrame.minX - margin
        let visibleMaxX = selectedFrame.maxX + margin
        if visibleMinX < offset {
            offset = visibleMinX
        } else if visibleMaxX > offset + viewportWidth {
            offset = visibleMaxX - viewportWidth
        }
        return min(max(0, offset), maxOffset)
    }
}
