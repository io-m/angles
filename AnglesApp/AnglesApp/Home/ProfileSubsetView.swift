import SwiftUI

struct ProfileSubsetView: View {
    let title: String
    let emptyCopy: String
    let loadingLabel: String
    let cards: [HomeCard]
    let presentation: ReframeCardPresentation
    var openingStyle: Style? = nil
    let loadState: LibraryLoadState
    let onRetry: () -> Void
    var menuRole: ((HomeCard) -> ReframeCardMenuRole)? = nil
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard, Style) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }
    /// Optional support for a server-paged grid.
    var onLoadMore: (() -> Void)? = nil
    var usesPagination = false
    var isLoadingMore = false

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(loadingLabel)
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.muted)
                    Button("Retry", action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if cards.isEmpty {
                    Text(emptyCopy)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            HomeCardGrid(
                                cards: cards,
                                rowSpacing: HeaderCollapse.horizontalPadding,
                                presentation: presentation,
                                openingStyle: openingStyle,
                                menuRole: menuRole ?? { card in card.isOwner ? .owner : .savedFromFeed },
                                onDelete: onDelete,
                                onToggleFavorite: onToggleFavorite,
                                onSetPublic: onSetPublic,
                                onRemoveFromBoard: onRemoveFromBoard,
                                onReachEnd: onLoadMore,
                                loadMorePrefetchDistance: usesPagination ? 6 : 0
                            )
                            .equatable()
                            .padding(.horizontal, 16)

                            if usesPagination {
                                ProgressView()
                                    .opacity(isLoadingMore ? 1 : 0)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .accessibilityLabel(loadingLabel)
                                    .accessibilityHidden(!isLoadingMore)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AnglesCanvasBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(theme.ink)
    }
}
