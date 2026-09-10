import SwiftUI

private struct ScrollDistanceKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

struct ProfileView: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let gridSpacing: CGFloat = 12
        static let headerHeight: CGFloat = 44
        static let headerTopPad: CGFloat = 6
        static let headerContentGap: CGFloat = 18
        static let restFadeDistance: CGFloat = 44
        static let collapsedRevealDistance: CGFloat = 36
        static let collapseSlide: CGFloat = 10
        static let greetings = ["Hey", "Welcome back", "Hi there", "Good to see you"]
    }

    let safeAreaInsets: EdgeInsets

    @ObservedObject var viewModel: HomeViewModel
    var onInspire: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var favoriteRowHeight: CGFloat = 252

    @State private var scrolledDistance: CGFloat = 0
    @State private var showRestFilter = false
    @State private var showCollapsedFilter = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var headerOverlayHeight: CGFloat {
        safeAreaInsets.top + Layout.headerTopPad + Layout.headerHeight
    }

    private var greeting: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return Layout.greetings[(day - 1) % Layout.greetings.count]
    }

    private var restProgress: CGFloat {
        unitProgress(scrolledDistance / Layout.restFadeDistance)
    }

    private var restOpacity: CGFloat {
        1 - restProgress
    }

    private var collapsedProgress: CGFloat {
        unitProgress((scrolledDistance - Layout.restFadeDistance) / Layout.collapsedRevealDistance)
    }

    private func unitProgress(_ raw: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, raw))
        if reduceMotion {
            return clamped > 0.5 ? 1 : 0
        }
        return clamped
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                AnglesCanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.headerContentGap) {
                        scrollingHeader

                        favoritesBlock(pageWidth: geometry.size.width)

                        gridSection
                    }
                    .padding(.top, safeAreaInsets.top + Layout.headerTopPad)
                    .padding(.bottom, 20)
                    .background(alignment: .top) {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollDistanceKey.self,
                                value: proxy.frame(in: .named("profileScroll")).minY
                            )
                        }
                        .frame(height: 0)
                    }
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "profileScroll")
                .modifier(ProfileScrollDistance(distance: $scrolledDistance))

                headerFade

                collapsedHeader
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .task {
            await viewModel.loadLibrary()
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
                    symbol: filterSymbolColor(viewModel.profileGridFilter),
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
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(minHeight: Layout.headerHeight, alignment: .center)
        .opacity(restOpacity)
        .animation(nil, value: scrolledDistance)
        .allowsHitTesting(restOpacity > 0.4)
        .accessibilityHidden(restOpacity <= 0.4)
    }

    private var collapsedHeader: some View {
        let progress = collapsedProgress

        return VStack(spacing: 0) {
            Color.clear
                .frame(height: safeAreaInsets.top + Layout.headerTopPad)
                .allowsHitTesting(false)

            HStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                Button {
                    showCollapsedFilter = true
                } label: {
                    collapsedTitleLabel
                }
                .buttonStyle(.plain)
                .opacity(progress)
                .offset(y: reduceMotion ? 0 : Layout.collapseSlide * (1 - progress))
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
            .frame(height: Layout.headerHeight)
        }
        .frame(height: headerOverlayHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(progress > 0.4)
    }

    private var collapsedTitleLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: filterSystemImage(viewModel.profileGridFilter))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filterSymbolColor(viewModel.profileGridFilter))

            Text(viewModel.profileGridFilter.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
        }
        .contentShape(Rectangle())
    }

    private var filterPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ProfileGridFilter.allCases, id: \.self) { filter in
                let isSelected = viewModel.profileGridFilter == filter

                Button {
                    viewModel.profileGridFilter = filter
                    showRestFilter = false
                    showCollapsedFilter = false
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

    private var showsEmptyHero: Bool {
        guard case .loaded = viewModel.libraryLoadState else {
            return false
        }

        return viewModel.profileGridFilter == .all && viewModel.cards.isEmpty
    }

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !showsEmptyHero {
                Text(viewModel.profileGridFilter.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, Layout.horizontalPadding)
                    .accessibilityAddTraits(.isHeader)
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
                        spacing: Layout.gridSpacing,
                        openingStyle: viewModel.profileGridFilter.matchingStyle,
                        onDelete: deleteCard,
                        onToggleFavorite: toggleFavorite
                    )
                    .equatable()
                    .padding(.horizontal, Layout.horizontalPadding)
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
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var emptyFilterCopy: some View {
        Text(emptyFilterMessage)
            .font(.body.weight(.medium))
            .foregroundStyle(theme.muted)
            .padding(.horizontal, Layout.horizontalPadding)
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
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func favoritesBlock(pageWidth: CGFloat) -> some View {
        switch viewModel.libraryLoadState {
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                Text("Favorites")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, Layout.horizontalPadding)
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: favoriteRowHeight)
                    .accessibilityLabel("Loading favorites")
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Favorites")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, Layout.horizontalPadding)
                HStack {
                    Text(message)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.muted)
                    Button("Retry") {
                        viewModel.retryLoadLibrary()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
                }
                .padding(.horizontal, Layout.horizontalPadding)
            }
        case .loaded:
            if !viewModel.favoriteCards.isEmpty {
                favoritesSection(pageWidth: pageWidth)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
            .frame(height: Layout.headerTopPad + Layout.headerHeight + 12)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(nil, value: scrolledDistance)
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

private struct ProfileScrollDistance: ViewModifier {
    @Binding var distance: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y)
            } action: { _, newValue in
                update(newValue)
            }
        } else {
            content.onPreferenceChange(ScrollDistanceKey.self) { minY in
                guard let minY else { return }
                update(max(0, -minY))
            }
        }
    }

    private func update(_ newValue: CGFloat) {
        guard abs(distance - newValue) > 0.5 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            distance = newValue
        }
    }
}
