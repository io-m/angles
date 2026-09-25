import SwiftUI

enum HomeFeedPagerMetrics {
    static func chromeHeight(safeTop: CGFloat) -> CGFloat {
        HeaderCollapse.overlayHeight(safeTop: safeTop) + StyleTabMetrics.chromeBottomInset
    }
}

struct HomeView: View {
    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager
    /// AppRoot owns Home's first load; this only gates in-place refresh.
    var canLoadFullAppContent = false
    var glimpseCard: HomeCard? = nil
    var isGlimpseActive = false
    var isActiveTab: Bool = true
    var onLogOut: (() -> Void)? = nil
    var onOpenAuthor: (HomeCard) -> Void = { _ in }
    var onOpenModel: (HomeCard) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showHomeFilter = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HomeFeedPager(
            safeAreaInsets: safeAreaInsets,
            cards: cards(for:),
            loadState: viewModel.feedLoadState,
            footerState: viewModel.feedFooterState,
            emptyCopy: viewModel.feedEmptyCopy(for:),
            glimpseCard: glimpseCard,
            scrollToTopToken: viewModel.saveLanding == .home
                ? viewModel.saveLandingToken
                : 0,
            shiningCardID: viewModel.shiningCardID,
            isScrollDisabled: isGlimpseActive,
            canPullToRefresh: canLoadFullAppContent && !isGlimpseActive,
            offersOwnerPrivacyMenu: true,
            externalSelectionTab: viewModel.saveLanding == .home ? .all : nil,
            externalSelectionToken: viewModel.saveLandingToken,
            onCommitPage: commitPage,
            onRetry: viewModel.retryLoadFeed,
            onRefresh: { await viewModel.refreshFeed() },
            onLoadMore: viewModel.loadMoreFeed,
            onRetryLoadMore: viewModel.retryLoadMoreFeed,
            onDelete: deleteCard,
            onToggleFavorite: toggleFavorite,
            onSetPublic: setPublic,
            onRemoveFromBoard: removeFromBoard,
            onReport: reportCard,
            onBlock: blockAuthor,
            onOpenAuthor: onOpenAuthor,
            onOpenModel: onOpenModel,
            onToggleFollow: toggleFollow
        ) { pagerState, settledSelection, onSelectTab in
            HomeChrome(
                safeTop: safeAreaInsets.top,
                pagerState: pagerState,
                settledSelection: settledSelection,
                appliedCount: viewModel.appliedFilter.appliedCount,
                showFilter: $showHomeFilter,
                onSelectTab: onSelectTab
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .sheet(isPresented: $showHomeFilter) {
            HomeFilterSheet(appliedFilter: viewModel.appliedFilter) { filter in
                viewModel.applyFeedFilter(filter)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.grey)
        }
    }

    private func cards(for tab: HomeFeedTab) -> [HomeCard] {
        let base = viewModel.homeCards(for: tab)
        guard tab == .all, let glimpseCard else {
            return base
        }
        return [glimpseCard] + base.filter { $0.id != glimpseCard.id }
    }

    private func commitPage(_ tab: HomeFeedTab) {
        if tab != viewModel.homeFeedTab {
            viewModel.homeFeedTab = tab
        }
    }

    private func deleteCard(_ card: HomeCard) {
        guard card.isOwner else {
            return
        }
        viewModel.deleteCard(card.id)
    }

    private func toggleFavorite(_ card: HomeCard, _ style: Style) {
        viewModel.toggleFavorite(card.id, style: style)
    }

    private func toggleFollow(_ card: HomeCard) {
        guard let authorId = card.authorId, !card.isOwner else {
            return
        }
        viewModel.toggleFollow(authorId)
    }

    private func setPublic(_ card: HomeCard, _ isPublic: Bool) {
        guard card.isOwner else {
            return
        }
        if reduceMotion {
            viewModel.setPublic(card.id, isPublic: isPublic)
        } else {
            withAnimation(.smooth(duration: 0.3)) {
                viewModel.setPublic(card.id, isPublic: isPublic)
            }
        }
    }

    private func removeFromBoard(_ card: HomeCard) {
        if !card.isOwner {
            viewModel.removeFromBoard(card.id)
        }
    }

    private func reportCard(_ card: HomeCard, _ reason: ReportReason) {
        guard !card.isOwner else { return }
        viewModel.reportCard(card.id, reason: reason)
    }

    private func blockAuthor(_ card: HomeCard) {
        guard !card.isOwner, let authorId = card.authorId else { return }
        viewModel.blockAuthor(
            authorId,
            initials: card.authorInitials,
            avatarPath: card.authorAvatarPath
        )
    }
}

struct HomeFeedPager<Chrome: View>: View {
    let safeAreaInsets: EdgeInsets
    let cards: (HomeFeedTab) -> [HomeCard]
    let loadState: LibraryLoadState
    let footerState: FeedFooterState
    let emptyCopy: (HomeFeedTab) -> String
    let glimpseCard: HomeCard?
    let scrollToTopToken: Int
    let shiningCardID: UUID?
    let isScrollDisabled: Bool
    let canPullToRefresh: Bool
    let offersOwnerPrivacyMenu: Bool
    let externalSelectionTab: HomeFeedTab?
    let externalSelectionToken: Int
    let onCommitPage: (HomeFeedTab) -> Void
    let onRetry: () -> Void
    let onRefresh: () async -> Void
    let onLoadMore: () -> Void
    let onRetryLoadMore: () -> Void
    let onDelete: (HomeCard) -> Void
    let onToggleFavorite: (HomeCard, Style) -> Void
    let onSetPublic: (HomeCard, Bool) -> Void
    let onRemoveFromBoard: (HomeCard) -> Void
    let onReport: (HomeCard, ReportReason) -> Void
    let onBlock: (HomeCard) -> Void
    let onOpenAuthor: (HomeCard) -> Void
    let onOpenModel: (HomeCard) -> Void
    let onToggleFollow: (HomeCard) -> Void
    let chrome: (
        StyleTabPagerState<HomeFeedTab>,
        HomeFeedTab,
        @escaping (HomeFeedTab) -> Void
    ) -> Chrome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pagerState = StyleTabPagerState<HomeFeedTab>(initialTab: .all)
    @State private var committedTab: HomeFeedTab = .all
    @State private var sameTabScrollToken = 0
    @State private var pagerSpace = UUID()

