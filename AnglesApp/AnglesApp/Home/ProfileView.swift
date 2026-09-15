import Observation
import SwiftUI

private enum ProfileMetrics {
    static let identityHeight: CGFloat = 124
    static let chipSpring = Animation.spring(response: 0.36, dampingFraction: 0.78)
    static let tabBarHeight = ReframeCardMetrics.chipSize + 12
    static let pagerSpace = "profilePager"

    static func expandedChromeHeight(safeTop: CGFloat) -> CGFloat {
        HeaderCollapse.overlayHeight(safeTop: safeTop)
            + identityHeight
            + tabBarHeight
    }

    static func chromeHeight(safeTop: CGFloat, collapseDistance: CGFloat) -> CGFloat {
        expandedChromeHeight(safeTop: safeTop)
            - min(identityHeight, max(0, collapseDistance))
    }

    static func identityProgress(_ collapseDistance: CGFloat) -> CGFloat {
        min(1, max(0, collapseDistance / identityHeight))
    }

    static func compactProgress(_ collapseDistance: CGFloat) -> CGFloat {
        let revealDistance = HeaderCollapse.collapsedRevealDistance
        return min(
            1,
            max(0, (collapseDistance - (identityHeight - revealDistance)) / revealDistance)
        )
    }
}

@MainActor
@Observable
private final class ProfileHeaderState {
    let distance = ProfileMetrics.identityHeight
}

private struct ProfilePagerSnapshot: Equatable {
    var offset: CGFloat = 0
    var width: CGFloat = 1
    var fromIndex = 0
    var toIndex = 0
    var pageProgress: CGFloat = 0
}

@MainActor
@Observable
private final class ProfilePagerState {
    private(set) var snapshot = ProfilePagerSnapshot()
    private(set) var requestedTab: ProfileGridFilter = .favorites
    private(set) var requestSerial = 0

    private let pageCount: Int

    init(pageCount: Int) {
        self.pageCount = max(1, pageCount)
    }

    func update(offset rawOffset: CGFloat, width rawWidth: CGFloat) {
        guard rawOffset.isFinite, rawWidth.isFinite, rawWidth > 0 else {
            return
        }

        let maximumOffset = rawWidth * CGFloat(pageCount - 1)
        let newOffset = min(maximumOffset, max(0, rawOffset))
        guard abs(snapshot.offset - newOffset) > 0.5
                || abs(snapshot.width - rawWidth) > 0.5
        else {
            return
        }

        let position = newOffset / rawWidth
        let lowerIndex = min(pageCount - 1, max(0, Int(floor(position))))
        let upperIndex = min(pageCount - 1, lowerIndex + 1)
        let progress = upperIndex == lowerIndex
            ? 0
            : min(1, max(0, position - CGFloat(lowerIndex)))

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            snapshot = ProfilePagerSnapshot(
                offset: newOffset,
                width: rawWidth,
                fromIndex: lowerIndex,
                toIndex: progress < 0.0001 ? lowerIndex : upperIndex,
                pageProgress: progress < 0.0001 ? 0 : progress
            )
        }
    }

    func requestPage(_ tab: ProfileGridFilter) {
        requestedTab = tab
        requestSerial &+= 1
    }

    func normalizeAtEndpoint() -> ProfileGridFilter? {
        guard snapshot.width > 0 else {
            return nil
        }

        let index = min(
            pageCount - 1,
            max(0, Int((snapshot.offset / snapshot.width).rounded()))
        )
        guard abs(snapshot.offset - (CGFloat(index) * snapshot.width)) <= 1
        else {
            return nil
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            snapshot = ProfilePagerSnapshot(
                offset: CGFloat(index) * snapshot.width,
                width: snapshot.width,
                fromIndex: index,
                toIndex: index,
                pageProgress: 0
            )
        }
        return ProfileGridFilter.allCases[index]
    }

    func expansion(at index: Int) -> CGFloat {
        guard index >= 0, index < pageCount else {
            return 0
        }
        if snapshot.fromIndex == snapshot.toIndex {
            return index == snapshot.fromIndex ? 1 : 0
        }
        if index == snapshot.fromIndex {
            return 1 - snapshot.pageProgress
        }
        if index == snapshot.toIndex {
            return snapshot.pageProgress
        }
        return 0
    }
}

