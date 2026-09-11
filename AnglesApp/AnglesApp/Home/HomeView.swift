import SwiftUI

struct HomeView: View {
    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var headerScrollState = HeaderScrollState()
    @State private var showSettings = false
    @State private var showHomeFilter = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack(alignment: .top) {
            AnglesCanvasBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: HeaderCollapse.headerContentGap) {
                    HomeScrollingTitle(scrollState: headerScrollState)

                    HomeFeedList(viewModel: viewModel)
                }
                .padding(.top, HeaderCollapse.headerTopPad)
                .padding(.bottom, 20)
                .background(alignment: .top) {
                    ScrollDistanceProbe(space: "homeScroll")
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "homeScroll")
            .modifier(ProfileScrollDistance(state: headerScrollState))
            .refreshable {
                await viewModel.refreshFeed()
            }

            CollapsingHeaderFade(
                scrollState: headerScrollState,
                safeTop: safeAreaInsets.top
            )
            .ignoresSafeArea(.container, edges: .top)

            HomeFixedActions(
                scrollState: headerScrollState,
                safeTop: safeAreaInsets.top,
                appliedCount: viewModel.appliedFilter.appliedCount,
                showFilter: $showHomeFilter,
                showSettings: $showSettings
            )
            .ignoresSafeArea(.container, edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .task {
            await viewModel.loadFeedIfNeeded()
        }
        .sheet(isPresented: $showHomeFilter) {
            HomeFilterSheet(appliedFilter: viewModel.appliedFilter) { filter in
                viewModel.applyFeedFilter(filter)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.grey)
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

private struct HomeScrollingTitle: View {
    let scrollState: HeaderScrollState

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let opacity = 1 - HeaderCollapse.restProgress(
            scrollState.distance,
            reduceMotion: reduceMotion
        )

        Text("Home")
            .font(.title.bold())
            .foregroundStyle(theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
            .frame(height: HeaderCollapse.headerHeight, alignment: .leading)
            .opacity(opacity)
            .animation(nil, value: scrollState.distance)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHidden(opacity <= 0.4)
    }
}

private struct HomeFixedActions: View {
    let scrollState: HeaderScrollState
    let safeTop: CGFloat
    let appliedCount: Int
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
                CollapsedInlineTitle(title: "Home", progress: progress)
                    .animation(nil, value: scrollState.distance)

                HStack(spacing: 12) {
                    Spacer(minLength: 0)

                    Button {
                        showFilter = true
                    } label: {
                        HomeFilterIcon(appliedCount: appliedCount)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter Home")
                    .accessibilityValue(filterAccessibilityValue(appliedCount))

                    HomeSettingsButton(showSettings: $showSettings)
                }
            }
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
            .frame(height: HeaderCollapse.headerHeight)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeFilterIcon: View {
    let appliedCount: Int

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        CircleIcon(
            systemName: "line.3.horizontal.decrease",
            fill: theme.surface,
            symbol: theme.ink,
            weight: .semibold,
            hairline: theme.cardHairline
        )
        .overlay(alignment: .topTrailing) {
            if appliedCount > 0 {
                Text(String(appliedCount))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.paper)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, 2)
                    .background(theme.ink, in: Capsule())
                    .offset(x: 5, y: -5)
                    .accessibilityHidden(true)
            }
        }
    }
}

private func filterAccessibilityValue(_ appliedCount: Int) -> String {
    appliedCount == 0 ? "No filters applied" : "\(appliedCount) filters applied"
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

private struct HomeFeedList: View {
    let viewModel: HomeViewModel

    @Environment(\.colorScheme) private var colorScheme

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
            if viewModel.feedCards.isEmpty {
                Text(viewModel.feedEmptyCopy)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, HeaderCollapse.horizontalPadding)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 0) {
                    HomeCardGrid(
                        cards: viewModel.feedCards,
                        rowSpacing: HeaderCollapse.horizontalPadding,
                        presentation: .library,
                        menuRole: { _ in .feed },
                        onDelete: { _ in },
                        onToggleFavorite: { card, style in
                            viewModel.toggleFavorite(card.id, style: style)
                        },
                        onSetPublic: { _, _ in },
                        onRemoveFromBoard: { _ in },
                        onReachEnd: viewModel.loadMoreFeed,
                        loadMorePrefetchDistance: 6
                    )
                    .equatable()
                    .padding(.horizontal, HeaderCollapse.horizontalPadding)

                    feedFooter
                }
            }
        }
    }

    @ViewBuilder
    private var feedFooter: some View {
        Group {
            switch viewModel.feedFooterState {
            case .idle:
                Color.clear
                    .accessibilityHidden(true)
            case .loading:
                ProgressView()
                    .accessibilityLabel("Loading more thoughts")
            case .failed:
                Button("Retry loading more") {
                    viewModel.retryLoadMoreFeed()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }
}

#Preview("Home") {
    NavigationStack {
        HomeView(
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            viewModel: HomeViewModel()
        )
    }
    .environmentObject(ThemeStore())
}
