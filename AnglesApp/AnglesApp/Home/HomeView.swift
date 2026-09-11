import SwiftUI

struct HomeView: View {
    let safeAreaInsets: EdgeInsets
    let pageWidth: CGFloat

    @ObservedObject var viewModel: HomeViewModel

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrolledDistance: CGFloat = 0
    @State private var showSettings = false
    @State private var showRestFilter = false
    @State private var showCollapsedFilter = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var headerOverlayHeight: CGFloat {
        HeaderCollapse.overlayHeight(safeTop: safeAreaInsets.top)
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
                    restHeader

                    HomeFeedList(pageWidth: pageWidth, viewModel: viewModel)
                }
                .padding(.top, safeAreaInsets.top + HeaderCollapse.headerTopPad)
                .padding(.bottom, 20)
                .background(alignment: .top) {
                    ScrollDistanceProbe(space: "homeScroll")
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "homeScroll")
            .modifier(ProfileScrollDistance(distance: $scrolledDistance))

            headerFade

            collapsedHeader
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .task {
            await viewModel.loadFeedIfNeeded()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.grey)
                .modifier(UserAppearance(store: themeStore))
        }
    }

    private var restHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Home")
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
                    systemName: filterSystemImage(viewModel.homeGridFilter),
                    fill: theme.surface,
                    symbol: filterSymbolColor(viewModel.homeGridFilter, ink: theme.ink),
                    weight: .semibold,
                    hairline: theme.cardHairline
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter")
            .accessibilityValue(viewModel.homeGridFilter.title)
            .popover(isPresented: $showRestFilter, arrowEdge: .top) {
                filterPicker
                    .presentationCompactAdaptation(.popover)
            }

            settingsButton
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .frame(minHeight: HeaderCollapse.headerHeight, alignment: .center)
        .opacity(restOpacity)
        .animation(nil, value: scrolledDistance)
        .allowsHitTesting(restOpacity > 0.4)
        .accessibilityHidden(restOpacity <= 0.4)
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            CircleIcon(
                systemName: "gearshape",
                fill: theme.surface,
                symbol: theme.ink,
                hairline: theme.cardHairline
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    /// Collapsed chrome is the centered filter chip; Settings stays trailing so it is
    /// still reachable once the title is gone.
    private var collapsedHeader: some View {
        let progress = collapsedProgress

        return VStack(spacing: 0) {
            Color.clear
                .frame(height: safeAreaInsets.top + HeaderCollapse.headerTopPad)
                .allowsHitTesting(false)

            ZStack {
                Button {
                    showCollapsedFilter = true
                } label: {
                    CollapsedFilterLabel(filter: viewModel.homeGridFilter)
                }
                .buttonStyle(.plain)
                .opacity(progress)
                .offset(y: reduceMotion ? 0 : HeaderCollapse.collapseSlide * (1 - progress))
                .animation(nil, value: scrolledDistance)
                .accessibilityLabel("Filter")
                .accessibilityValue(viewModel.homeGridFilter.title)
                .accessibilityHidden(progress <= 0.4)
                .popover(isPresented: $showCollapsedFilter, arrowEdge: .top) {
                    filterPicker
                        .presentationCompactAdaptation(.popover)
                }
                .allowsHitTesting(progress > 0.4)

                HStack {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    settingsButton
                        .opacity(progress)
                        .animation(nil, value: scrolledDistance)
                        .accessibilityHidden(progress <= 0.4)
                        .allowsHitTesting(progress > 0.4)
                }
                .padding(.horizontal, HeaderCollapse.horizontalPadding)
            }
            .frame(height: HeaderCollapse.headerHeight)
        }
        .frame(height: headerOverlayHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(progress > 0.4)
    }

    private var filterPicker: some View {
        GridFilterPicker(selection: viewModel.homeGridFilter) { filter in
            viewModel.homeGridFilter = filter
            showRestFilter = false
            showCollapsedFilter = false
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
            .frame(height: HeaderCollapse.headerTopPad + HeaderCollapse.headerHeight + 12)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(nil, value: scrolledDistance)
    }
}

/// Own view so the header's scroll progress never re-evaluates the shelves.
private struct HomeFeedList: View {
    let pageWidth: CGFloat

    @ObservedObject var viewModel: HomeViewModel

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var cardRowHeight: CGFloat = ReframeCardMetrics.baseHeight

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        switch viewModel.feedLoadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .accessibilityLabel("Loading Home")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                Button("Retry") {
                    viewModel.retryLoadFeed()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
            }
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
        case .loaded:
            let sections = viewModel.feedSections
            if sections.isEmpty {
                Text(viewModel.feedEmptyCopy)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, HeaderCollapse.horizontalPadding)
                    .padding(.top, 8)
            } else {
                // Lazy so the shelves off screen are not mounted; ~20 strips of 6 flip
                // cards each is far too much view tree to keep alive at once.
                LazyVStack(alignment: .leading, spacing: HeaderCollapse.headerContentGap) {
                    ForEach(sections) { section in
                        HomeFeedShelf(
                            section: section,
                            pageWidth: pageWidth,
                            cardRowHeight: cardRowHeight,
                            openingStyle: viewModel.homeGridFilter.matchingStyle,
                            viewModel: viewModel
                        )
                        .equatable()
                    }
                }
            }
        }
    }
}

/// Not an `@ObservedObject`: a heart on one shelf must not re-render the others, so this
/// only reacts to its own inputs.
private struct HomeFeedShelf: View, Equatable {
    let section: FeedSection
    let pageWidth: CGFloat
    let cardRowHeight: CGFloat
    let openingStyle: Style?
    let viewModel: HomeViewModel

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    static func == (lhs: HomeFeedShelf, rhs: HomeFeedShelf) -> Bool {
        lhs.section == rhs.section
            && lhs.pageWidth == rhs.pageWidth
            && lhs.cardRowHeight == rhs.cardRowHeight
            && lhs.openingStyle == rhs.openingStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HeaderCollapse.sectionContentGap) {
            NavigationLink {
                FeedSubsetView(shelf: section.shelf, viewModel: viewModel)
            } label: {
                HStack(spacing: 6) {
                    Text(section.shelf.title)
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
            .accessibilityHint(section.shelf.hint)

            HomeCardStrip(
                cards: section.cards,
                pageWidth: pageWidth,
                presentation: .library,
                cardRowHeight: cardRowHeight,
                openingStyle: openingStyle,
                menuRole: { _ in .feed },
                onDelete: { _ in },
                onToggleFavorite: { card, style in viewModel.toggleFavorite(card.id, style: style) },
                onSetPublic: { _, _ in },
                onRemoveFromBoard: { _ in }
            )
            .equatable()
        }
    }
}

#Preview("Home") {
    NavigationStack {
        HomeView(
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            pageWidth: 393,
            viewModel: HomeViewModel()
        )
    }
    .environmentObject(ThemeStore())
}
