import Observation
import SwiftUI

private enum ProfileMetrics {
    static let identityHeight: CGFloat = 132
    static let tabBarHeight = StyleTabMetrics.tabBarHeight
    static let pagerSpace = "profilePager"

    static func expandedChromeHeight(safeTop: CGFloat) -> CGFloat {
        HeaderCollapse.overlayHeight(safeTop: safeTop)
            + identityHeight
            + tabBarHeight
    }

    static func chromeHeight(safeTop: CGFloat, collapseDistance: CGFloat) -> CGFloat {
        expandedChromeHeight(safeTop: safeTop)
            - min(identityHeight, max(0, collapseDistance))
    }

    static func identityProgress(_ collapseDistance: CGFloat) -> CGFloat {
        min(1, max(0, collapseDistance / identityHeight))
    }

    static func compactProgress(_ collapseDistance: CGFloat) -> CGFloat {
        let revealDistance = HeaderCollapse.collapsedRevealDistance
        return min(
            1,
            max(0, (collapseDistance - (identityHeight - revealDistance)) / revealDistance)
        )
    }
}

@MainActor
@Observable
private final class ProfileHeaderState {
    let distance = ProfileMetrics.identityHeight
}

struct ProfileView: View {

    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore? = nil
    /// Filled from Sign in with Apple / Better Auth in row 8. Nil keeps the session label.
    var displayName: String? = nil
    var onInspire: () -> Void = {}
    var onLogOut: (() -> Void)? = nil
    var onDeleteAccount: (() async -> Bool)? = nil
    var canLoadFullAppContent = false
    var onOpenAuthor: (HomeCard) -> Void = { _ in }
    var onOpenModel: (HomeCard) -> Void = { _ in }
    var onOpenFollowed: (FollowedPerson) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var headerState = ProfileHeaderState()
    @State private var pagerState = StyleTabPagerState<ProfileGridFilter>(initialTab: .favorites)
    @State private var showSettings = false
    @State private var showFollowing = false
    @State private var committedTab: ProfileGridFilter = .favorites

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var fixedChromeHeight: CGFloat {
        ProfileMetrics.chromeHeight(
            safeTop: safeAreaInsets.top,
            collapseDistance: ProfileMetrics.identityHeight
        )
    }

    private var profileTitle: String {
        if let identityStore {
            return identityStore.profileTitle
        }
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "On this iPhone" : trimmed
    }

    var body: some View {
        ZStack(alignment: .top) {
            StyleTabPageBackground(pagerState: pagerState)
                .ignoresSafeArea()

            pager
                .ignoresSafeArea(edges: .top)

            ProfileChrome(
                title: profileTitle,
                safeTop: safeAreaInsets.top,
                headerState: headerState,
                pagerState: pagerState,
                settledSelection: committedTab,
                showSettings: $showSettings,
                identityStore: identityStore,
                onOpenFollowing: { showFollowing = true },
                onSelectTab: selectTab
            )
            .ignoresSafeArea(edges: .top)

            StyleTabBottomFade(pagerState: pagerState, safeBottom: safeAreaInsets.bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .task(id: canLoadFullAppContent) {
            guard canLoadFullAppContent else {
                return
            }
            await viewModel.loadLibraryIfNeeded()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                storeKitManager: storeKitManager,
                identityStore: identityStore,
                onLogOut: {
                    onLogOut?()
                    showSettings = false
                },
                onDeleteAccount: {
                    guard await onDeleteAccount?() == true else {
                        return false
                    }
                    showSettings = false
                    return true
                },
                blockedPeople: viewModel.blockedPeople,
                blocksLoadState: viewModel.blocksLoadState,
                onLoadBlocks: { await viewModel.loadBlocks() },
                onRetryBlocks: { Task { await viewModel.loadBlocks() } },
                onUnblock: viewModel.unblock,
                writeError: viewModel.writeError,
                onDismissWriteError: viewModel.dismissWriteError
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.grey)
            .modifier(UserAppearance(store: themeStore))
        }
        .sheet(isPresented: $showFollowing) {
            FollowingSheet(
                people: viewModel.followedPeople,
                loadState: viewModel.followingLoadState,
                onRetry: { Task { await viewModel.loadFollowing() } },
                onUnfollow: { person in
                    viewModel.unfollow(person)
                },
                onOpen: { person in
                    showFollowing = false
                    onOpenFollowed(person)
                },
                writeError: viewModel.writeError,
                onDismissError: viewModel.dismissWriteError
            )
            .task { await viewModel.loadFollowing() }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.grey)
            .modifier(UserAppearance(store: themeStore))
        }
    }

