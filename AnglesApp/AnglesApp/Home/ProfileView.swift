import Observation
import SwiftUI

struct ProfileView: View {

    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore? = nil
    /// Filled from Sign in with Apple / Better Auth in row 8. Nil keeps the session label.
    var displayName: String? = nil
    var onInspire: () -> Void = {}
    var onLogOut: (() -> Void)? = nil
    var onDeleteAccount: (() async -> AccountDeletion)? = nil
    var canLoadFullAppContent = false
    var onOpenAuthor: (HomeCard) -> Void = { _ in }
    var onOpenFollowed: (FollowedPerson) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var pagerState = StyleTabPagerState<ProfileGridFilter>(initialTab: .hearts)
    @State private var showSettings = false
    @State private var showFollowing = false
    /// A follow push opens People on Notifications. The icon opens Following.
    @State private var peopleStartsOnNotifications = false
    @State private var committedTab: ProfileGridFilter = .hearts
    /// Lists that have been shown. The rest are empty placeholders until first chosen.
    @State private var visitedTabs: Set<ProfileGridFilter> = [.hearts]

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var fixedChromeHeight: CGFloat {
        HomeFeedPagerMetrics.chromeHeight(safeTop: safeAreaInsets.top)
    }

    private var profileTitle: String {
        if let identityStore {
            return identityStore.profileTitle
        }
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "On this iPhone" : trimmed
    }

