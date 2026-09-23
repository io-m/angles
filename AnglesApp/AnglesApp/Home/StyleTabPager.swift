import Observation
import SwiftUI

enum StyleTabMetrics {
    static let chipSpring = Animation.spring(response: 0.36, dampingFraction: 0.78)
    static let chromeBottomInset: CGFloat = 8
    static let tabBarHeight = ReframeCardMetrics.chipSize + 12 + chromeBottomInset

    static func pageTint(isDark: Bool) -> CGFloat {
        isDark ? 0.07 : 0.045
    }
}

protocol StyleTabRepresentable: Hashable, CaseIterable {
    var title: String { get }
    var chipTitle: String { get }
    var systemImage: String { get }
    var matchingStyle: Style? { get }
    func symbolColor(ink: Color) -> Color
    var headerWashInk: Color { get }
    var usesNeutralChip: Bool { get }
}

extension ProfileGridFilter: StyleTabRepresentable {
    var usesNeutralChip: Bool { self == .favorites }
}

extension HomeFeedTab: StyleTabRepresentable {
    var usesNeutralChip: Bool { self == .all }
}

struct StyleTabPagerSnapshot: Equatable {
    var offset: CGFloat = 0
    var width: CGFloat = 1
    var fromIndex = 0
    var toIndex = 0
    var pageProgress: CGFloat = 0
}

@MainActor
@Observable
final class StyleTabPagerState<T: StyleTabRepresentable> {
    private(set) var snapshot = StyleTabPagerSnapshot()
    private(set) var requestedTab: T
    private(set) var requestSerial = 0
    private(set) var requestAnimated = true

    private let tabs: [T]

    init(initialTab: T) {
        self.requestedTab = initialTab
        self.tabs = Array(T.allCases)
    }

    var pageCount: Int { tabs.count }

    func update(offset rawOffset: CGFloat, width rawWidth: CGFloat) {
        guard rawOffset.isFinite, rawWidth.isFinite, rawWidth > 0 else {
            return
        }

        let maximumOffset = rawWidth * CGFloat(pageCount - 1)
        let newOffset = min(maximumOffset, max(0, rawOffset))
        guard abs(snapshot.offset - newOffset) > 0.5
                || abs(snapshot.width - rawWidth) > 0.5
        else {
            return
        }

        let position = newOffset / rawWidth
        let lowerIndex = min(pageCount - 1, max(0, Int(floor(position))))
        let upperIndex = min(pageCount - 1, lowerIndex + 1)
        let progress = upperIndex == lowerIndex
            ? 0
            : min(1, max(0, position - CGFloat(lowerIndex)))

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            snapshot = StyleTabPagerSnapshot(
                offset: newOffset,
                width: rawWidth,
                fromIndex: lowerIndex,
                toIndex: progress < 0.0001 ? lowerIndex : upperIndex,
                pageProgress: progress < 0.0001 ? 0 : progress
            )
        }
    }

    func requestPage(_ tab: T, animated: Bool = true) {
        requestAnimated = animated
        requestedTab = tab
        requestSerial &+= 1
    }

    func normalizeAtEndpoint() -> T? {
        guard snapshot.width > 0 else {
            return nil
        }

        let index = min(
            pageCount - 1,
            max(0, Int((snapshot.offset / snapshot.width).rounded()))
        )
        guard abs(snapshot.offset - (CGFloat(index) * snapshot.width)) <= 1
        else {
            return nil
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            snapshot = StyleTabPagerSnapshot(
                offset: CGFloat(index) * snapshot.width,
                width: snapshot.width,
                fromIndex: index,
                toIndex: index,
                pageProgress: 0
            )
        }
        return tabs[index]
    }

    func expansion(at index: Int) -> CGFloat {
        guard index >= 0, index < pageCount else {
            return 0
        }
        if snapshot.fromIndex == snapshot.toIndex {
            return index == snapshot.fromIndex ? 1 : 0
        }
        if index == snapshot.fromIndex {
            return 1 - snapshot.pageProgress
        }
        if index == snapshot.toIndex {
            return snapshot.pageProgress
        }
        return 0
    }
}

private struct StyleTabPagerGeometry: Equatable {
    let offset: CGFloat
    let width: CGFloat
}

private struct StyleTabPagerOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

struct StyleTabPagerOffsetProbe: View {
    let space: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: StyleTabPagerOffsetKey.self,
                value: proxy.frame(in: .named(space)).minX
            )
        }
    }
}

