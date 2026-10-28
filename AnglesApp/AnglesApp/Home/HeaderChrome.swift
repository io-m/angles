import SwiftUI

/// Header metrics shared by Home, Profile, and author pages: one fixed compact row over
/// the pager, plus the reveal timing Profile's compact identity uses.
enum HeaderCollapse {
    static let horizontalPadding: CGFloat = 16
    static let headerHeight: CGFloat = 44
    static let headerTopPad: CGFloat = 6
    static let collapsedRevealDistance: CGFloat = 36
    static let collapseSlide: CGFloat = 10

    /// Base horizontal padding plus Duo side safe area (status / vertical tab column).
    static func contentLeadingPadding(safeLeading: CGFloat) -> CGFloat {
        horizontalPadding + max(0, safeLeading)
    }

    static func contentTrailingPadding(safeTrailing: CGFloat) -> CGFloat {
        horizontalPadding + max(0, safeTrailing)
    }

    static func overlayHeight(safeTop: CGFloat) -> CGFloat {
        safeTop + headerTopPad + headerHeight
    }

    static func bottomFadeHeight(safeBottom: CGFloat) -> CGFloat {
        safeBottom + 52
    }
}

/// Wide canvas: two columns once each would be at least `minColumnWidth`.
/// Phone portrait and the narrow Duo face stay under that width, so they stay one column.
/// Duo draws the tab bar in a side column but still reports `tabBarPlacement` as `bottomBar`,
/// so the page width is the switch.
enum HomeMasonryMetrics {
    static let minColumnWidth: CGFloat = 280
    static let columnGap: CGFloat = HeaderCollapse.horizontalPadding

    /// Page width at which two columns fit after the side gutters and the gap between them.
    static var minimumContentWidth: CGFloat {
        minColumnWidth * 2 + HeaderCollapse.horizontalPadding * 2 + columnGap
    }

    static func usesMasonry(contentWidth: CGFloat) -> Bool {
        contentWidth >= minimumContentWidth
    }
}

private struct HomeSideColumnKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Wide Duo: Home's style, filter, and settings live in the trailing side column.
    var homeSideColumn: Bool {
        get { self[HomeSideColumnKey.self] }
        set { self[HomeSideColumnKey.self] = newValue }
    }
}

/// Shared bottom fade over `AnglesCanvasBackground` — softer than a solid bar, aligned with the tab-area gradient.
enum CanvasEdgeFade {
    static func bottomStops(theme: ColorTokens.Theme) -> [Gradient.Stop] {
        [
            .init(color: .clear, location: 0),
            .init(color: theme.grey.opacity(0.58), location: 0.58),
            .init(color: theme.grey.opacity(0.86), location: 1),
        ]
    }
}
