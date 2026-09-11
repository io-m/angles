import SwiftUI

struct HomeView: View {
    let safeAreaInsets: EdgeInsets
    let pageWidth: CGFloat

    let viewModel: HomeViewModel

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var headerScrollState = HeaderScrollState()
    @State private var showSettings = false
    @State private var showRestFilter = false
    @State private var showCollapsedFilter = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack(alignment: .top) {
            AnglesCanvasBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: HeaderCollapse.headerContentGap) {
                    HomeRestHeader(
                        scrollState: headerScrollState,
                        viewModel: viewModel,
                        showFilter: $showRestFilter,
                        showSettings: $showSettings
                    )

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
            .modifier(ProfileScrollDistance(state: headerScrollState))

            CollapsingHeaderFade(
                scrollState: headerScrollState,
                safeTop: safeAreaInsets.top
            )

            HomeCollapsedHeader(
                scrollState: headerScrollState,
                safeTop: safeAreaInsets.top,
                viewModel: viewModel,
                showFilter: $showCollapsedFilter,
                showSettings: $showSettings
            )
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
}

private struct HomeRestHeader: View {
    let scrollState: HeaderScrollState
    let viewModel: HomeViewModel
    @Binding var showFilter: Bool
    @Binding var showSettings: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let opacity = 1 - HeaderCollapse.restProgress(
            scrollState.distance,
            reduceMotion: reduceMotion
        )

        HStack(alignment: .center, spacing: 12) {
            Text("Home")
                .font(.title.bold())
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Button {
                showFilter = true
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
            .popover(isPresented: $showFilter, arrowEdge: .top) {
                GridFilterPicker(selection: viewModel.homeGridFilter) { filter in
                    viewModel.homeGridFilter = filter
                    showFilter = false
                }
                .presentationCompactAdaptation(.popover)
            }

            HomeSettingsButton(showSettings: $showSettings)
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .frame(minHeight: HeaderCollapse.headerHeight, alignment: .center)
        .opacity(opacity)
        .animation(nil, value: scrollState.distance)
        .allowsHitTesting(opacity > 0.4)
        .accessibilityHidden(opacity <= 0.4)
    }
}

/// Collapsed chrome is the centered filter chip; Settings stays trailing.
private struct HomeCollapsedHeader: View {
    let scrollState: HeaderScrollState
    let safeTop: CGFloat
    let viewModel: HomeViewModel
    @Binding var showFilter: Bool
    @Binding var showSettings: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let progress = HeaderCollapse.collapsedProgress(
            scrollState.distance,
            reduceMotion: reduceMotion
        )

        VStack(spacing: 0) {
            Color.clear
                .frame(height: safeTop + HeaderCollapse.headerTopPad)
                .allowsHitTesting(false)

            ZStack {
                Button {
                    showFilter = true
                } label: {
                    CollapsedFilterLabel(filter: viewModel.homeGridFilter)
                }
                .buttonStyle(.plain)
                .opacity(progress)
                .offset(y: reduceMotion ? 0 : HeaderCollapse.collapseSlide * (1 - progress))
                .animation(nil, value: scrollState.distance)
                .accessibilityLabel("Filter")
                .accessibilityValue(viewModel.homeGridFilter.title)
                .accessibilityHidden(progress <= 0.4)
                .popover(isPresented: $showFilter, arrowEdge: .top) {
                    GridFilterPicker(selection: viewModel.homeGridFilter) { filter in
                        viewModel.homeGridFilter = filter
                        showFilter = false
                    }
                    .presentationCompactAdaptation(.popover)
                }
                .allowsHitTesting(progress > 0.4)

                HStack {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    HomeSettingsButton(showSettings: $showSettings)
                        .opacity(progress)
                        .animation(nil, value: scrollState.distance)
                        .accessibilityHidden(progress <= 0.4)
                        .allowsHitTesting(progress > 0.4)
                }
                .padding(.horizontal, HeaderCollapse.horizontalPadding)
            }
            .frame(height: HeaderCollapse.headerHeight)
        }
        .frame(height: HeaderCollapse.overlayHeight(safeTop: safeTop), alignment: .top)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(progress > 0.4)
    }
}

private struct HomeSettingsButton: View {
    @Binding var showSettings: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
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
}

/// Own view so the header's scroll progress never re-evaluates the shelves.
private struct HomeFeedList: View {
    let pageWidth: CGFloat
    let viewModel: HomeViewModel

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