    init(
        safeAreaInsets: EdgeInsets,
        cards: @escaping (HomeFeedTab) -> [HomeCard],
        loadState: LibraryLoadState,
        footerState: FeedFooterState,
        emptyCopy: @escaping (HomeFeedTab) -> String,
        glimpseCard: HomeCard? = nil,
        scrollToTopToken: Int = 0,
        shiningCardID: UUID? = nil,
        isScrollDisabled: Bool = false,
        canPullToRefresh: Bool = true,
        offersOwnerPrivacyMenu: Bool = false,
        externalSelectionTab: HomeFeedTab? = nil,
        externalSelectionToken: Int = 0,
        onCommitPage: @escaping (HomeFeedTab) -> Void = { _ in },
        onRetry: @escaping () -> Void,
        onRefresh: @escaping () async -> Void,
        onLoadMore: @escaping () -> Void,
        onRetryLoadMore: @escaping () -> Void,
        onDelete: @escaping (HomeCard) -> Void,
        onToggleFavorite: @escaping (HomeCard, Style) -> Void,
        onSetPublic: @escaping (HomeCard, Bool) -> Void,
        onRemoveFromBoard: @escaping (HomeCard) -> Void,
        onReport: @escaping (HomeCard, ReportReason) -> Void,
        onBlock: @escaping (HomeCard) -> Void,
        onOpenAuthor: @escaping (HomeCard) -> Void,
        onOpenModel: @escaping (HomeCard) -> Void,
        onToggleFollow: @escaping (HomeCard) -> Void,
        @ViewBuilder chrome: @escaping (
            StyleTabPagerState<HomeFeedTab>,
            HomeFeedTab,
            @escaping (HomeFeedTab) -> Void
        ) -> Chrome
    ) {
        self.safeAreaInsets = safeAreaInsets
        self.cards = cards
        self.loadState = loadState
        self.footerState = footerState
        self.emptyCopy = emptyCopy
        self.glimpseCard = glimpseCard
        self.scrollToTopToken = scrollToTopToken
        self.shiningCardID = shiningCardID
        self.isScrollDisabled = isScrollDisabled
        self.canPullToRefresh = canPullToRefresh
        self.offersOwnerPrivacyMenu = offersOwnerPrivacyMenu
        self.externalSelectionTab = externalSelectionTab
        self.externalSelectionToken = externalSelectionToken
        self.onCommitPage = onCommitPage
        self.onRetry = onRetry
        self.onRefresh = onRefresh
        self.onLoadMore = onLoadMore
        self.onRetryLoadMore = onRetryLoadMore
        self.onDelete = onDelete
        self.onToggleFavorite = onToggleFavorite
        self.onSetPublic = onSetPublic
        self.onRemoveFromBoard = onRemoveFromBoard
        self.onReport = onReport
        self.onBlock = onBlock
        self.onOpenAuthor = onOpenAuthor
        self.onOpenModel = onOpenModel
        self.onToggleFollow = onToggleFollow
        self.chrome = chrome
    }

