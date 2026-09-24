import SwiftUI

struct ModelRoute: Hashable {
    let model: LlmModel
}

struct ModelProfileView: View {
    let route: ModelRoute
    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel
    let onOpenAuthor: (HomeCard) -> Void
    let onOpenModel: (HomeCard) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HomeFeedPager(
            safeAreaInsets: safeAreaInsets,
            cards: { tab in
                viewModel.modelCards(for: route.model, tab: tab)
            },
            loadState: viewModel.modelLoadState(for: route.model),
            footerState: viewModel.modelFooterState(for: route.model),
            emptyCopy: { tab in
                tab.emptyCopy(appliedFilter: HomeFeedFilter())
            },
            offersOwnerPrivacyMenu: true,
            onRetry: { viewModel.retryLoadModel(route.model) },
            onRefresh: { await viewModel.refreshModel(route.model) },
            onLoadMore: { viewModel.loadMoreModel(route.model) },
            onRetryLoadMore: { viewModel.retryLoadMoreModel(route.model) },
            onDelete: deleteCard,
            onToggleFavorite: toggleFavorite,
            onSetPublic: setPublic,
            onRemoveFromBoard: removeFromBoard,
            onOpenAuthor: onOpenAuthor,
            onOpenModel: onOpenModel,
            onToggleFollow: toggleFollow
        ) { pagerState, settledSelection, onSelectTab in
            ModelChrome(
                safeTop: safeAreaInsets.top,
                pagerState: pagerState,
                settledSelection: settledSelection,
                model: route.model,
                onBack: dismiss.callAsFunction,
                onSelectTab: onSelectTab
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .accessibilityAction(named: "Back") {
            dismiss()
        }
        .task(id: route.model) {
            await viewModel.loadModelIfNeeded(route.model)
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
}

private struct ModelChrome: View {
    let safeTop: CGFloat
    let pagerState: StyleTabPagerState<HomeFeedTab>
    let settledSelection: HomeFeedTab
    let model: LlmModel
    let onBack: () -> Void
    let onSelectTab: (HomeFeedTab) -> Void

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

                ModelLogo(model: model, side: 18)
                    .frame(
                        width: CircleIcon.Size.normal.side,
                        height: CircleIcon.Size.normal.side
                    )
                    .background(model.brandColor.opacity(0.12), in: Circle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(model.displayName)
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
