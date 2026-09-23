import SwiftUI
import UIKit

struct AuthorRoute: Hashable, Identifiable {
    let id: UUID
    let initials: String
    let avatarPath: String?
    let isSelf: Bool
}

private enum AuthorMetrics {
    static let pagerSpace = "authorPager"

    static func chromeHeight(safeTop: CGFloat) -> CGFloat {
        HeaderCollapse.overlayHeight(safeTop: safeTop) + StyleTabMetrics.chromeBottomInset
    }
}

struct AuthorProfileView: View {
    let route: AuthorRoute
    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel
    let onOpenAuthor: (HomeCard) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pagerState = StyleTabPagerState<HomeFeedTab>(initialTab: .all)
    @State private var committedTab: HomeFeedTab = .all

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var header: AuthorHeader {
        viewModel.authorHeader(for: route.id)
            ?? AuthorHeader(
                initials: route.initials,
                avatarPath: route.avatarPath,
                isSelf: route.isSelf,
                following: false
            )
    }

    private var chromeHeight: CGFloat {
        AuthorMetrics.chromeHeight(safeTop: safeAreaInsets.top)
    }

    var body: some View {
        ZStack(alignment: .top) {
            StyleTabPageBackground(pagerState: pagerState)
                .ignoresSafeArea()

            pager
                .ignoresSafeArea(edges: .top)

            chrome
                .ignoresSafeArea(edges: .top)

            StyleTabBottomFade(pagerState: pagerState, safeBottom: safeAreaInsets.bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .accessibilityAction(named: "Back") {
            dismiss()
        }
        .task(id: route.id) {
            await viewModel.loadAuthorIfNeeded(route)
        }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: safeAreaInsets.top + HeaderCollapse.headerTopPad)
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 12) {
                Button(action: dismiss.callAsFunction) {
                    CircleIcon(
                        systemName: "chevron.left",
                        fill: theme.surface,
                        symbol: theme.ink,
                        weight: .semibold,
                        hairline: theme.cardHairline
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                StyleTabBar(
                    pagerState: pagerState,
                    settledSelection: committedTab,
                    includesTrailingSpacer: true,
                    padded: false,
                    onSelect: selectTab
                )

                ZStack(alignment: .bottomTrailing) {
                    AuthorMark(
                        initials: header.initials,
                        avatarPath: header.avatarPath,
                        prefersLocalPhoto: header.isSelf,
                        side: CircleIcon.Size.normal.side,
                        fill: theme.ink,
                        symbol: theme.paper
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Posts by \(header.initials)")
                    .accessibilityAddTraits(.isHeader)

                    if !header.isSelf {
                        FollowBadge(following: header.following) {
                            viewModel.toggleFollow(route.id)
                        }
                        .offset(FollowBadge.overhang)
                    }
                }
            }
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
            .frame(height: HeaderCollapse.headerHeight)

            Color.clear
                .frame(height: StyleTabMetrics.chromeBottomInset)
                .allowsHitTesting(false)
        }
        .frame(height: chromeHeight, alignment: .top)
        .background {
            StyleTabChromeBackground(pagerState: pagerState)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var pager: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(HomeFeedTab.allCases, id: \.self) { tab in
                            AuthorTabPage(
                                tab: tab,
                                cards: viewModel.authorCards(for: route.id, tab: tab),
                                loadState: viewModel.authorLoadState(for: route.id),
                                footerState: viewModel.authorFooterState(for: route.id),
                                emptyCopy: tab.emptyCopy(appliedFilter: HomeFeedFilter()),
                                chromeHeight: chromeHeight,
                                allowsPullToRefresh: tab == committedTab,
                                onRetry: { viewModel.retryLoadAuthor(route.id) },
                                onRefresh: { await viewModel.refreshAuthor(route.id) },
                                onLoadMore: { viewModel.loadMoreAuthor(route.id) },
                                onRetryLoadMore: { viewModel.retryLoadMoreAuthor(route.id) },
                                onDelete: deleteCard,
                                onToggleFavorite: toggleFavorite,
                                onSetPublic: setPublic,
                                onRemoveFromBoard: removeFromBoard,
                                onOpenAuthor: onOpenAuthor,
                                onToggleFollow: toggleFollow
                            )
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(tab)
                        }
                    }
                    .background(alignment: .leading) {
                        StyleTabPagerOffsetProbe(space: AuthorMetrics.pagerSpace)
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .background(AuthorPopGesture())
                .coordinateSpace(name: AuthorMetrics.pagerSpace)
                .modifier(
                    StyleTabPagerTracking(
                        state: pagerState,
                        fallbackWidth: proxy.size.width,
                        onReachPage: commitPage
                    )
                )
                .onChange(of: pagerState.requestSerial) { _, _ in
                    let animation: Animation? = pagerState.requestAnimated ? tabAnimation : nil
                    var transaction = Transaction(animation: animation)
                    if animation == nil {
                        transaction.disablesAnimations = true
                    }
                    withTransaction(transaction) {
                        scrollProxy.scrollTo(pagerState.requestedTab, anchor: .leading)
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
            return
        }
        pagerState.requestPage(tab)
    }

    private func commitPage(_ tab: HomeFeedTab) {
        guard tab != committedTab else {
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            committedTab = tab
        }
        viewModel.selectAuthorTab(route.id, tab)
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
        if card.isOwner {
            viewModel.setPublic(card.id, isPublic: isPublic)
        }
    }

    private func removeFromBoard(_ card: HomeCard) {
        if !card.isOwner {
            viewModel.removeFromBoard(card.id)
        }
    }
}

private struct AuthorTabPage: View {
    let tab: HomeFeedTab
    let cards: [HomeCard]
    let loadState: LibraryLoadState
    let footerState: FeedFooterState
    let emptyCopy: String
    let chromeHeight: CGFloat
    let allowsPullToRefresh: Bool
    let onRetry: () -> Void
    let onRefresh: () async -> Void
    let onLoadMore: () -> Void
    let onRetryLoadMore: () -> Void
    let onDelete: (HomeCard) -> Void
    let onToggleFavorite: (HomeCard, Style) -> Void
    let onSetPublic: (HomeCard, Bool) -> Void
    let onRemoveFromBoard: (HomeCard) -> Void
    let onOpenAuthor: (HomeCard) -> Void
    let onToggleFollow: (HomeCard) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            let viewportBelowChrome = max(0, proxy.size.height - chromeHeight)
            let tallCardMaxHeight = max(
                0,
                viewportBelowChrome - HeaderCollapse.horizontalPadding - 72
            )
            ScrollView {
                VStack(spacing: 0) {
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
            .modifier(
                HomeFeedNativeRefresh(
                    enabled: allowsPullToRefresh,
                    onRefresh: onRefresh
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func tabContent(cardMaxHeight: CGFloat) -> some View {
        switch loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .accessibilityLabel("Loading posts")
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
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    footer
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
                        onOpenAuthor: onOpenAuthor,
                        onToggleFollow: onToggleFollow,
                        onReachEnd: onLoadMore,
                        loadMorePrefetchDistance: 6
                    )
                    .equatable()
                    .padding(.horizontal, HeaderCollapse.horizontalPadding)
                    .padding(.top, HeaderCollapse.horizontalPadding)

                    footer
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
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

/// Begins an edge-swipe back only when there is a screen to go back to.
private final class PopGate: NSObject, UIGestureRecognizerDelegate {
    weak var navigation: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigation?.viewControllers.count ?? 0) > 1
    }
}

/// Keeps the system edge-swipe back while the style pager also claims horizontal drags.
private struct AuthorPopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        private var didAttachScroll = false
        private let gate = PopGate()
        private weak var gatedPop: UIGestureRecognizer?
        private weak var originalDelegate: UIGestureRecognizerDelegate?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            attach()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restore()
        }

        private func attach() {
            guard let navigation = navigationController,
                  let pop = navigation.interactivePopGestureRecognizer,
                  navigation.viewControllers.count > 1
            else {
                return
            }
            pop.isEnabled = true
            if pop.delegate !== gate {
                originalDelegate = pop.delegate
                gate.navigation = navigation
                pop.delegate = gate
                gatedPop = pop
            }
            guard !didAttachScroll, let scroll = nearestHorizontalScrollView() else {
                return
            }
            scroll.panGestureRecognizer.require(toFail: pop)
            didAttachScroll = true
        }

        /// Hands the recognizer back so the root of the stack never starts a pop with nothing to pop.
        private func restore() {
            guard let pop = gatedPop, pop.delegate === gate else {
                return
            }
            pop.delegate = originalDelegate
            gatedPop = nil
        }

        private func nearestHorizontalScrollView() -> UIScrollView? {
            var current: UIView? = view.superview
            while let candidate = current {
                if let scroll = candidate as? UIScrollView,
                   scroll.contentSize.width > scroll.bounds.width + 8 {
                    return scroll
                }
                current = candidate.superview
            }
            return nil
        }
    }
}