struct StyleTabPagerTracking<T: StyleTabRepresentable>: ViewModifier {
    let state: StyleTabPagerState<T>
    let fallbackWidth: CGFloat
    let onReachPage: (T) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: StyleTabPagerGeometry.self) { geometry in
                    StyleTabPagerGeometry(
                        offset: max(0, geometry.contentOffset.x),
                        width: geometry.containerSize.width
                    )
                } action: { _, newValue in
                    state.update(offset: newValue.offset, width: newValue.width)
                }
                .onScrollPhaseChange { _, newPhase in
                    guard newPhase == .idle else {
                        return
                    }
                    commitEndpoint()
                }
        } else {
            content
                .onPreferenceChange(StyleTabPagerOffsetKey.self) { minX in
                    guard let minX else {
                        return
                    }
                    state.update(offset: max(0, -minX), width: fallbackWidth)
                    commitEndpoint()
                }
        }
    }

    private func commitEndpoint() {
        guard let tab = state.normalizeAtEndpoint() else {
            return
        }
        onReachPage(tab)
    }
}

struct StyleTabBar<T: StyleTabRepresentable>: View {
    let pagerState: StyleTabPagerState<T>
    let settledSelection: T
    var includesTrailingSpacer = true
    var padded = true
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: ReframeCardMetrics.chipSpacing) {
            ForEach(Array(T.allCases.enumerated()), id: \.element) { index, tab in
                StyleTabChip(
                    tab: tab,
                    expansion: pagerState.expansion(at: index),
                    isSettledSelection: settledSelection == tab,
                    onSelect: { onSelect(tab) }
                )
            }

            if includesTrailingSpacer {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, padded ? HeaderCollapse.horizontalPadding : 0)
        .padding(.top, padded ? 6 : 0)
        .padding(.bottom, padded ? 6 + StyleTabMetrics.chromeBottomInset : 0)
        .frame(
            height: padded
                ? StyleTabMetrics.tabBarHeight
                : CircleIcon.Size.normal.side
        )
        .accessibilityElement(children: .contain)
    }
}

struct StyleTabChromeBackground<T: StyleTabRepresentable>: View {
    let pagerState: StyleTabPagerState<T>

    var body: some View {
        let tabs = Array(T.allCases)
        let snapshot = pagerState.snapshot

        StyleWash.headerGlassFill(
            fromInk: tabs[snapshot.fromIndex].headerWashInk,
            toInk: tabs[snapshot.toIndex].headerWashInk,
            progress: snapshot.pageProgress
        )
    }
}

/// Paper-to-grey canvas with a quiet style wash that scrubs with the pager.
struct StyleTabPageBackground<T: StyleTabRepresentable>: View {
    let pagerState: StyleTabPagerState<T>

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let tabs = Array(T.allCases)
        let snapshot = pagerState.snapshot
        let amount = min(1, max(0, snapshot.pageProgress))
        let tint = StyleTabMetrics.pageTint(isDark: colorScheme == .dark)

        ZStack {
            LinearGradient(
                colors: [theme.paper, theme.grey],
                startPoint: .top,
                endPoint: .bottom
            )

            styleWash(
                ink: tabs[snapshot.fromIndex].headerWashInk,
                tint: tint
            )
            .opacity(1 - amount)

            styleWash(
                ink: tabs[snapshot.toIndex].headerWashInk,
                tint: tint
            )
            .opacity(amount)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .animation(nil, value: snapshot)
    }