private struct ProfilePagerGeometry: Equatable {
    let offset: CGFloat
    let width: CGFloat
}

private struct ProfilePagerOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

private struct ProfilePagerOffsetProbe: View {
    let space: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ProfilePagerOffsetKey.self,
                value: proxy.frame(in: .named(space)).minX
            )
        }
    }
}

private struct ProfilePagerTracking: ViewModifier {
    let state: ProfilePagerState
    let fallbackWidth: CGFloat
    let onReachPage: (ProfileGridFilter) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: ProfilePagerGeometry.self) { geometry in
                    ProfilePagerGeometry(
                        offset: max(0, geometry.contentOffset.x),
                        width: geometry.containerSize.width
                    )
                } action: { _, newValue in
                    state.update(offset: newValue.offset, width: newValue.width)
                }
                .onScrollPhaseChange { _, newPhase in
                    guard newPhase == .idle else {
                        return
                    }
                    commitEndpoint()
                }
        } else {
            content
                .onPreferenceChange(ProfilePagerOffsetKey.self) { minX in
                    guard let minX else {
                        return
                    }
                    state.update(offset: max(0, -minX), width: fallbackWidth)
                    commitEndpoint()
                }
        }
    }

    private func commitEndpoint() {
        guard let tab = state.normalizeAtEndpoint() else {
            return
        }
        onReachPage(tab)
    }
}

struct ProfileView: View {

    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager
    /// Filled from Sign in with Apple / Better Auth in row 8. Nil keeps the session label.
    var displayName: String? = nil
    var onInspire: () -> Void = {}
    var onLogOut: (() -> Void)? = nil
    var canLoadFullAppContent = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var headerState = ProfileHeaderState()
    @State private var pagerState = ProfilePagerState(
        pageCount: ProfileGridFilter.allCases.count
    )
    @State private var showSettings = false
    @State private var committedTab: ProfileGridFilter = .favorites

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var fixedChromeHeight: CGFloat {
        ProfileMetrics.chromeHeight(
            safeTop: safeAreaInsets.top,
            collapseDistance: ProfileMetrics.identityHeight
        )
    }

