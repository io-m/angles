import SwiftUI

/// Collapse language shared by Home and Profile: a left-aligned title row at rest that
/// fades into a centered filter chip as the page scrolls.
enum HeaderCollapse {
    static let horizontalPadding: CGFloat = 16
    static let headerHeight: CGFloat = 44
    static let headerTopPad: CGFloat = 6
    static let headerContentGap: CGFloat = 18
    static let sectionContentGap: CGFloat = 16
    static let restFadeDistance: CGFloat = 44
    static let collapsedRevealDistance: CGFloat = 36
    static let collapseSlide: CGFloat = 10

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