    private var chromeHeight: CGFloat {
        HomeFeedPagerMetrics.chromeHeight(safeTop: safeAreaInsets.top)
    }

    var body: some View {
        ZStack(alignment: .top) {
            StyleTabPageBackground(pagerState: pagerState)
                .ignoresSafeArea()

            pager
                .ignoresSafeArea(edges: .top)

            chrome(pagerState, committedTab, selectTab)
                .ignoresSafeArea(edges: .top)

            StyleTabBottomFade(
                pagerState: pagerState,
                safeBottom: safeAreaInsets.bottom
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(!isScrollDisabled)
    }

    private var pager: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(HomeFeedTab.allCases, id: \.self) { tab in
                            HomeFeedTabPage(
                                tab: tab,
                                cards: cards(tab),
                                loadState: loadState,
                                footerState: footerState,
                                emptyCopy: emptyCopy(tab),
                                chromeHeight: chromeHeight,
                                glimpseCard: tab == .all ? glimpseCard : nil,
                                scrollToTopToken: tab == .all
                                    ? scrollToTopToken
                                    : 0,
                                sameTabScrollToken: sameTabScrollToken,
                                isCurrentPage: tab == committedTab,
                                shiningCardID: shiningCardID,
                                isScrollDisabled: isScrollDisabled,
                                allowsPullToRefresh: canPullToRefresh
                                    && tab == committedTab,
                                onRetry: onRetry,
                                onRefresh: onRefresh,
                                onLoadMore: onLoadMore,
                                onRetryLoadMore: onRetryLoadMore,
                                onDelete: onDelete,
                                onToggleFavorite: onToggleFavorite,
                                onSetPublic: onSetPublic,
                                onRemoveFromBoard: onRemoveFromBoard,
                                onReport: onReport,
                                onBlock: onBlock,
                                onOpenAuthor: onOpenAuthor,
                                onOpenModel: onOpenModel,
                                onToggleFollow: onToggleFollow,
                                offersOwnerPrivacyMenu: offersOwnerPrivacyMenu
                            )
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(tab)
                        }
                    }
                    .background(alignment: .leading) {
                        StyleTabPagerOffsetProbe(space: pagerSpace)
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollDisabled(isScrollDisabled)
                .coordinateSpace(name: pagerSpace)
                .modifier(
                    StyleTabPagerTracking(
                        state: pagerState,
                        fallbackWidth: proxy.size.width,
                        onReachPage: commitPage
                    )
                )
                .onChange(of: pagerState.requestSerial) { _, _ in
                    let animation: Animation? = pagerState.requestAnimated
                        ? tabAnimation
                        : nil
                    var transaction = Transaction(animation: animation)
                    if animation == nil {
                        transaction.disablesAnimations = true
                    }
                    withTransaction(transaction) {
                        scrollProxy.scrollTo(
                            pagerState.requestedTab,
                            anchor: .leading
                        )
                    }
                }
                .onChange(of: externalSelectionToken) { _, token in
                    guard token > 0, externalSelectionTab != nil else {
                        return
                    }
                    settleExternalSelection()
                    Task { @MainActor in
                        settleExternalSelection()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabAnimation: Animation? {
        reduceMotion ? nil : StyleTabMetrics.chipSpring
    }

    private func selectTab(_ tab: HomeFeedTab) {
        guard tab != committedTab else {
            sameTabScrollToken &+= 1
            return
        }
        pagerState.requestPage(tab)
    }

    private func commitPage(_ tab: HomeFeedTab) {
        guard tab != committedTab else {
            return
        }
        settle(tab)
    }

    private func settleExternalSelection() {
        guard let externalSelectionTab else {
            return
        }
        settle(externalSelectionTab)
        pagerState.requestPage(externalSelectionTab, animated: false)
    }

    private func settle(_ tab: HomeFeedTab) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            committedTab = tab
            onCommitPage(tab)
        }
    }
}

private struct HomeChrome: View {
    let safeTop: CGFloat
    let pagerState: StyleTabPagerState<HomeFeedTab>
    let settledSelection: HomeFeedTab
    let appliedCount: Int
    @Binding var showFilter: Bool
    let onSelectTab: (HomeFeedTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: safeTop + HeaderCollapse.headerTopPad)
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 12) {
                AdaptiveStyleTabBar(
                    pagerState: pagerState,
                    settledSelection: settledSelection,
                    includesTrailingSpacer: true,
                    padded: false,
                    onSelect: onSelectTab
                )

                Button {
                    showFilter = true
                } label: {
                    HomeFilterIcon(appliedCount: appliedCount)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter Home")
                .accessibilityValue(filterAccessibilityValue(appliedCount))
            }
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
            .frame(height: HeaderCollapse.headerHeight)

            Color.clear
                .frame(height: StyleTabMetrics.chromeBottomInset)
                .allowsHitTesting(false)
        }
        .frame(
            height: HomeFeedPagerMetrics.chromeHeight(safeTop: safeTop),
            alignment: .top
        )
        .background {
            StyleTabChromeBackground(pagerState: pagerState)
                .ignoresSafeArea(edges: .top)
        }
    }
}

struct HomeFeedTabPage: View {
    let tab: HomeFeedTab
    let cards: [HomeCard]
    let loadState: LibraryLoadState
    let footerState: FeedFooterState
    let emptyCopy: String
    let chromeHeight: CGFloat
    let glimpseCard: HomeCard?
    let scrollToTopToken: Int
    let sameTabScrollToken: Int
    let isCurrentPage: Bool
    var shiningCardID: UUID? = nil
    let isScrollDisabled: Bool
    let allowsPullToRefresh: Bool
    let onRetry: () -> Void
    let onRefresh: () async -> Void
    let onLoadMore: () -> Void
    let onRetryLoadMore: () -> Void
    let onDelete: (HomeCard) -> Void
    let onToggleFavorite: (HomeCard, Style) -> Void
    let onSetPublic: (HomeCard, Bool) -> Void
    let onRemoveFromBoard: (HomeCard) -> Void
    let onReport: (HomeCard, ReportReason) -> Void
    let onBlock: (HomeCard) -> Void
    let onOpenAuthor: (HomeCard) -> Void
    let onOpenModel: (HomeCard) -> Void
    let onToggleFollow: (HomeCard) -> Void
    let offersOwnerPrivacyMenu: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            // Cards hug their text. The cap is the space under the header, minus the
            // same 16-point gap the list uses, minus a peek of the next card.
            let viewportBelowChrome = max(0, proxy.size.height - chromeHeight)
            let tallCardMaxHeight = max(
                0,
                viewportBelowChrome - HeaderCollapse.horizontalPadding - 72
            )
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id("home-tab-top")

