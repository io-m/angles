import SwiftUI

struct ProfileSubsetView: View {
    let title: String
    let emptyCopy: String
    let loadingLabel: String
    let cards: [HomeCard]
    let presentation: ReframeCardPresentation
    var openingStyle: Style? = nil
    var loadState: LibraryLoadState? = nil
    var onRetry: (() -> Void)? = nil
    var menuRole: ((HomeCard) -> ReframeCardMenuRole)? = nil
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard, Style) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }
    /// Set by shelves that page the server instead of holding the whole list.
    var onLoadMore: (() -> Void)? = nil
    var isLoadingMore = false

    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var resolvedState: LibraryLoadState {
        loadState ?? viewModel.libraryLoadState
    }

    var body: some View {
        Group {
            switch resolvedState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(loadingLabel)
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.muted)
                    Button("Retry") {
                        if let onRetry {
                            onRetry()
                        } else {
                            viewModel.retryLoadLibrary()
                        }
                    }
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
                                usesSingleColumn: dynamicTypeSize.isAccessibilitySize,
                                columnSpacing: 12,
                                rowSpacing: 16,
                                presentation: presentation,
                                openingStyle: openingStyle,
                                menuRole: menuRole ?? { card in card.isOwner ? .owner : .savedFromFeed },
                                onDelete: onDelete,
                                onToggleFavorite: onToggleFavorite,
                                onSetPublic: onSetPublic,
                                onRemoveFromBoard: onRemoveFromBoard,
                                onReachEnd: onLoadMore
                            )
                            .equatable()
                            .padding(.horizontal, 16)

                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 16)
                                    .accessibilityLabel(loadingLabel)
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
