import SwiftUI

struct FavoritesView: View {
    @ObservedObject var viewModel: HomeViewModel
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard, Style) -> Void
    var onTogglePin: (HomeCard) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }

    var body: some View {
        ProfileSubsetView(
            title: "Favorite angles",
            emptyCopy: "No favorite angles",
            loadingLabel: "Loading favorite angles",
            cards: viewModel.favoriteAngleCards,
            presentation: .favoriteAngles,
            onDelete: onDelete,
            onToggleFavorite: onToggleFavorite,
            onTogglePin: onTogglePin,
            onSetPublic: onSetPublic,
            onRemoveFromBoard: onRemoveFromBoard,
            viewModel: viewModel
        )
    }
}

struct PinsView: View {
    @ObservedObject var viewModel: HomeViewModel
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard, Style) -> Void
    var onTogglePin: (HomeCard) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }

    var body: some View {
        ProfileSubsetView(
            title: "Pinned",
            emptyCopy: "No pinned posts",
            loadingLabel: "Loading pinned posts",
            cards: viewModel.pinnedCards,
            presentation: .pinned,
            onDelete: onDelete,
            onToggleFavorite: onToggleFavorite,
            onTogglePin: onTogglePin,
            onSetPublic: onSetPublic,
            onRemoveFromBoard: onRemoveFromBoard,
            viewModel: viewModel
        )
    }
}