                        Color.clear
                            .frame(height: chromeHeight)

                        tabContent(cardMaxHeight: tallCardMaxHeight)
                            .padding(.bottom, 20)
                    }
                    .frame(
                        minHeight: proxy.size.height,
                        alignment: .top
                    )
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.always)
                .scrollDisabled(isScrollDisabled)
                .modifier(
                    HomeFeedNativeRefresh(
                        enabled: allowsPullToRefresh,
                        onRefresh: onRefresh
                    )
                )
                .onChange(of: glimpseCard?.id) { _, cardID in
                    guard tab == .all, cardID != nil else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.35)) {
                        scrollProxy.scrollTo("home-tab-top", anchor: .top)
                    }
                }
                .onChange(of: scrollToTopToken) { _, token in
                    guard tab == .all, token > 0 else {
                        return
                    }
                    scrollFeedToTop(scrollProxy)
                    Task { @MainActor in
                        scrollFeedToTop(scrollProxy)
                    }
                }
                .onChange(of: sameTabScrollToken) { _, token in
                    guard token > 0, isCurrentPage else {
                        return
                    }
                    if reduceMotion {
                        scrollFeedToTop(scrollProxy)
                    } else {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            scrollProxy.scrollTo("home-tab-top", anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollFeedToTop(_ proxy: ScrollViewProxy) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo("home-tab-top", anchor: .top)
        }
    }

    @ViewBuilder
    private func tabContent(cardMaxHeight: CGFloat) -> some View {
        switch loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .accessibilityLabel("Loading Home")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                Button("Retry", action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
            }
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
        case .loaded:
            if cards.isEmpty {
                if footerState == .idle {
                    Text(emptyCopy)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, HeaderCollapse.horizontalPadding)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Older pages may still carry this angle; the copy waits for them.
                    feedFooter
                        .padding(.top, 16)
                }
            } else {
                VStack(spacing: 0) {
                    TallHomeCardGrid(
                        cards: cards,
                        cardMaxHeight: cardMaxHeight,
                        rowSpacing: HeaderCollapse.horizontalPadding,
                        openingStyle: tab.matchingStyle,
                        menuRole: { card in card.isOwner ? .owner : .feed },
                        onDelete: onDelete,
                        onToggleFavorite: onToggleFavorite,
                        onSetPublic: onSetPublic,
                        onRemoveFromBoard: onRemoveFromBoard,
                        onReport: onReport,
                        onBlock: onBlock,
                        shiningCardID: shiningCardID,
                        onOpenAuthor: onOpenAuthor,
                        onOpenModel: onOpenModel,
                        onToggleFollow: onToggleFollow,
                        onReachEnd: onLoadMore,
                        loadMorePrefetchDistance: 6,
                        offersOwnerPrivacyMenu: offersOwnerPrivacyMenu
                    )
                    .equatable()
                    .padding(.horizontal, HeaderCollapse.horizontalPadding)
                    .padding(.top, HeaderCollapse.horizontalPadding)

                    feedFooter
                }
            }
        }
    }

    @ViewBuilder
    private var feedFooter: some View {
        Group {
            switch footerState {
            case .idle:
                Color.clear
                    .accessibilityHidden(true)
            case .loading:
                ProgressView()
                    .accessibilityLabel("Loading more thoughts")
            case .failed:
                Button("Retry loading more", action: onRetryLoadMore)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }
}

private struct HomeFilterIcon: View {
    let appliedCount: Int

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        CircleIcon(
            systemName: "line.3.horizontal.decrease",
            fill: theme.surface,
            symbol: theme.ink,
            weight: .semibold,
            hairline: theme.cardHairline
        )
        .overlay(alignment: .topTrailing) {
            if appliedCount > 0 {
                Text(String(appliedCount))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.paper)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, 2)
                    .background(theme.ink, in: Capsule())
                    .offset(x: 5, y: -5)
                    .accessibilityHidden(true)
            }
        }
    }
}

private func filterAccessibilityValue(_ appliedCount: Int) -> String {
    appliedCount == 0 ? "No filters applied" : "\(appliedCount) filters applied"
}

#Preview("Home") {
    NavigationStack {
        HomeView(
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            viewModel: HomeViewModel(),
            storeKitManager: StoreKitManager()
        )
    }
    .environmentObject(ThemeStore())
}
