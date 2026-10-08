import Observation
import SwiftUI
import UIKit

enum StyleTabMetrics {
    static let chipSpring = Animation.spring(response: 0.36, dampingFraction: 0.78)
    static let chromeBottomInset: CGFloat = 8
    static let tabBarHeight = ReframeCardMetrics.chipSize + 12 + chromeBottomInset

    static func pageTint(isDark: Bool) -> CGFloat {
        isDark ? 0.07 : 0.045
    }
}

protocol StyleTabRepresentable: Hashable, CaseIterable {
    var title: String { get }
    var chipTitle: String { get }
    var systemImage: String { get }
    var matchingStyle: Style? { get }
    func symbolColor(ink: Color) -> Color
    var headerWashInk: Color { get }
}

extension ProfileGridFilter: StyleTabRepresentable {
}

extension HomeFeedTab: StyleTabRepresentable {
}

struct StyleTabPagerSnapshot: Equatable {
    var fromIndex = 0
    var toIndex = 0
    var pageProgress: CGFloat = 0
}

/// Which style page is showing, and the one short crossfade between two of them.
///
/// Styles are picked from a menu, so there is no finger to follow. A pick jumps the strip to
/// its page and animates `pageProgress` from 0 to 1 once; the wash, glass and chips cross-fade
/// as opacities, so the chrome is evaluated at the start and the end, not once per frame.
@MainActor
@Observable
final class StyleTabPagerState<T: StyleTabRepresentable> {
    private(set) var snapshot: StyleTabPagerSnapshot
    private(set) var requestedTab: T
    /// Bumped on every pick; the strip scrolls to `requestedTab` when it changes.
    private(set) var requestSerial = 0

    private let tabs: [T]
    @ObservationIgnored private var transitionSerial = 0

    init(initialTab: T) {
        let tabs = Array(T.allCases)
        let index = tabs.firstIndex(of: initialTab) ?? 0
        self.requestedTab = initialTab
        self.tabs = tabs
        self.snapshot = StyleTabPagerSnapshot(fromIndex: index, toIndex: index, pageProgress: 0)
    }

    var pageCount: Int { tabs.count }

    /// Picks a page. A nil `animation` (Reduce Motion, a jump from a deep link) settles at once.
    func requestPage(_ tab: T, animation: Animation? = StyleTabMetrics.chipSpring) {
        guard let target = tabs.firstIndex(of: tab) else {
            return
        }
        requestedTab = tab
        requestSerial &+= 1
        transitionSerial &+= 1
        let serial = transitionSerial

        // Leaving from wherever the picture is closest to, so a quick second pick starts clean.
        let origin = snapshot.pageProgress < 0.5 ? snapshot.fromIndex : snapshot.toIndex
        guard let animation, origin != target else {
            settle(on: target)
            return
        }

        var start = Transaction(animation: nil)
        start.disablesAnimations = true
        withTransaction(start) {
            snapshot = StyleTabPagerSnapshot(fromIndex: origin, toIndex: target, pageProgress: 0)
        }
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            snapshot.pageProgress = 1
        } completion: { [weak self] in
            guard let self, self.transitionSerial == serial else {
                return
            }
            self.settle(on: target)
        }
    }

    private func settle(on index: Int) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            snapshot = StyleTabPagerSnapshot(fromIndex: index, toIndex: index, pageProgress: 0)
        }
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

/// The style picker in a page header: a native single-select menu, plus a chip for any
/// tab pinned outside it (Profile's Favorites). Six styles do not fit a row of chips on a
/// narrow phone, so they live in the menu. The pages do not swipe sideways.
struct AdaptiveStyleTabBar<T: StyleTabRepresentable>: View {
    let pagerState: StyleTabPagerState<T>
    let settledSelection: T
    /// Kept for call sites that reserve trailing room; the menu never needs it.
    var reservedTrailingWidth: CGFloat = 0
    var includesTrailingSpacer = true
    var padded = true
    let onSelect: (T) -> Void

