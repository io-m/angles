import Observation
import SwiftUI

private let pagingTabsSpace = "pagingTabs"

/// Where a paging strip's underline sits, from the scroll offset.
enum PagingTrack {
    /// Fractional page index. Scrolling toward the next page makes `contentMinX` negative.
    /// Rubber-band offsets clamp so the indicator stays on the tab row.
    static func pageIndex(contentMinX: CGFloat, pageWidth: CGFloat, pageCount: Int) -> CGFloat {
        guard pageWidth > 0, pageCount > 1 else { return 0 }
        let raw = -contentMinX / pageWidth
        return min(max(raw, 0), CGFloat(pageCount - 1))
    }

    /// The tab the line has reached. Halfway rounds onto the next page.
    static func nearestPage(_ index: CGFloat, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let rounded = Int(index.rounded())
        return min(max(rounded, 0), pageCount - 1)
    }
}

/// Icon and title for one tab, in the same metrics as Profile.
struct PagingTabLabel: View {
    let title: String
    let symbol: String
    let selectedSymbol: String
    var isSelected: Bool
    var tint: Color

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isSelected ? selectedSymbol : symbol)
                .symbolVariant(isSelected ? .fill : .none)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? tint : theme.muted)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? theme.ink : theme.muted)
        }
        .frame(height: 22)
    }
}

/// Finger position for one pager. The tab strip reads it; the pages only write it,
/// so a drag frame does not rebuild the scroll view.
@Observable
final class PagingTrackModel {
    var progress: CGFloat = 0
    /// The tab whose icon is filled. A tap sets it immediately; a swipe flips it halfway.
    var activeIndex = 0
    var hapticTick = 0
    private var hasMeasured = false
    private var nearestIndex = 0
    private var reportedPage = -1
    /// Tap target. Holds the filled icon until the scroll offset catches up.
    private var pinnedIndex: Int?

    func reset(to index: Int) {
        progress = CGFloat(index)
        activeIndex = index
        nearestIndex = index
        reportedPage = index
        pinnedIndex = nil
        hasMeasured = false
    }

    /// Fills this tab's icon now. The underline still follows the scroll.
    func activate(_ index: Int) {
        guard activeIndex != index else { return }
        activeIndex = index
        pinnedIndex = index
        hapticTick += 1
    }

    /// Moves the line. `onSettled` runs once the offset is sitting on a page, not while the finger is between them.
    func note(contentMinX: CGFloat, pageWidth: CGFloat, pageCount: Int, onSettled: (Int) -> Void) {
        guard pageWidth > 0 else { return }
        let index = PagingTrack.pageIndex(
            contentMinX: contentMinX,
            pageWidth: pageWidth,
            pageCount: pageCount
        )
        let nearest = PagingTrack.nearestPage(index, pageCount: pageCount)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            progress = index
            if let pinned = pinnedIndex {
                if nearest == pinned {
                    pinnedIndex = nil
                }
            } else if nearest != activeIndex {
                if hasMeasured {
                    hapticTick += 1
                }
                activeIndex = nearest
            }
            nearestIndex = nearest
            hasMeasured = true
        }
        guard abs(index - index.rounded()) < 0.04 else { return }
        let page = min(max(Int(index.rounded()), 0), max(pageCount - 1, 0))
        guard page != reportedPage else { return }
        reportedPage = page
        onSettled(page)
    }
}

/// Profile-style tabs whose underline tracks a horizontal swipe. The pages slide with it.
/// The strip and the pages are separate so a sheet can put the strip on the frosted bar.
struct PagingSplit<ID: Hashable, Label: View, Page: View, Root: View>: View {
    let ids: [ID]
    @Binding var selection: ID
    /// Pull to refresh on a page. Filter leaves this empty.
    var onRefresh: ((ID) async -> Void)?
    let tint: (ID) -> Color
    let label: (ID, Bool) -> Label
    let page: (ID) -> Page
    let root: (PagingTabBar<ID, Label>, PagingPages<ID, Page>) -> Root

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var track = PagingTrackModel()
    @State private var scrollToken = 0
    @State private var ignoreSelectionChange = false

