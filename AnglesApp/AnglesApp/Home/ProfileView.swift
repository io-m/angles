import SwiftUI

struct ProfileView: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let gridSpacing: CGFloat = 12
        static let headerHeight: CGFloat = 44
        static let headerTopPad: CGFloat = 6
        static let headerContentGap: CGFloat = 18
    }

    let safeAreaInsets: EdgeInsets

    @ObservedObject var viewModel: HomeViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var favoriteRowHeight: CGFloat = 252

    @State private var showFilterPicker = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var headerOverlayHeight: CGFloat {
        safeAreaInsets.top + Layout.headerTopPad + Layout.headerHeight
    }

    private var scrollTopInset: CGFloat {
        headerOverlayHeight + Layout.headerContentGap
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                AnglesCanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !viewModel.favoriteCards.isEmpty {
                            favoritesSection(pageWidth: geometry.size.width)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        gridSection
                    }
                    .padding(.top, scrollTopInset)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)

                headerChrome
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
    }

    private var headerChrome: some View {
        ZStack(alignment: .top) {
            headerFade

            header
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, safeAreaInsets.top + Layout.headerTopPad)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            InitialsAvatar(side: 40, fill: theme.ink, symbol: theme.paper)

            Spacer(minLength: 0)

            filterButton
        }
        .frame(minHeight: Layout.headerHeight, alignment: .center)
    }

    private var filterButton: some View {
        Button {
            showFilterPicker = true
        } label: {
            CircleIcon(
                systemName: filterSystemImage(viewModel.profileGridFilter),
                fill: theme.surface,
                symbol: filterSymbolColor(viewModel.profileGridFilter),
                hairline: theme.cardHairline
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter")
        .accessibilityValue(viewModel.profileGridFilter.title)
        .popover(isPresented: $showFilterPicker, arrowEdge: .top) {
            filterPicker
                .presentationCompactAdaptation(.popover)
        }
    }

    private var filterPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ProfileGridFilter.allCases, id: \.self) { filter in
                let isSelected = viewModel.profileGridFilter == filter

                Button {
                    viewModel.profileGridFilter = filter
                    showFilterPicker = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: filterSystemImage(filter))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(filterSymbolColor(filter))
                            .frame(width: 22, alignment: .center)

                        Text(filter.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.ink)

                        Spacer(minLength: 12)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.ink)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)

                if filter != ProfileGridFilter.allCases.last {
                    Rectangle()
                        .fill(theme.line)
                        .frame(height: 1)
                        .padding(.leading, 50)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minWidth: 220)
        .background(theme.surface)
    }

    private func filterSystemImage(_ filter: ProfileGridFilter) -> String {
        guard let style = filter.matchingStyle else {
            return "square.grid.2x2"
        }

        return CardStyleAppearance(style: style).systemImage
    }

    private func filterSymbolColor(_ filter: ProfileGridFilter) -> Color {
        guard let style = filter.matchingStyle else {
            return theme.ink
        }

        return CardStyleAppearance(style: style).ink
    }

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.profileGridFilter.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.ink)
                .padding(.horizontal, Layout.horizontalPadding)
                .accessibilityAddTraits(.isHeader)

            if viewModel.filteredProfileCards.isEmpty {
                Text(emptyFilterMessage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, Layout.horizontalPadding)
                    .padding(.top, 8)
            } else {
                HomeCardGrid(
                    cards: viewModel.filteredProfileCards,
                    usesSingleColumn: dynamicTypeSize.isAccessibilitySize,
                    spacing: Layout.gridSpacing,
                    onDelete: deleteCard,
                    onToggleFavorite: toggleFavorite
                )
                .equatable()
                .padding(.horizontal, Layout.horizontalPadding)
            }
        }
    }

    private var emptyFilterMessage: String {
        switch viewModel.profileGridFilter {
        case .all:
            return "No cards yet"
        case .stoic, .optimistic, .humorous, .toughLove:
            return "No \(viewModel.profileGridFilter.title) cards yet"
        }
    }

    private func favoritesSection(pageWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                FavoritesView(
                    viewModel: viewModel,
                    onDelete: deleteCard,
                    onToggleFavorite: toggleFavorite
                )
            } label: {
                HStack(spacing: 6) {
                    Text("Favorites")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.ink)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.muted)

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Layout.horizontalPadding)
            .accessibilityHint("Shows all favorite cards")

            ScrollView(.horizontal) {
                HStack(spacing: Layout.gridSpacing) {
                    ForEach(viewModel.stripFavoriteCards) { card in
                        ReframeCardView(
                            card: card,
                            onDelete: { deleteCard(card) },
                            onToggleFavorite: { toggleFavorite(card) }
                        )
                        .frame(width: min(pageWidth * 0.78, 300))
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            )
                        )
                    }
                }
                .padding(.leading, Layout.horizontalPadding)
                .padding(.trailing, Layout.horizontalPadding)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(height: favoriteRowHeight)
        }
    }

    private var headerFade: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: theme.paper.opacity(0.86), location: 0),
                Gradient.Stop(color: theme.paper.opacity(0.43), location: 0.55),
                Gradient.Stop(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: headerOverlayHeight + 12)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func deleteCard(_ card: HomeCard) {
        withAnimation(.easeInOut(duration: 0.22)) {
            viewModel.deleteCard(card.id)
        }
    }

    private var favoriteLayoutAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private func toggleFavorite(_ card: HomeCard) {
        withAnimation(favoriteLayoutAnimation) {
            viewModel.toggleFavorite(card.id)
        }
    }
}

#Preview("Profile") {
    NavigationStack {
        ProfileView(
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            viewModel: HomeViewModel()
        )
    }
    .environmentObject(ThemeStore())
}
