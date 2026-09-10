import SwiftUI

struct FavoritesView: View {
    @ObservedObject var viewModel: HomeViewModel
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Group {
            if viewModel.favoriteCards.isEmpty {
                Text("No favorites")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    HomeCardGrid(
                        cards: viewModel.favoriteCards,
                        usesSingleColumn: dynamicTypeSize.isAccessibilitySize,
                        spacing: 12,
                        onDelete: onDelete,
                        onToggleFavorite: onToggleFavorite
                    )
                    .equatable()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AnglesCanvasBackground())
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(theme.ink)
    }
}