    private var profileTitle: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "On this iPhone" : trimmed
    }

    var body: some View {
        ZStack(alignment: .top) {
            AnglesCanvasBackground()
                .ignoresSafeArea()

            pager
                .ignoresSafeArea(edges: .top)

            ProfileChrome(
                title: profileTitle,
                safeTop: safeAreaInsets.top,
                headerState: headerState,
                pagerState: pagerState,
                settledSelection: committedTab,
                showSettings: $showSettings,
                onSelectTab: selectTab
            )
            .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.ink)
        .task(id: canLoadFullAppContent) {
            guard canLoadFullAppContent else {
                return
            }
            await viewModel.loadLibraryIfNeeded()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                storeKitManager: storeKitManager,
                onLogOut: {
                    onLogOut?()
                    showSettings = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.grey)
            .modifier(UserAppearance(store: themeStore))
        }
    }

    private var pager: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(ProfileGridFilter.allCases, id: \.self) { tab in
                            ProfileTabPage(
                                tab: tab,
                                cards: viewModel.profileCards(for: tab),
                                loadState: viewModel.libraryLoadState,
                                ownedIsEmpty: viewModel.ownedCards.isEmpty,
                                chromeHeight: fixedChromeHeight,
                                onInspire: onInspire,
                                onRetry: viewModel.retryLoadLibrary,
                                onRefresh: { await viewModel.refreshLibrary() },
                                onDelete: deleteCard,
                                onToggleFavorite: toggleFavorite,
                                onSetPublic: setPublic,
                                onRemoveFromBoard: removeFromBoard
                            )
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(tab)
                        }
                    }
                    .background(alignment: .leading) {
                        ProfilePagerOffsetProbe(space: ProfileMetrics.pagerSpace)
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .coordinateSpace(name: ProfileMetrics.pagerSpace)
                .modifier(
                    ProfilePagerTracking(
                        state: pagerState,
                        fallbackWidth: proxy.size.width,
                        onReachPage: commitPage
                    )
                )
                .onChange(of: pagerState.requestSerial) { _, _ in
                    withAnimation(tabAnimation) {
                        scrollProxy.scrollTo(
                            pagerState.requestedTab,
                            anchor: .leading
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabAnimation: Animation? {
        reduceMotion ? nil : ProfileMetrics.chipSpring
    }

    private func selectTab(_ filter: ProfileGridFilter) {
        guard filter != committedTab else {
            return
        }
        pagerState.requestPage(filter)
    }

    private func commitPage(_ filter: ProfileGridFilter) {
        guard filter != committedTab else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            committedTab = filter
            if filter != viewModel.profileGridFilter {
                viewModel.profileGridFilter = filter
            }
        }
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

    private func setPublic(_ card: HomeCard, _ isPublic: Bool) {
        viewModel.setPublic(card.id, isPublic: isPublic)
    }

    private func removeFromBoard(_ card: HomeCard) {
        withAnimation(favoriteLayoutAnimation) {
            viewModel.removeFromBoard(card.id)
        }
    }
}

private struct ProfileChrome: View {
    let title: String
    let safeTop: CGFloat
    let headerState: ProfileHeaderState
    let pagerState: ProfilePagerState
    let settledSelection: ProfileGridFilter
    @Binding var showSettings: Bool
    let onSelectTab: (ProfileGridFilter) -> Void

    var body: some View {
        let collapseDistance = headerState.distance
        let identityProgress = ProfileMetrics.identityProgress(collapseDistance)

        VStack(spacing: 0) {
            ProfileTopBar(
                title: title,
                safeTop: safeTop,
                collapseDistance: collapseDistance,
                showSettings: $showSettings
            )

            ProfileIdentityHeader(title: title)
                .frame(
                    height: ProfileMetrics.identityHeight - collapseDistance,
                    alignment: .top
                )
                .clipped()
                .opacity(Double(1 - identityProgress))
                .allowsHitTesting(identityProgress < 0.5)
                .accessibilityHidden(identityProgress >= 0.5)
                .animation(nil, value: collapseDistance)

            ProfileStyleTabBar(
                pagerState: pagerState,
                settledSelection: settledSelection,
                onSelect: onSelectTab
            )
        }
        .frame(
            height: ProfileMetrics.chromeHeight(
                safeTop: safeTop,
                collapseDistance: collapseDistance
            ),
            alignment: .top
        )
        .background {
            ProfileChromeBackground(pagerState: pagerState)
            .ignoresSafeArea(edges: .top)
        }
    }
}

private struct ProfileChromeBackground: View {
    let pagerState: ProfilePagerState

    var body: some View {
        let tabs = ProfileGridFilter.allCases
        let snapshot = pagerState.snapshot

        StyleWash.headerGlassFill(
            fromInk: tabs[snapshot.fromIndex].headerWashInk,
            toInk: tabs[snapshot.toIndex].headerWashInk,
            progress: snapshot.pageProgress
        )
    }
}

private enum ProfileViewAvatar {
    static let large: CGFloat = 76
    static let compact: CGFloat = 28
}

private struct ProfileIdentityHeader: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InitialsAvatar(
                letters: UserInitials.letters,
                side: ProfileViewAvatar.large,
                fill: theme.ink,
                symbol: theme.paper
            )

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct ProfileTopBar: View {
    let title: String
    let safeTop: CGFloat
    let collapseDistance: CGFloat
    @Binding var showSettings: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let progress = ProfileMetrics.compactProgress(collapseDistance)

        HStack(spacing: 10) {
            HStack(spacing: 8) {
                InitialsAvatar(
                    letters: UserInitials.letters,
                    side: ProfileViewAvatar.compact,
                    fill: theme.ink,
                    symbol: theme.paper
                )

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
            }
            .opacity(progress)
            .offset(y: reduceMotion ? 0 : HeaderCollapse.collapseSlide * (1 - progress))
            .animation(nil, value: collapseDistance)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHidden(progress <= 0.4)

            Spacer(minLength: 8)

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
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.top, safeTop + HeaderCollapse.headerTopPad)
        .frame(height: HeaderCollapse.overlayHeight(safeTop: safeTop))
    }
}

private struct ProfileStyleTabBar: View {
    let pagerState: ProfilePagerState
    let settledSelection: ProfileGridFilter
    let onSelect: (ProfileGridFilter) -> Void

    var body: some View {
        HStack(spacing: ReframeCardMetrics.chipSpacing) {
            ForEach(
                Array(ProfileGridFilter.allCases.enumerated()),
                id: \.element
            ) { index, filter in
                ProfileTabChip(
                    filter: filter,
                    expansion: pagerState.expansion(at: index),
                    isSettledSelection: settledSelection == filter,
                    onSelect: { onSelect(filter) }
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.vertical, 6)
        .frame(height: ProfileMetrics.tabBarHeight)
        .accessibilityElement(children: .contain)
    }
}

private struct ProfileTabChipLayout: Layout {
    struct Cache {
        var iconSize: CGSize
        var labelSize: CGSize
    }

    var expansion: CGFloat

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(
            iconSize: subviews.indices.contains(0)
                ? subviews[0].sizeThatFits(.unspecified)
                : .zero,
            labelSize: subviews.indices.contains(1)
                ? subviews[1].sizeThatFits(.unspecified)
                : .zero
        )
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        guard subviews.count == 2 else {
            return .zero
        }

        let side = ReframeCardMetrics.chipSize
        let expandedWidth = max(
            side,
            20 + cache.iconSize.width + 6 + cache.labelSize.width
        )

        return CGSize(
            width: side + ((expandedWidth - side) * expansion),
            height: side
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard subviews.count == 2 else {
            return
        }

        let side = ReframeCardMetrics.chipSize
        let iconSize = cache.iconSize
        let labelSize = cache.labelSize
        let collapsedIconX = (side - iconSize.width) / 2
        let expandedIconX: CGFloat = 10
        let iconX = collapsedIconX
            + ((expandedIconX - collapsedIconX) * expansion)
        let iconY = bounds.midY - (iconSize.height / 2)

        subviews[0].place(
            at: CGPoint(x: bounds.minX + iconX, y: iconY),
            anchor: .topLeading,
            proposal: ProposedViewSize(iconSize)
        )

        subviews[1].place(
            at: CGPoint(
                x: bounds.minX + expandedIconX + iconSize.width + 6,
                y: bounds.midY - (labelSize.height / 2)
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(labelSize)
        )
    }
}

private struct ProfileTabChip: View {
    let filter: ProfileGridFilter
    let expansion: CGFloat
    let isSettledSelection: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectHaptic = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var appearance: CardStyleAppearance? {
        filter.matchingStyle.map(CardStyleAppearance.init)
    }

    private var ink: Color {
        return filter.symbolColor(ink: theme.ink)
    }

    var body: some View {
        let side = ReframeCardMetrics.chipSize
        let slop = (ReframeCardMetrics.chipHitSize - side) / 2
        let clampedExpansion = min(1, max(0, expansion))

        Button {
            guard !isSettledSelection else {
                return
            }
            selectHaptic += 1
            onSelect()
        } label: {
            ProfileTabChipLayout(expansion: clampedExpansion) {
                Image(systemName: filter.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))

                Text(filter.chipTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(clampedExpansion)
                    .scaleEffect(
                        0.84 + (0.16 * clampedExpansion),
                        anchor: .leading
                    )
            }
            .foregroundStyle(ink.opacity(inkOpacity(for: clampedExpansion)))
            .frame(height: side)
            .clipped()
            .background {
                Capsule(style: .continuous)
                    .fill(chipFill(for: clampedExpansion))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                filter == .favorites ? theme.cardHairline : .clear,
                                lineWidth: 0.5
                            )
                    }
            }
            .padding(slop)
            .contentShape(Capsule())
            .padding(-slop)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectHaptic)
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(
            isSettledSelection ? [.isButton, .isSelected] : .isButton
        )
    }

    private func chipFill(for expansion: CGFloat) -> Color {
        if filter == .favorites {
            let unselected = colorScheme == .dark ? 0.72 : 0.68
            return theme.surface.opacity(
                unselected + ((1 - unselected) * Double(expansion))
            )
        }
        return ink.opacity(fillOpacity(for: expansion))
    }

    private func fillOpacity(for expansion: CGFloat) -> Double {
        let selected: Double
        let unselected: Double
        if let appearance {
            selected = appearance.chipFillOpacity(for: colorScheme)
            unselected = appearance.chipUnselectedFillOpacity(for: colorScheme)
        } else {
            selected = colorScheme == .dark ? 0.16 : 0.22
            unselected = colorScheme == .dark ? 0.13 : 0.16
        }

        return unselected + ((selected - unselected) * Double(expansion))
    }

    private var unselectedInkOpacity: Double {
        appearance?.chipUnselectedInkOpacity(for: colorScheme)
            ?? (colorScheme == .dark ? 0.84 : 0.72)
    }

    private func inkOpacity(for expansion: CGFloat) -> Double {
        unselectedInkOpacity
            + ((1 - unselectedInkOpacity) * Double(expansion))
    }
}

private struct ProfileTabPage: View {
    let tab: ProfileGridFilter
    let cards: [HomeCard]
    let loadState: LibraryLoadState
    let ownedIsEmpty: Bool
    let chromeHeight: CGFloat
    var onInspire: () -> Void
    var onRetry: () -> Void
    var onRefresh: () async -> Void
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard, Style) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void
    var onRemoveFromBoard: (HomeCard) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var showsEmptyHero: Bool {
        guard case .loaded = loadState else {
            return false
        }

        return tab != .favorites && ownedIsEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: chromeHeight)

                    tabContent
                        .padding(.bottom, 20)
                }
                .frame(
                    minHeight: proxy.size.height,
                    alignment: .top
                )
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await onRefresh()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .accessibilityLabel("Loading cards")
        case .failed(let message):
            libraryError(message)
        case .loaded:
            if showsEmptyHero {
                ProfileEmptyLibraryHero(onInspire: onInspire)
            } else if cards.isEmpty {
                Text(tab.emptyCopy)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, HeaderCollapse.horizontalPadding)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HomeCardGrid(
                    cards: cards,
                    rowSpacing: HeaderCollapse.horizontalPadding,
                    presentation: tab.presentation,
                    openingStyle: tab.matchingStyle,
                    onDelete: onDelete,
                    onToggleFavorite: onToggleFavorite,
                    onSetPublic: onSetPublic,
                    onRemoveFromBoard: onRemoveFromBoard
                )
                .equatable()
                .padding(.horizontal, HeaderCollapse.horizontalPadding)
                .padding(.top, 10)
            }
        }
    }

    private func libraryError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.muted)
            Button("Retry", action: onRetry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct ProfileEmptyLibraryHero: View {
    var onInspire: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
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
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Profile") {
    NavigationStack {
        ProfileView(
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            viewModel: HomeViewModel(),
            storeKitManager: StoreKitManager()
        )
    }
    .environmentObject(ThemeStore())
}