    var body: some View {
        let _ = RenderCounter.hit("ProfileView")
        // Read the photo here so the header updates when the server copy arrives after sign-in.
        let _ = identityStore?.photo
        ZStack(alignment: .top) {
            StyleTabPageBackground(pagerState: pagerState)
                .ignoresSafeArea()

            pager
                .ignoresSafeArea(edges: .top)

            ProfileChrome(
                title: profileTitle,
                safeTop: safeAreaInsets.top,
                pagerState: pagerState,
                settledSelection: committedTab,
                showSettings: $showSettings,
                identityStore: identityStore,
                hasUnreadFollows: viewModel.unreadFollowCount > 0,
                onOpenFollowing: { showFollowing = true },
                onSelectTab: selectTab
            )
            .ignoresSafeArea(edges: .top)

            FeedRefreshBanner(
                outcome: viewModel.libraryRefreshOutcome,
                token: viewModel.libraryRefreshToken,
                noun: "card",
                onConsumed: { viewModel.consumeLibraryRefreshBanner() }
            )
            .padding(.top, fixedChromeHeight + 8)
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
            await viewModel.loadFollowNotifications()
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
                    let result = await onDeleteAccount?() ?? .failed
                    if result == .deleted {
                        showSettings = false
                    }
                    return result
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
                notices: viewModel.followNotices,
                loadState: viewModel.followingLoadState,
                noticesLoadState: viewModel.followNoticesLoadState,
                startsOnNotifications: peopleStartsOnNotifications || viewModel.unreadFollowCount > 0,
                onRetry: {
                    Task {
                        await viewModel.loadFollowing()
                        await viewModel.loadFollowNotifications()
                    }
                },
                onViewNotifications: { viewModel.openedFollowNotifications() },
                onUnfollow: { person in
                    viewModel.unfollow(person)
                },
                onFollowBack: { notice in
                    viewModel.followBack(notice.actorId)
                },
                onOpen: { person in
                    showFollowing = false
                    onOpenFollowed(person)
                },
                onOpenNotice: { notice in
                    showFollowing = false
                    onOpenFollowed(
                        FollowedPerson(
                            id: notice.actorId,
                            initials: notice.initials,
                            avatarPath: notice.avatarPath
                        )
                    )
                },
                writeError: viewModel.writeError,
                onDismissError: viewModel.dismissWriteError
            )
            .task {
                async let following: Void = viewModel.loadFollowing()
                async let notices: Void = viewModel.loadFollowNotifications()
                _ = await (following, notices)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.grey)
            .modifier(UserAppearance(store: themeStore))
        }
        .onChange(of: viewModel.openFollowNotificationsToken) { _, _ in
            peopleStartsOnNotifications = true
            showFollowing = true
        }
        .onChange(of: showFollowing) { _, showing in
            if !showing {
                peopleStartsOnNotifications = false
            }
        }
    }

    private var pager: some View {
        GeometryReader { _ in
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(ProfileGridFilter.allCases, id: \.self) { tab in
                            // Built the first time it is chosen, then kept; the others stay
                            // empty so a list is not sorted and laid out for every style.
                            Group {
                            if visitedTabs.contains(tab) {
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
                                onToggleHeart: toggleHeart,
                                onSetPublic: setPublic,
                                onRemoveFromBoard: removeFromBoard,
                                onReport: reportCard,
                                onBlock: blockAuthor,
                                onOpenAuthor: onOpenAuthor,
                                onToggleFollow: toggleFollow
                            )
                            } else {
                                Color.clear
                            }
                            }
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(tab)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // Styles are picked from the menu, never by dragging sideways. The vertical
                // lists in each page switch scrolling back on below.
                .scrollDisabled(true)
                .onChange(of: pagerState.requestSerial) { _, _ in
                    // The strip jumps; the chrome does the cross-fade (StyleTabPagerState).
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
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
            visitedTabs.insert(filter)
            committedTab = filter
            if viewModel.profileGridFilter != filter {
                viewModel.profileGridFilter = filter
            }
        }
        pagerState.requestPage(filter, animation: nil)
    }

    private func selectTab(_ filter: ProfileGridFilter) {
        guard filter != committedTab else {
            return
        }
        // Committed at the pick, not after a scroll settles: there is no scroll to wait for.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visitedTabs.insert(filter)
            committedTab = filter
            if filter != viewModel.profileGridFilter {
                viewModel.profileGridFilter = filter
            }
        }
        pagerState.requestPage(filter, animation: tabAnimation)
    }

    private func deleteCard(_ card: HomeCard) {
        guard card.isOwner else {
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            viewModel.deleteCard(card.id)
        }
    }

    private var heartLayoutAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private func toggleHeart(_ card: HomeCard, _ style: Style) {
        withAnimation(heartLayoutAnimation) {
            viewModel.toggleHeart(card.id, style: style)
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
        withAnimation(heartLayoutAnimation) {
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
    let pagerState: StyleTabPagerState<ProfileGridFilter>
    let settledSelection: ProfileGridFilter
    @Binding var showSettings: Bool
    var identityStore: ProfileIdentityStore? = nil
    var hasUnreadFollows = false
    var onOpenFollowing: () -> Void = {}
    let onSelectTab: (ProfileGridFilter) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProfileTopBar(
                title: title,
                safeTop: safeTop,
                pagerState: pagerState,
                settledSelection: settledSelection,
                showSettings: $showSettings,
                identityStore: identityStore,
                hasUnreadFollows: hasUnreadFollows,
                onOpenFollowing: onOpenFollowing,
                onSelectTab: onSelectTab
            )
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

private enum ProfileViewAvatar {
    static let large: CGFloat = 76
    static let compact: CGFloat = 28
}

private struct ProfileTopBar: View {
    let title: String
    let safeTop: CGFloat
    let pagerState: StyleTabPagerState<ProfileGridFilter>
    let settledSelection: ProfileGridFilter
    @Binding var showSettings: Bool
    var identityStore: ProfileIdentityStore? = nil
    var hasUnreadFollows = false
    var onOpenFollowing: () -> Void = {}
    let onSelectTab: (ProfileGridFilter) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: safeTop + HeaderCollapse.headerTopPad)
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 12) {
                ProfileAvatar(
                    identityStore: identityStore,
                    letters: UserInitials.letters,
                    side: ProfileViewAvatar.compact,
                    fill: theme.ink,
                    symbol: theme.paper
                )
                .accessibilityHidden(true)

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(-1)
                    .accessibilityAddTraits(.isHeader)

                AdaptiveStyleTabBar(
                    pagerState: pagerState,
                    settledSelection: settledSelection,
                    includesTrailingSpacer: true,
                    padded: false,
                    onSelect: onSelectTab
                )

                Button(action: onOpenFollowing) {
                    CircleIcon(
                        systemName: "person.2",
                        fill: theme.surface,
                        symbol: theme.ink,
                        hairline: theme.cardHairline
                    )
                    .overlay(alignment: .topTrailing) {
                        if hasUnreadFollows {
                            Circle()
                                .fill(theme.ink)
                                .frame(width: 8, height: 8)
                                .offset(x: 1, y: -1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasUnreadFollows ? "People, new" : "People")

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
            .frame(height: HeaderCollapse.headerHeight)

            Color.clear
                .frame(height: StyleTabMetrics.chromeBottomInset)
                .allowsHitTesting(false)
        }
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
    var onToggleHeart: (HomeCard, Style) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void
    var onRemoveFromBoard: (HomeCard) -> Void
    var onReport: (HomeCard, ReportReason) -> Void
    var onBlock: (HomeCard) -> Void
    var onOpenAuthor: (HomeCard) -> Void
    var onToggleFollow: (HomeCard) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var showsEmptyHero: Bool {
        guard case .loaded = loadState else {
            return false
        }

        return tab != .hearts && ownedIsEmpty
    }

    var body: some View {
        let _ = RenderCounter.hit("ProfileTabPage")
        GeometryReader { proxy in
            // Same cap as Home: space under the chrome, minus the 16-point list gap,
            // minus a peek of the next card. Hearts never receive it.
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

                        tabContent(tallCardMaxHeight: tallCardMaxHeight)
                            .padding(.bottom, 20)
                    }
                    .frame(
                        minHeight: viewportBelowChrome,
                        alignment: .top
                    )
                }
                // A real top inset rather than a spacer inside the content:
                // cards still scroll up behind the glass header, but the
                // native refresh control emerges below it.
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear
                        .frame(height: chromeHeight)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.always)
                .scrollDisabled(false)
                .modifier(
                    HomeFeedNativeRefresh(
                        enabled: true,
                        onRefresh: onRefresh
                    )
                )
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
            } else if tab == .hearts {
                VStack(spacing: 0) {
                    HomeCardGrid(
                        cards: cards,
                        rowSpacing: HeaderCollapse.horizontalPadding,
                        presentation: tab.presentation,
                        openingStyle: tab.matchingStyle,
                        onDelete: onDelete,
                        onToggleHeart: onToggleHeart,
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
                        onToggleHeart: onToggleHeart,
                        onSetPublic: onSetPublic,
                        onRemoveFromBoard: onRemoveFromBoard,
                        onReport: onReport,
                        onBlock: onBlock,
                        shiningCardID: shiningCardID,
                        onOpenAuthor: onOpenAuthor,
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
            InspireMarkCircle(
                fill: theme.paper,
                markSize: .big,
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
                    InspireMark(size: 18, rendering: .monochrome(theme.paper))
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
