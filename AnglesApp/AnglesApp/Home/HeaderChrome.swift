import Observation
import SwiftUI

/// Collapse language shared by Home and Profile: a left-aligned title row at rest that
/// fades as the page scrolls. Home reveals a centered inline title; Profile reveals
/// a centered filter chip.
enum HeaderCollapse {
    static let horizontalPadding: CGFloat = 16
    static let headerHeight: CGFloat = 44
    static let headerTopPad: CGFloat = 6
    static let headerContentGap: CGFloat = 18
    static let sectionContentGap: CGFloat = 16
    static let restFadeDistance: CGFloat = 44
    static let collapsedRevealDistance: CGFloat = 36
    static let collapseSlide: CGFloat = 10
    static let maximumTrackedDistance = restFadeDistance + collapsedRevealDistance

    static func overlayHeight(safeTop: CGFloat) -> CGFloat {
        safeTop + headerTopPad + headerHeight
    }

    static func restProgress(_ distance: CGFloat, reduceMotion: Bool) -> CGFloat {
        unit(distance / restFadeDistance, reduceMotion: reduceMotion)
    }

    static func collapsedProgress(_ distance: CGFloat, reduceMotion: Bool) -> CGFloat {
        unit((distance - restFadeDistance) / collapsedRevealDistance, reduceMotion: reduceMotion)
    }

    private static func unit(_ raw: CGFloat, reduceMotion: Bool) -> CGFloat {
        let clamped = min(1, max(0, raw))
        if reduceMotion {
            return clamped > 0.5 ? 1 : 0
        }
        return clamped
    }

    static func topFadeHeight(safeTop: CGFloat) -> CGFloat {
        safeTop + headerTopPad + headerHeight + 12
    }
}

/// Shared edge fades over `AnglesCanvasBackground` — softer than a solid bar, aligned with the tab-area gradient.
enum CanvasEdgeFade {
    static func topStops(theme: ColorTokens.Theme, strength: CGFloat) -> [Gradient.Stop] {
        [
            .init(color: theme.paper.opacity(0.86 * strength), location: 0),
            .init(color: theme.paper.opacity(0.52 * strength), location: 0.42),
            .init(color: theme.grey.opacity(0.28 * strength), location: 0.72),
            .init(color: .clear, location: 1),
        ]
    }

    static func bottomStops(theme: ColorTokens.Theme) -> [Gradient.Stop] {
        [
            .init(color: .clear, location: 0),
            .init(color: theme.grey.opacity(0.58), location: 0.58),
            .init(color: theme.grey.opacity(0.86), location: 1),
        ]
    }
}

/// Scroll state is retained by the screen, but only the small header views read it.
/// Distance is capped once collapse completes so a long feed fling stops publishing work.
@Observable
final class HeaderScrollState {
    private(set) var distance: CGFloat = 0

    func update(_ rawDistance: CGFloat) {
        let newValue = min(HeaderCollapse.maximumTrackedDistance, max(0, rawDistance))
        guard abs(distance - newValue) > 0.5 else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            distance = newValue
        }
    }
}

func filterSystemImage(_ filter: ProfileGridFilter) -> String {
    guard let style = filter.matchingStyle else {
        return "square.grid.2x2"
    }

    return CardStyleAppearance(style: style).systemImage
}

func filterSymbolColor(_ filter: ProfileGridFilter, ink: Color) -> Color {
    guard let style = filter.matchingStyle else {
        return ink
    }

    return CardStyleAppearance(style: style).ink
}

/// Compact nav title that fades and slides into the bar, matching UIKit inline titles.
struct CollapsedInlineTitle: View {
    let title: String
    let progress: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundStyle(theme.ink)
            .lineLimit(1)
            .opacity(progress)
            .offset(y: reduceMotion ? 0 : HeaderCollapse.collapseSlide * (1 - progress))
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHidden(progress <= 0.4)
    }
}

/// The collapsed chrome: icon + title + chevron, centered.
struct CollapsedFilterLabel: View {
    let filter: ProfileGridFilter

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: filterSystemImage(filter))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filterSymbolColor(filter, ink: theme.ink))

            Text(filter.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
        }
        .contentShape(Rectangle())
    }
}

struct GridFilterPicker: View {
    let selection: ProfileGridFilter
    let onSelect: (ProfileGridFilter) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ProfileGridFilter.allCases, id: \.self) { filter in
                let isSelected = selection == filter

                Button {
                    onSelect(filter)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: filterSystemImage(filter))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(filterSymbolColor(filter, ink: theme.ink))
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
}

/// The status-bar fade is the only background that follows continuous collapse progress.
struct CollapsingHeaderFade: View {
    let scrollState: HeaderScrollState
    let safeTop: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let progress = HeaderCollapse.restProgress(
            scrollState.distance,
            reduceMotion: reduceMotion
        )

        LinearGradient(
            stops: CanvasEdgeFade.topStops(theme: theme, strength: progress),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: HeaderCollapse.topFadeHeight(safeTop: safeTop))
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(nil, value: scrollState.distance)
    }
}

struct ScrollDistanceKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// Reports how far a scroll view has travelled without animating the report itself.
struct ProfileScrollDistance: ViewModifier {
    let state: HeaderScrollState

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y)
            } action: { _, newValue in
                state.update(newValue)
            }
        } else {
            content.onPreferenceChange(ScrollDistanceKey.self) { minY in
                guard let minY else { return }
                state.update(max(0, -minY))
            }
        }
    }
}

/// iOS 17 fallback probe for `ProfileScrollDistance`.
struct ScrollDistanceProbe: View {
    let space: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ScrollDistanceKey.self,
                value: proxy.frame(in: .named(space)).minY
            )
        }
        .frame(height: 0)
    }
}
