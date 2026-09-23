import SwiftUI

/// Header metrics shared by Home, Profile, and author pages: one fixed compact row over
/// the pager, plus the reveal timing Profile's compact identity uses.
enum HeaderCollapse {
    static let horizontalPadding: CGFloat = 16
    static let headerHeight: CGFloat = 44
    static let headerTopPad: CGFloat = 6
    static let collapsedRevealDistance: CGFloat = 36
    static let collapseSlide: CGFloat = 10

    static func overlayHeight(safeTop: CGFloat) -> CGFloat {
        safeTop + headerTopPad + headerHeight
    }

    static func bottomFadeHeight(safeBottom: CGFloat) -> CGFloat {
        safeBottom + 52
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
