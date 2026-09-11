import SwiftUI

struct FavoritesView: View {
    let viewModel: HomeViewModel
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard, Style) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }

    var body: some View {
        ProfileSubsetView(
            title: "Favorite angles",
            emptyCopy: "No favorite angles",
            loadingLabel: "Loading favorite angles",
            cards: viewModel.favoriteAngleCards,
            presentation: .favoriteAngles,
            loadState: viewModel.libraryLoadState,
            onRetry: viewModel.retryLoadLibrary,
            onDelete: onDelete,
            onToggleFavorite: onToggleFavorite,
            onSetPublic: onSetPublic,
            onRemoveFromBoard: onRemoveFromBoard
        )
    }
}