    private var pager: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(ProfileGridFilter.allCases, id: \.self) { tab in
                            ProfileTabPage(
                                tab: tab,
                                cards: viewModel.profileCards(for: tab),
                                loadState: viewModel.libraryLoadState,
                                footerState: viewModel.libraryFooterState,
                                ownedIsEmpty: viewModel.ownedCards.isEmpty,
                                chromeHeight: fixedChromeHeight,
                                scrollToTopToken: {
                                    guard case .profile(let filter) = viewModel.saveLanding, filter == tab else {
                                        return 0
                                    }
                                    return viewModel.saveLandingToken
                                }(),
                                shiningCardID: viewModel.shiningCardID,
                                onInspire: onInspire,
                                onRetry: viewModel.retryLoadLibrary,
                                onRefresh: { await viewModel.refreshLibrary() },
                                onLoadMore: viewModel.loadMoreLibrary,
                                onRetryLoadMore: viewModel.retryLoadMoreLibrary,
                                onDelete: deleteCard,
                                onToggleFavorite: toggleFavorite,
                                onSetPublic: setPublic,
                                onRemoveFromBoard: removeFromBoard,
                                onReport: reportCard,
                                onBlock: blockAuthor,
                                onOpenAuthor: onOpenAuthor,
                                onOpenModel: onOpenModel,
                                onToggleFollow: toggleFollow
                            )
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(tab)
                        }
                    }
                    .background(alignment: .leading) {
                        StyleTabPagerOffsetProbe(space: ProfileMetrics.pagerSpace)
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .coordinateSpace(name: ProfileMetrics.pagerSpace)
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
                        scrollProxy.scrollTo(
                            pagerState.requestedTab,
                            anchor: .leading
                        )
                    }
                }
                .onChange(of: viewModel.saveLandingToken) { _, token in
                    guard token > 0, case .profile = viewModel.saveLanding else {
                        return
                    }
                    settleProfileLanding()
                    Task { @MainActor in
                        settleProfileLanding()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabAnimation: Animation? {
        reduceMotion ? nil : StyleTabMetrics.chipSpring
    }

    private func settleProfileLanding() {
        guard case .profile(let filter) = viewModel.saveLanding else {
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            committedTab = filter
            if viewModel.profileGridFilter != filter {
                viewModel.profileGridFilter = filter
            }
        }
        pagerState.requestPage(filter, animated: false)
    }

    private func selectTab(_ filter: ProfileGridFilter) {
        guard filter != committedTab else {
            return
        }
        pagerState.requestPage(filter)
    }

    private func commitPage(_ filter: ProfileGridFilter) {
        guard filter != committedTab else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            committedTab = filter
            if filter != viewModel.profileGridFilter {
                viewModel.profileGridFilter = filter
            }
        }
    }

    private func deleteCard(_ card: HomeCard) {
        guard card.isOwner else {
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            viewModel.deleteCard(card.id)
        }
    }

    private var favoriteLayoutAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private func toggleFavorite(_ card: HomeCard, _ style: Style) {
        withAnimation(favoriteLayoutAnimation) {
            viewModel.toggleFavorite(card.id, style: style)
        }
    }

    private func toggleFollow(_ card: HomeCard) {
        guard let authorId = card.authorId, !card.isOwner else {
            return
        }
        viewModel.toggleFollow(authorId)
    }

    private func setPublic(_ card: HomeCard, _ isPublic: Bool) {
        viewModel.setPublic(card.id, isPublic: isPublic)
    }

    private func removeFromBoard(_ card: HomeCard) {
        withAnimation(favoriteLayoutAnimation) {
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

private struct ProfileChrome: View {
    let title: String
    let safeTop: CGFloat
    let headerState: ProfileHeaderState
    let pagerState: StyleTabPagerState<ProfileGridFilter>
    let settledSelection: ProfileGridFilter
    @Binding var showSettings: Bool
    var identityStore: ProfileIdentityStore? = nil
    var onOpenFollowing: () -> Void = {}
    let onSelectTab: (ProfileGridFilter) -> Void

    var body: some View {
        let collapseDistance = headerState.distance
        let identityProgress = ProfileMetrics.identityProgress(collapseDistance)

        VStack(spacing: 0) {
            ProfileTopBar(
                title: title,
                safeTop: safeTop,
                collapseDistance: collapseDistance,
                showSettings: $showSettings,
                identityStore: identityStore,
                onOpenFollowing: onOpenFollowing
            )

            ProfileIdentityHeader(title: title, identityStore: identityStore)
                .frame(
                    height: ProfileMetrics.identityHeight - collapseDistance,
                    alignment: .top
                )
                .clipped()
                .opacity(Double(1 - identityProgress))
                .allowsHitTesting(identityProgress < 0.5)
                .accessibilityHidden(identityProgress >= 0.5)
                .animation(nil, value: collapseDistance)

            AdaptiveStyleTabBar(
                pagerState: pagerState,
                settledSelection: settledSelection,
                onSelect: onSelectTab
            )
        }
        .frame(
            height: ProfileMetrics.chromeHeight(
                safeTop: safeTop,
                collapseDistance: collapseDistance
            ),
            alignment: .top
        )
        .background {
            StyleTabChromeBackground(pagerState: pagerState)
            .ignoresSafeArea(edges: .top)
        }
    }
}

private enum ProfileViewAvatar {
    static let large: CGFloat = 76
    static let compact: CGFloat = 28
}

private struct ProfileIdentityHeader: View {
    let title: String
    var identityStore: ProfileIdentityStore? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileAvatar(
                identityStore: identityStore,
                letters: UserInitials.letters,
                side: ProfileViewAvatar.large,
                fill: theme.ink,
                symbol: theme.paper
            )

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct ProfileTopBar: View {
    let title: String
    let safeTop: CGFloat
    let collapseDistance: CGFloat
    @Binding var showSettings: Bool
    var identityStore: ProfileIdentityStore? = nil
    var onOpenFollowing: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let progress = ProfileMetrics.compactProgress(collapseDistance)

        HStack(spacing: 10) {
            HStack(spacing: 8) {
                ProfileAvatar(
                    identityStore: identityStore,
                    letters: UserInitials.letters,
                    side: ProfileViewAvatar.compact,
                    fill: theme.ink,
                    symbol: theme.paper
                )

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(-1)
            }
            .opacity(progress)
            .offset(y: reduceMotion ? 0 : HeaderCollapse.collapseSlide * (1 - progress))
            .animation(nil, value: collapseDistance)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHidden(progress <= 0.4)

            Spacer(minLength: 8)

            Button(action: onOpenFollowing) {
                CircleIcon(
                    systemName: "person.2",
                    fill: theme.surface,
                    symbol: theme.ink,
                    hairline: theme.cardHairline
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Following")

            Button {
                showSettings = true
            } label: {
                CircleIcon(
                    systemName: "gearshape",
                    fill: theme.surface,
                    symbol: theme.ink,
                    hairline: theme.cardHairline
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.top, safeTop + HeaderCollapse.headerTopPad)
        .frame(height: HeaderCollapse.overlayHeight(safeTop: safeTop))
    }
}

private struct ProfileTabPage: View {
    let tab: ProfileGridFilter
    let cards: [HomeCard]
    let loadState: LibraryLoadState
    let footerState: FeedFooterState
    let ownedIsEmpty: Bool
    let chromeHeight: CGFloat
    var scrollToTopToken = 0
    var shiningCardID: UUID? = nil
    var onInspire: () -> Void
    var onRetry: () -> Void
    var onRefresh: () async -> Void
    var onLoadMore: () -> Void
    var onRetryLoadMore: () -> Void
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard, Style) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void
    var onRemoveFromBoard: (HomeCard) -> Void
    var onReport: (HomeCard, ReportReason) -> Void
    var onBlock: (HomeCard) -> Void
    var onOpenAuthor: (HomeCard) -> Void
    var onOpenModel: (HomeCard) -> Void
    var onToggleFollow: (HomeCard) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var showsEmptyHero: Bool {
        guard case .loaded = loadState else {
            return false
        }

        return tab != .favorites && ownedIsEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            // Same cap as Home: space under the chrome, minus the 16-point list gap,
            // minus a peek of the next card. Favorites never receive it.
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
                            .id("profile-tab-top")

                        Color.clear
                            .frame(height: chromeHeight)

                        tabContent(tallCardMaxHeight: tallCardMaxHeight)
                            .padding(.bottom, 20)
                    }
                    .frame(
                        minHeight: proxy.size.height,
                        alignment: .top
                    )
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await onRefresh()
                }
                .onChange(of: scrollToTopToken) { _, token in
                    guard token > 0 else {
                        return
                    }
                    scrollListToTop(scrollProxy)
                    Task { @MainActor in
                        scrollListToTop(scrollProxy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollListToTop(_ proxy: ScrollViewProxy) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo("profile-tab-top", anchor: .top)
        }
    }

    @ViewBuilder
    private func tabContent(tallCardMaxHeight: CGFloat) -> some View {
        switch loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .accessibilityLabel("Loading cards")
        case .failed(let message):
            libraryError(message)
        case .loaded:
            if showsEmptyHero {
                ProfileEmptyLibraryHero(onInspire: onInspire)
            } else if cards.isEmpty {
                if footerState == .idle {
                    Text(tab.emptyCopy)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, HeaderCollapse.horizontalPadding)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    footer
                        .padding(.top, 16)
                }
            } else if tab == .favorites {
                VStack(spacing: 0) {
                    HomeCardGrid(
                        cards: cards,
                        rowSpacing: HeaderCollapse.horizontalPadding,
                        presentation: tab.presentation,
                        openingStyle: tab.matchingStyle,
                        onDelete: onDelete,
                        onToggleFavorite: onToggleFavorite,
                        onSetPublic: onSetPublic,
                        onRemoveFromBoard: onRemoveFromBoard,
                        onReport: onReport,
                        onBlock: onBlock,
                        onOpenAuthor: onOpenAuthor,
                        onToggleFollow: onToggleFollow,
                        onReachEnd: onLoadMore,
                        loadMorePrefetchDistance: 6,
                        offersOwnerPrivacyMenu: true
                    )
                    .equatable()
                    .padding(.horizontal, HeaderCollapse.horizontalPadding)
                    .padding(.top, 10)

                    footer
                }
            } else {
                VStack(spacing: 0) {
                    TallHomeCardGrid(
                        cards: cards,
                        cardMaxHeight: tallCardMaxHeight,
                        rowSpacing: HeaderCollapse.horizontalPadding,
                        openingStyle: tab.matchingStyle,
                        menuRole: { _ in .owner },
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
                        offersOwnerPrivacyMenu: true
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
        switch footerState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .accessibilityLabel("Loading more cards")
        case .failed:
            Button("Retry loading more", action: onRetryLoadMore)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }

    private func libraryError(_ message: String) -> some View {
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
        .accessibilityElement(children: .contain)
    }
}

private struct ProfileEmptyLibraryHero: View {
    var onInspire: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CircleIcon(
                systemName: "sparkle",
                fill: theme.paper,
                symbol: theme.ink,
                size: .big,
                weight: .semibold,
                hairline: theme.cardHairline
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Your library is empty")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Write what's stuck. We'll turn it into four angles.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onInspire) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Inspire me")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inspire me")
            .accessibilityHint("Opens the composer to write your first thought")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.cardHairline, lineWidth: 1)
        }
        .shadow(color: theme.shadowSoft, radius: 10, y: 3)
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Profile") {
    NavigationStack {
        ProfileView(
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            viewModel: HomeViewModel(),
            storeKitManager: StoreKitManager()
        )
    }
    .environmentObject(ThemeStore())
}