    private func styleWash(ink: Color, tint: CGFloat) -> some View {
        LinearGradient(
            colors: [
                ink.opacity(tint),
                ink.opacity(tint * 0.28),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Tab-bar fade using the same quiet style wash as the page canvas.
struct StyleTabBottomFade<T: StyleTabRepresentable>: View {
    let pagerState: StyleTabPagerState<T>
    let safeBottom: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let tabs = Array(T.allCases)
        let snapshot = pagerState.snapshot
        let amount = min(1, max(0, snapshot.pageProgress))
        let tint = StyleTabMetrics.pageTint(isDark: colorScheme == .dark)

        ZStack {
            LinearGradient(
                stops: CanvasEdgeFade.bottomStops(theme: theme),
                startPoint: .top,
                endPoint: .bottom
            )

            footerWash(
                ink: tabs[snapshot.fromIndex].headerWashInk,
                tint: tint
            )
            .opacity(1 - amount)

            footerWash(
                ink: tabs[snapshot.toIndex].headerWashInk,
                tint: tint
            )
            .opacity(amount)
        }
        .frame(height: HeaderCollapse.bottomFadeHeight(safeBottom: safeBottom))
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(nil, value: snapshot)
    }

    private func footerWash(ink: Color, tint: CGFloat) -> some View {
        LinearGradient(
            colors: [
                .clear,
                ink.opacity(tint * 0.55),
                ink.opacity(tint),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct StyleTabChipLayout: Layout {
    struct Cache {
        var iconSize: CGSize
        var labelSize: CGSize
    }

    var expansion: CGFloat

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(
            iconSize: subviews.indices.contains(0)
                ? subviews[0].sizeThatFits(.unspecified)
                : .zero,
            labelSize: subviews.indices.contains(1)
                ? subviews[1].sizeThatFits(.unspecified)
                : .zero
        )
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        guard subviews.count == 2 else {
            return .zero
        }

        let side = ReframeCardMetrics.chipSize
        let expandedWidth = max(
            side,
            20 + cache.iconSize.width + 6 + cache.labelSize.width
        )

        return CGSize(
            width: side + ((expandedWidth - side) * expansion),
            height: side
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard subviews.count == 2 else {
            return
        }

        let side = ReframeCardMetrics.chipSize
        let iconSize = cache.iconSize
        let labelSize = cache.labelSize
        let collapsedIconX = (side - iconSize.width) / 2
        let expandedIconX: CGFloat = 10
        let iconX = collapsedIconX
            + ((expandedIconX - collapsedIconX) * expansion)
        let iconY = bounds.midY - (iconSize.height / 2)

        subviews[0].place(
            at: CGPoint(x: bounds.minX + iconX, y: iconY),
            anchor: .topLeading,
            proposal: ProposedViewSize(iconSize)
        )

        subviews[1].place(
            at: CGPoint(
                x: bounds.minX + expandedIconX + iconSize.width + 6,
                y: bounds.midY - (labelSize.height / 2)
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(labelSize)
        )
    }
}

private struct StyleTabChip<T: StyleTabRepresentable>: View {
    let tab: T
    let expansion: CGFloat
    let isSettledSelection: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectHaptic = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var appearance: CardStyleAppearance? {
        tab.matchingStyle.map(CardStyleAppearance.init)
    }

    private var ink: Color {
        tab.symbolColor(ink: theme.ink)
    }

    var body: some View {
        let side = ReframeCardMetrics.chipSize
        let slop = (ReframeCardMetrics.chipHitSize - side) / 2
        let clampedExpansion = min(1, max(0, expansion))

        Button {
            guard !isSettledSelection else {
                return
            }
            selectHaptic += 1
            onSelect()
        } label: {
            StyleTabChipLayout(expansion: clampedExpansion) {
                Image(systemName: tab.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))

                Text(tab.chipTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(clampedExpansion)
                    .scaleEffect(
                        0.84 + (0.16 * clampedExpansion),
                        anchor: .leading
                    )
            }
            .foregroundStyle(ink.opacity(inkOpacity(for: clampedExpansion)))
            .frame(height: side)
            .clipped()
            .background {
                Capsule(style: .continuous)
                    .fill(chipFill(for: clampedExpansion))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                tab.usesNeutralChip ? theme.cardHairline : .clear,
                                lineWidth: 0.5
                            )
                    }
            }
            .padding(slop)
            .contentShape(Capsule())
            .padding(-slop)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectHaptic)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(
            isSettledSelection ? [.isButton, .isSelected] : .isButton
        )
    }

    private func chipFill(for expansion: CGFloat) -> Color {
        if tab.usesNeutralChip {
            let unselected = colorScheme == .dark ? 0.72 : 0.68
            return theme.surface.opacity(
                unselected + ((1 - unselected) * Double(expansion))
            )
        }
        return ink.opacity(fillOpacity(for: expansion))
    }

    private func fillOpacity(for expansion: CGFloat) -> Double {
        let selected: Double
        let unselected: Double
        if let appearance {
            selected = appearance.chipFillOpacity(for: colorScheme)
            unselected = appearance.chipUnselectedFillOpacity(for: colorScheme)
        } else {
            selected = colorScheme == .dark ? 0.16 : 0.22
            unselected = colorScheme == .dark ? 0.13 : 0.16
        }

        return unselected + ((selected - unselected) * Double(expansion))
    }

    private var unselectedInkOpacity: Double {
        appearance?.chipUnselectedInkOpacity(for: colorScheme)
            ?? (colorScheme == .dark ? 0.84 : 0.72)
    }

    private func inkOpacity(for expansion: CGFloat) -> Double {
        unselectedInkOpacity
            + ((1 - unselectedInkOpacity) * Double(expansion))
    }
}