    var body: some View {
        let _ = RenderCounter.hit("AdaptiveStyleTabBar")
        let tabs = Array(T.allCases)
        // The menu names the page that was picked, not the one the fade is leaving.
        let nearest = pagerState.requestedTab

        HStack(spacing: ReframeCardMetrics.chipSpacing) {
            StyleTabMenu(
                tabs: tabs,
                current: nearest,
                onSelect: onSelect
            )

            if includesTrailingSpacer {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, padded ? HeaderCollapse.horizontalPadding : 0)
        .padding(.top, padded ? 6 : 0)
        .padding(.bottom, padded ? 6 + StyleTabMetrics.chromeBottomInset : 0)
        .frame(
            height: padded
                ? StyleTabMetrics.tabBarHeight
                : CircleIcon.Size.normal.side
        )
        .accessibilityElement(children: .contain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Tinted menu symbols, built once per style and appearance. At most six styles times two
/// appearances, and the system evicts them under memory pressure.
private enum MenuIconCache {
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        return cache
    }()
}

/// One capsule that names the tab on screen and opens a single-select list of the rest.
private struct StyleTabMenu<T: StyleTabRepresentable>: View {
    let tabs: [T]
    let current: T
    let onSelect: (T) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectHaptic = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var appearance: CardStyleAppearance? {
        current.matchingStyle.map(CardStyleAppearance.init)
    }

    private var selection: Binding<T> {
        Binding(
            get: { current },
            set: { tab in
                if tab != current {
                    selectHaptic += 1
                }
                onSelect(tab)
            }
        )
    }

    var body: some View {
        Menu {
            Picker(selection: selection) {
                ForEach(tabs, id: \.self) { tab in
                    Label {
                        Text(tab.title)
                    } icon: {
                        rowIcon(for: tab)
                    }
                    .tag(tab)
                }
            } label: {
                Text("Style")
            }
            .pickerStyle(.inline)
        } label: {
            // The pill is as wide as the longest label it can show, so picking another style
            // never resizes it and the native menu has nothing to re-anchor or animate.
            ZStack {
                ForEach(sizingLabels, id: \.title) { label in
                    labelContent(symbol: label.symbol, title: label.title)
                        .hidden()
                        .accessibilityHidden(true)
                }
                labelContent(
                    symbol: current.systemImage,
                    title: current.chipTitle
                )
                .transaction { $0.animation = nil }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(height: ReframeCardMetrics.chipSize)
            .background {
                Capsule(style: .continuous)
                    .fill(fill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(appearance == nil ? theme.cardHairline : .clear, lineWidth: 0.5)
                    }
            }
            .contentShape(Capsule())
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectHaptic)
        .accessibilityLabel("Style: \(current.title)")
        .accessibilityHint("Opens the list of styles")
    }

    private struct SizingLabel {
        let symbol: String
        let title: String
    }

    /// Every label the pill can show. Only the widest one decides its width.
    private var sizingLabels: [SizingLabel] {
        tabs.map { SizingLabel(symbol: $0.systemImage, title: $0.chipTitle) }
    }

    private func labelContent(symbol: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .opacity(0.7)
        }
    }

    /// A native menu draws row icons as one template colour. A pre-tinted image keeps each
    /// style's own colour; rows with no style (For you) stay a plain symbol.
    private func rowIcon(for tab: T) -> Image {
        guard let style = tab.matchingStyle else {
            return Image(systemName: tab.systemImage)
        }
        let isDark = colorScheme == .dark
        let key = "\(tab.systemImage)|\(style.rawValue)|\(isDark)" as NSString
        if let cached = MenuIconCache.images.object(forKey: key) {
            return Image(uiImage: cached)
        }
        let ink = UIColor(CardStyleAppearance(style: style).ink)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: isDark ? .dark : .light))
        let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        guard
            let symbol = UIImage(systemName: tab.systemImage, withConfiguration: configuration)?
                .withTintColor(ink, renderingMode: .alwaysOriginal)
        else {
            return Image(systemName: tab.systemImage)
        }
        MenuIconCache.images.setObject(symbol, forKey: key)
        return Image(uiImage: symbol)
    }

    private var ink: Color {
        current.symbolColor(ink: theme.ink)
    }

    private var fill: Color {
        guard let appearance else {
            return theme.surface
        }
        return appearance.ink.opacity(appearance.chipFillOpacity(for: colorScheme))
    }
}

struct StyleTabChromeBackground<T: StyleTabRepresentable>: View {
    let pagerState: StyleTabPagerState<T>

    var body: some View {
        let tabs = Array(T.allCases)
        let snapshot = pagerState.snapshot

        StyleWash.headerGlassFill(
            fromInk: tabs[snapshot.fromIndex].headerWashInk,
            toInk: tabs[snapshot.toIndex].headerWashInk,
            progress: snapshot.pageProgress
        )
    }
}

/// Paper-to-grey canvas with a quiet style wash that scrubs with the pager.
struct StyleTabPageBackground<T: StyleTabRepresentable>: View {
    let pagerState: StyleTabPagerState<T>

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let _ = RenderCounter.hit("StyleTabPageBackground")
        let tabs = Array(T.allCases)
        let snapshot = pagerState.snapshot
        let amount = min(1, max(0, snapshot.pageProgress))
        let tint = StyleTabMetrics.pageTint(isDark: colorScheme == .dark)

        ZStack {
            LinearGradient(
                colors: [theme.paper, theme.grey],
                startPoint: .top,
                endPoint: .bottom
            )

            styleWash(
                ink: tabs[snapshot.fromIndex].headerWashInk,
                tint: tint
            )
            .opacity(1 - amount)

            styleWash(
                ink: tabs[snapshot.toIndex].headerWashInk,
                tint: tint
            )
            .opacity(amount)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func styleWash(ink: Color, tint: CGFloat) -> some View {
        LinearGradient(
            colors: [
                ink.opacity(tint),
                ink.opacity(tint * 0.28),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Tab-bar fade using the same quiet style wash as the page canvas.
struct StyleTabBottomFade<T: StyleTabRepresentable>: View {
    let pagerState: StyleTabPagerState<T>
    let safeBottom: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let tabs = Array(T.allCases)
        let snapshot = pagerState.snapshot
        let amount = min(1, max(0, snapshot.pageProgress))
        let tint = StyleTabMetrics.pageTint(isDark: colorScheme == .dark)

        ZStack {
            LinearGradient(
                stops: CanvasEdgeFade.bottomStops(theme: theme),
                startPoint: .top,
                endPoint: .bottom
            )

            footerWash(
                ink: tabs[snapshot.fromIndex].headerWashInk,
                tint: tint
            )
            .opacity(1 - amount)

            footerWash(
                ink: tabs[snapshot.toIndex].headerWashInk,
                tint: tint
            )
            .opacity(amount)
        }
        .frame(height: HeaderCollapse.bottomFadeHeight(safeBottom: safeBottom))
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func footerWash(ink: Color, tint: CGFloat) -> some View {
        LinearGradient(
            colors: [
                .clear,
                ink.opacity(tint * 0.55),
                ink.opacity(tint),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