    init(
        ids: [ID],
        selection: Binding<ID>,
        onRefresh: ((ID) async -> Void)? = nil,
        tint: @escaping (ID) -> Color,
        @ViewBuilder label: @escaping (ID, Bool) -> Label,
        @ViewBuilder page: @escaping (ID) -> Page,
        @ViewBuilder root: @escaping (PagingTabBar<ID, Label>, PagingPages<ID, Page>) -> Root
    ) {
        self.ids = ids
        self._selection = selection
        self.onRefresh = onRefresh
        self.tint = tint
        self.label = label
        self.page = page
        self.root = root
        let initial = ids.firstIndex(of: selection.wrappedValue) ?? 0
        let model = PagingTrackModel()
        model.reset(to: initial)
        self._track = State(initialValue: model)
    }

    var body: some View {
        root(tabBar, pages)
            .onChange(of: selection) { _, _ in
                if ignoreSelectionChange {
                    ignoreSelectionChange = false
                    return
                }
                scrollToken += 1
            }
    }

    private var tabBar: PagingTabBar<ID, Label> {
        PagingTabBar(
            ids: ids,
            track: track,
            tint: tint,
            label: label,
            onSelect: select
        )
    }

    private var pages: PagingPages<ID, Page> {
        PagingPages(
            ids: ids,
            selection: selection,
            scrollToken: scrollToken,
            spring: tapSpring,
            track: track,
            onRefresh: onRefresh,
            page: page,
            onSettled: settle
        )
    }

    private var tapSpring: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    private func select(_ id: ID) {
        guard selection != id, let index = ids.firstIndex(of: id) else { return }
        track.activate(index)
        ignoreSelectionChange = true
        selection = id
        scrollToken += 1
    }

    private func settle(on index: Int) {
        guard ids.indices.contains(index) else { return }
        let id = ids[index]
        guard selection != id else { return }
        ignoreSelectionChange = true
        selection = id
    }
}

/// The strip. Reads the track, so it is the only view that redraws while a finger is down.
struct PagingTabBar<ID: Hashable, Label: View>: View {
    let ids: [ID]
    let track: PagingTrackModel
    let tint: (ID) -> Color
    let label: (ID, Bool) -> Label
    let onSelect: (ID) -> Void

