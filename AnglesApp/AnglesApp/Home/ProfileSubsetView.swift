import SwiftUI

struct ProfileSubsetView: View {
    let title: String
    let emptyCopy: String
    let loadingLabel: String
    let cards: [HomeCard]
    let presentation: ReframeCardPresentation
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard, Style) -> Void
    var onTogglePin: (HomeCard) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void

    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Group {
            switch viewModel.libraryLoadState {
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
                        viewModel.retryLoadLibrary()
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
                        HomeCardGrid(
                            cards: cards,
                            usesSingleColumn: dynamicTypeSize.isAccessibilitySize,
                            columnSpacing: 12,
                            rowSpacing: 16,
                            presentation: presentation,
                            onDelete: onDelete,
                            onToggleFavorite: onToggleFavorite,
                            onTogglePin: onTogglePin,
                            onSetPublic: onSetPublic
                        )
                        .equatable()
                        .padding(.horizontal, 16)
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
