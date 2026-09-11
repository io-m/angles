import SwiftUI

/// One Home shelf in full. Seeded with the shelf's cards, then paged from the server with
/// the existing `before` cursor — Home never fetches more than the shelves need.
struct FeedSubsetView: View {
    let shelf: FeedShelf

    let viewModel: HomeViewModel

    var body: some View {
        let state = viewModel.feedSubset(shelf)
        // The shelf's own cards are already in hand, so the push renders content, not a spinner.
        let cards = state.cards.isEmpty ? viewModel.feedSectionCards(shelf) : state.cards
        let loadState: LibraryLoadState = cards.isEmpty ? state.loadState : .loaded

        return ProfileSubsetView(
            title: shelf.title,
            emptyCopy: shelf.emptyCopy,
            loadingLabel: "Loading \(shelf.title)",
            cards: cards,
            presentation: .library,
            openingStyle: viewModel.homeGridFilter.matchingStyle,
            loadState: loadState,
            onRetry: { viewModel.retryFeedSubset(shelf) },
            menuRole: { _ in .feed },
            onDelete: { _ in },
            onToggleFavorite: { card, style in viewModel.toggleFavorite(card.id, style: style) },
            onSetPublic: { _, _ in },
            onRemoveFromBoard: { _ in },
            onLoadMore: { viewModel.loadMoreFeedSubset(shelf) },
            usesPagination: true,
            isLoadingMore: state.isLoadingMore
        )
        .task {
            await viewModel.loadFeedSubsetIfNeeded(shelf)
        }
    }
}
