import SwiftUI

struct ProfileView: View {
    private enum Layout {
        static let gridColumnSpacing: CGFloat = 12
        static let gridRowSpacing: CGFloat = 16
        static let greetings = ["Hey", "Welcome back", "Hi there", "Good to see you"]
    }

    let safeAreaInsets: EdgeInsets
    let pageWidth: CGFloat

    @ObservedObject var viewModel: HomeViewModel
    var onInspire: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cardRowHeight: CGFloat = ReframeCardMetrics.baseHeight

    @State private var scrolledDistance: CGFloat = 0
    @State private var showRestFilter = false
    @State private var showCollapsedFilter = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var headerOverlayHeight: CGFloat {
        HeaderCollapse.overlayHeight(safeTop: safeAreaInsets.top)
    }

    private var greeting: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return Layout.greetings[(day - 1) % Layout.greetings.count]
    }

    private var restProgress: CGFloat {
        HeaderCollapse.restProgress(scrolledDistance, reduceMotion: reduceMotion)
    }

    private var restOpacity: CGFloat {
        1 - restProgress
    }

    private var collapsedProgress: CGFloat {
        HeaderCollapse.collapsedProgress(scrolledDistance, reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AnglesCanvasBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: HeaderCollapse.headerContentGap) {
                    scrollingHeader

                    pinnedAndFavorites

                    gridSection
                }
                .padding(.top, safeAreaInsets.top + HeaderCollapse.headerTopPad)
                .padding(.bottom, 20)
                .background(alignment: .top) {
                    ScrollDistanceProbe(space: "profileScroll")
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "profileScroll")
            .modifier(ProfileScrollDistance(distance: $scrolledDistance))

            headerFade

            collapsedHeader
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .task {
            await viewModel.loadLibraryIfNeeded()
        }
    }

    private var scrollingHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(greeting)
                .font(.title.bold())
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Button {
                showRestFilter = true
            } label: {
                CircleIcon(
                    systemName: filterSystemImage(viewModel.profileGridFilter),
                    fill: theme.surface,
                    symbol: filterSymbolColor(viewModel.profileGridFilter, ink: theme.ink),
                    weight: .semibold,
                    hairline: theme.cardHairline
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter")
            .accessibilityValue(viewModel.profileGridFilter.title)
            .popover(isPresented: $showRestFilter, arrowEdge: .top) {
                filterPicker
                    .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .frame(minHeight: HeaderCollapse.headerHeight, alignment: .center)
        .opacity(restOpacity)
        .animation(nil, value: scrolledDistance)
        .allowsHitTesting(restOpacity > 0.4)
        .accessibilityHidden(restOpacity <= 0.4)
    }

    private var collapsedHeader: some View {
        let progress = collapsedProgress

        return VStack(spacing: 0) {
            Color.clear
                .frame(height: safeAreaInsets.top + HeaderCollapse.headerTopPad)
                .allowsHitTesting(false)

            HStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                Button {
                    showCollapsedFilter = true
                } label: {
                    CollapsedFilterLabel(filter: viewModel.profileGridFilter)
                }
                .buttonStyle(.plain)
                .opacity(progress)
                .offset(y: reduceMotion ? 0 : HeaderCollapse.collapseSlide * (1 - progress))
                .animation(nil, value: scrolledDistance)
                .accessibilityLabel("Filter")
                .accessibilityValue(viewModel.profileGridFilter.title)
                .accessibilityHidden(progress <= 0.4)
                .popover(isPresented: $showCollapsedFilter, arrowEdge: .top) {
                    filterPicker
                        .presentationCompactAdaptation(.popover)
                }
                .allowsHitTesting(progress > 0.4)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .frame(height: HeaderCollapse.headerHeight)
        }
        .frame(height: headerOverlayHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(progress > 0.4)
    }

    private var filterPicker: some View {
        GridFilterPicker(selection: viewModel.profileGridFilter) { filter in
            viewModel.profileGridFilter = filter
            showRestFilter = false
            showCollapsedFilter = false
        }
    }

    private var showsEmptyHero: Bool {
        guard case .loaded = viewModel.libraryLoadState else {
            return false
        }

        return viewModel.profileGridFilter == .all && viewModel.ownedCards.isEmpty
    }

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !showsEmptyHero {
                librarySubtitle
            }

            switch viewModel.libraryLoadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .accessibilityLabel("Loading cards")
            case .failed(let message):
                libraryError(message)
            case .loaded:
                if showsEmptyHero {
                    emptyLibraryHero
                } else if viewModel.filteredProfileCards.isEmpty {
                    emptyFilterCopy
                } else {
                    HomeCardGrid(
                        cards: viewModel.filteredProfileCards,
                        usesSingleColumn: dynamicTypeSize.isAccessibilitySize,
                        columnSpacing: Layout.gridColumnSpacing,
                        rowSpacing: Layout.gridRowSpacing,
                        presentation: .library,
                        openingStyle: viewModel.profileGridFilter.matchingStyle,
                        onDelete: deleteCard,
                        onToggleFavorite: toggleFavorite,
                        onTogglePin: togglePinned,
                        onSetPublic: setPublic,
                        onRemoveFromBoard: removeFromBoard
                    )
                    .equatable()
                    .padding(.horizontal, HeaderCollapse.horizontalPadding)
                }
            }
        }
    }

    private var emptyLibraryHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            CircleIcon(
                systemName: "sparkle",
                fill: theme.paper,
                symbol: theme.ink,
                size: .big,
                weight: .semibold,
                hairline: theme.cardHairline
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Your library is empty")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Write what's stuck. We'll turn it into four angles.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onInspire) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Inspire me")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inspire me")
            .accessibilityHint("Opens the composer to write your first thought")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.cardHairline, lineWidth: 1)
        }
        .shadow(color: theme.shadowSoft, radius: 10, y: 3)
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var emptyFilterCopy: some View {
        Text(emptyFilterMessage)
            .font(.body.weight(.medium))
            .foregroundStyle(theme.muted)
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
            .padding(.top, 8)
    }

    private func libraryError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.muted)
            Button("Retry") {
                viewModel.retryLoadLibrary()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.ink)
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var pinnedAndFavorites: some View {
        if case .loaded = viewModel.libraryLoadState {
            VStack(alignment: .leading, spacing: HeaderCollapse.headerContentGap) {
                if !viewModel.pinnedCards.isEmpty {
                    pinnedSection
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !viewModel.favoriteAngleCards.isEmpty {
                    favoriteAnglesSection
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var emptyFilterMessage: String {
        switch viewModel.profileGridFilter {
        case .all:
            return "No cards yet"
        case .stoic, .optimistic, .humorous, .toughLove:
            return "No cards with a \(viewModel.profileGridFilter.title) angle yet"
        }
    }

    private var librarySubtitle: some View {
        HStack(spacing: 10) {
            CircleIcon(
                systemName: filterSystemImage(viewModel.profileGridFilter),
                fill: theme.surface,
                symbol: filterSymbolColor(viewModel.profileGridFilter, ink: theme.ink),
                weight: .semibold,
                hairline: theme.cardHairline
            )

            Text(viewModel.profileGridFilter.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(viewModel.profileGridFilter.title)
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: HeaderCollapse.sectionContentGap) {
            subsetSectionTitle("Pinned", hint: "Shows all pinned posts") {
                PinsView(
                    viewModel: viewModel,
                    onDelete: deleteCard,
                    onToggleFavorite: toggleFavorite,
                    onTogglePin: togglePinned,
                    onSetPublic: setPublic,
                    onRemoveFromBoard: removeFromBoard
                )
            }

            HomeCardStrip(
                cards: viewModel.stripPinnedCards,
                pageWidth: pageWidth,
                presentation: .pinned,
                cardRowHeight: cardRowHeight,
                onDelete: deleteCard,
                onToggleFavorite: toggleFavorite,
                onTogglePin: togglePinned,
                onSetPublic: setPublic,
                onRemoveFromBoard: removeFromBoard
            )
            .equatable()
        }
    }

    private var favoriteAnglesSection: some View {
        VStack(alignment: .leading, spacing: HeaderCollapse.sectionContentGap) {
            subsetSectionTitle("Favorite angles", hint: "Shows all favorite angles") {
                FavoritesView(
                    viewModel: viewModel,
                    onDelete: deleteCard,
                    onToggleFavorite: toggleFavorite,
                    onTogglePin: togglePinned,
                    onSetPublic: setPublic,
                    onRemoveFromBoard: removeFromBoard
                )
            }

            HomeCardStrip(
                cards: viewModel.stripFavoriteCards,
                pageWidth: pageWidth,
                presentation: .favoriteAngles,
                cardRowHeight: cardRowHeight,
                onDelete: deleteCard,
                onToggleFavorite: toggleFavorite,
                onTogglePin: togglePinned,
                onSetPublic: setPublic,
                onRemoveFromBoard: removeFromBoard
            )
            .equatable()
        }
    }

    private func subsetSectionTitle<Destination: View>(
        _ title: String,
        hint: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.muted)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint(hint)
    }

    private var headerFade: some View {
        let progress = restProgress

        return VStack(spacing: 0) {
            theme.paper
                .frame(height: safeAreaInsets.top)

            LinearGradient(
                stops: [
                    Gradient.Stop(color: theme.paper.opacity(progress), location: 0),
                    Gradient.Stop(color: theme.paper.opacity(0.88 * progress), location: 0.52),
                    Gradient.Stop(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: HeaderCollapse.headerTopPad + HeaderCollapse.headerHeight + 12)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(nil, value: scrolledDistance)
    }

    private func deleteCard(_ card: HomeCard) {
        guard card.isOwner else {
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            viewModel.deleteCard(card.id)
        }
    }

    private var favoriteLayoutAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private func toggleFavorite(_ card: HomeCard, _ style: Style) {
        withAnimation(favoriteLayoutAnimation) {
            viewModel.toggleFavorite(card.id, style: style)
        }
    }

    private func togglePinned(_ card: HomeCard) {
        withAnimation(favoriteLayoutAnimation) {
            viewModel.togglePinned(card.id)
        }
    }

    private func setPublic(_ card: HomeCard, _ isPublic: Bool) {
        viewModel.setPublic(card.id, isPublic: isPublic)
    }

    private func removeFromBoard(_ card: HomeCard) {
        withAnimation(favoriteLayoutAnimation) {
            viewModel.removeFromBoard(card.id)
        }
    }
}

#Preview("Profile") {
    NavigationStack {
        ProfileView(
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            pageWidth: 393,
            viewModel: HomeViewModel()
        )
    }
    .environmentObject(ThemeStore())
}
