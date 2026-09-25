import SwiftUI

struct AuthorRoute: Hashable, Identifiable {
    let id: UUID
    let initials: String
    let avatarPath: String?
    let isSelf: Bool
}

struct AuthorProfileView: View {
    let route: AuthorRoute
    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel
    let onOpenAuthor: (HomeCard) -> Void
    let onOpenModel: (HomeCard) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showBlockConfirm = false

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

    var body: some View {
        HomeFeedPager(
            safeAreaInsets: safeAreaInsets,
            cards: { tab in
                viewModel.authorCards(for: route.id, tab: tab)
            },
            loadState: viewModel.authorLoadState(for: route.id),
            footerState: viewModel.authorFooterState(for: route.id),
            emptyCopy: { tab in
                tab.emptyCopy(appliedFilter: HomeFeedFilter())
            },
            onRetry: { viewModel.retryLoadAuthor(route.id) },
            onRefresh: { await viewModel.refreshAuthor(route.id) },
            onLoadMore: { viewModel.loadMoreAuthor(route.id) },
            onRetryLoadMore: { viewModel.retryLoadMoreAuthor(route.id) },
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
            AuthorChrome(
                safeTop: safeAreaInsets.top,
                pagerState: pagerState,
                settledSelection: settledSelection,
                header: header,
                onBack: dismiss.callAsFunction,
                onSelectTab: onSelectTab,
                onToggleFollow: { viewModel.toggleFollow(route.id) },
                onRequestBlock: { showBlockConfirm = true }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .accessibilityAction(named: "Back") {
            dismiss()
        }
        .task(id: route.id) {
            await viewModel.loadAuthorIfNeeded(route)
        }
        .confirmationDialog(
            "Block \(displayInitials)?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive, action: blockRouteAuthor)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their posts will disappear, and you won't be able to follow each other.")
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
        if card.isOwner {
            viewModel.setPublic(card.id, isPublic: isPublic)
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

    private func blockRouteAuthor() {
        guard !header.isSelf else { return }
        viewModel.blockAuthor(
            route.id,
            initials: header.initials,
            avatarPath: header.avatarPath
        )
    }

    private var displayInitials: String {
        let trimmed = header.initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this person" : trimmed
    }
}

private struct AuthorChrome: View {
    let safeTop: CGFloat
    let pagerState: StyleTabPagerState<HomeFeedTab>
    let settledSelection: HomeFeedTab
    let header: AuthorHeader
    let onBack: () -> Void
    let onSelectTab: (HomeFeedTab) -> Void
    let onToggleFollow: () -> Void
    let onRequestBlock: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: safeTop + HeaderCollapse.headerTopPad)
                .allowsHitTesting(false)

            ZStack(alignment: .trailing) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: onBack) {
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

                    AdaptiveStyleTabBar(
                        pagerState: pagerState,
                        settledSelection: settledSelection,
                        reservedTrailingWidth: CircleIcon.Size.normal.side,
                        includesTrailingSpacer: true,
                        padded: false,
                        onSelect: onSelectTab
                    )
                }
                .frame(maxWidth: .infinity)

                ZStack(alignment: .bottomTrailing) {
                    if header.isSelf {
                        authorMark
                    } else {
                        Menu {
                            Button(role: .destructive, action: onRequestBlock) {
                                Label("Block", systemImage: "hand.raised")
                            }
                        } label: {
                            authorMark
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Author actions")
                        .accessibilityHint("Includes block")
                    }

                    if !header.isSelf {
                        FollowBadge(
                            following: header.following,
                            action: onToggleFollow
                        )
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
        .frame(
            height: HomeFeedPagerMetrics.chromeHeight(safeTop: safeTop),
            alignment: .top
        )
        .background {
            StyleTabChromeBackground(pagerState: pagerState)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var authorMark: some View {
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
    }
}