    var body: some View {
        let progress = track.progress
        let activeIndex = track.activeIndex
        HStack(spacing: 0) {
            ForEach(ids, id: \.self) { id in
                let selected = isSelected(id, activeIndex: activeIndex)
                Button {
                    onSelect(id)
                } label: {
                    VStack(spacing: 10) {
                        label(id, selected)
                        Color.clear.frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .overlay {
            GeometryReader { geo in
                let count = CGFloat(max(ids.count, 1))
                let inner = max(0, geo.size.width - HeaderCollapse.horizontalPadding * 2)
                let tabWidth = inner / count
                Capsule()
                    .fill(indicatorTint(progress: progress))
                    .frame(width: tabWidth, height: 2)
                    .offset(x: HeaderCollapse.horizontalPadding + progress * tabWidth)
                    .animation(nil, value: progress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .allowsHitTesting(false)
        }
        .sensoryFeedback(.selection, trigger: track.hapticTick)
    }

    private func isSelected(_ id: ID, activeIndex: Int) -> Bool {
        guard let index = ids.firstIndex(of: id) else { return false }
        return index == activeIndex
    }

    private func indicatorTint(progress: CGFloat) -> Color {
        let index = PagingTrack.nearestPage(progress, pageCount: ids.count)
        guard ids.indices.contains(index) else {
            return ids.first.map { tint($0) } ?? .clear
        }
        return tint(ids[index])
    }
}

/// Horizontal paging scroll. Writes the track from its offset and does not read it.
struct PagingPages<ID: Hashable, Page: View>: View {
    let ids: [ID]
    let selection: ID
    let scrollToken: Int
    let spring: Animation?
    let track: PagingTrackModel
    let onRefresh: ((ID) async -> Void)?
    let page: (ID) -> Page
    let onSettled: (Int) -> Void

    @State private var settled: ID?

    init(
        ids: [ID],
        selection: ID,
        scrollToken: Int,
        spring: Animation?,
        track: PagingTrackModel,
        onRefresh: ((ID) async -> Void)?,
        page: @escaping (ID) -> Page,
        onSettled: @escaping (Int) -> Void
    ) {
        self.ids = ids
        self.selection = selection
        self.scrollToken = scrollToken
        self.spring = spring
        self.track = track
        self.onRefresh = onRefresh
        self.page = page
        self.onSettled = onSettled
        self._settled = State(initialValue: selection)
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(ids, id: \.self) { id in
                        ScrollView(.vertical) {
                            page(id)
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .scrollBounceBehavior(onRefresh == nil ? .automatic : .always)
                        .modifier(PageRefresh(action: onRefresh.map { refresh in
                            { await refresh(id) }
                        }))
                        .containerRelativeFrame(.horizontal)
                        .id(id)
                    }
                }
                .scrollTargetLayout()
                .background {
                    // iOS 17 has no scroll geometry callback. The named space has to sit
                    // on the scroll view, or the content's frame never includes the offset.
                    if #unavailable(iOS 18) {
                        GeometryReader { content in
                            Color.clear.preference(
                                key: PagerScrollMetricsKey.self,
                                value: PagerScrollMetrics(
                                    contentMinX: content.frame(in: .named(pagingTabsSpace)).minX,
                                    pageWidth: viewport.size.width
                                )
                            )
                        }
                    }
                }
            }
            .coordinateSpace(name: pagingTabsSpace)
            .contentMargins(0, for: .scrollContent)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $settled, anchor: .leading)
            .scrollIndicators(.hidden)
            .modifier(
                PagingOffsetReader { metrics in
                    track.note(
                        contentMinX: metrics.contentMinX,
                        pageWidth: metrics.pageWidth,
                        pageCount: ids.count,
                        onSettled: onSettled
                    )
                }
            )
            .onChange(of: scrollToken) { _, _ in
                guard ids.contains(selection) else { return }
                if let spring {
                    withAnimation(spring) { settled = selection }
                } else {
                    settled = selection
                }
            }
        }
    }
}

/// Pull to refresh only on pages that asked for it. Filter's lists do not.
private struct PageRefresh: ViewModifier {
    var action: (() async -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.refreshable(action: action)
        } else {
            content
        }
    }
}

/// Scroll offset for the underline. Geometry is the live content offset; a layout
/// frame outside the scroll view stays at zero while the finger moves.
private struct PagingOffsetReader: ViewModifier {
    let onMetrics: (PagerScrollMetrics) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: PagerScrollMetrics.self) { geo in
                let scrolled = geo.contentOffset.x + geo.contentInsets.leading
                return PagerScrollMetrics(
                    contentMinX: -scrolled,
                    pageWidth: geo.containerSize.width
                )
            } action: { _, metrics in
                onMetrics(metrics)
            }
        } else {
            content.onPreferenceChange(PagerScrollMetricsKey.self, perform: onMetrics)
        }
    }
}

private struct PagerScrollMetrics: Equatable {
    var contentMinX: CGFloat = 0
    var pageWidth: CGFloat = 0
}

private struct PagerScrollMetricsKey: PreferenceKey {
    static var defaultValue = PagerScrollMetrics()

    static func reduce(value: inout PagerScrollMetrics, nextValue: () -> PagerScrollMetrics) {
        value = nextValue()
    }
}
