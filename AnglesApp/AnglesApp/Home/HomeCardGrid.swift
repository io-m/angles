import SwiftUI

struct HomeCardGrid: View, Equatable {
    let cards: [HomeCard]
    var rowSpacing: CGFloat = HeaderCollapse.horizontalPadding
    var presentation: ReframeCardPresentation = .library
    var openingStyle: Style? = nil
    var menuRole: (HomeCard) -> ReframeCardMenuRole = { card in
        card.isOwner ? .owner : .savedFromFeed
    }
    var onDelete: (HomeCard) -> Void = { _ in }
    var onToggleFavorite: (HomeCard, Style) -> Void = { _, _ in }
    var onSetPublic: (HomeCard, Bool) -> Void = { _, _ in }
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }
    /// Fires before the end is visible, so a server-paged grid can append off screen.
    var onReachEnd: (() -> Void)? = nil
    var loadMorePrefetchDistance = 0

    static func == (lhs: HomeCardGrid, rhs: HomeCardGrid) -> Bool {
        lhs.cards == rhs.cards
            && lhs.rowSpacing == rhs.rowSpacing
            && lhs.presentation == rhs.presentation
            && lhs.openingStyle == rhs.openingStyle
            && lhs.loadMorePrefetchDistance == rhs.loadMorePrefetchDistance
    }

    var body: some View {
        LazyVStack(spacing: rowSpacing) {
            ForEach(cards) { card in
                ReframeCardView(
                    card: card,
                    presentation: presentation,
                    menuRole: menuRole(card),
                    openingStyle: openingStyleFor(card),
                    onDelete: { onDelete(card) },
                    onToggleFavorite: { style in onToggleFavorite(card, style) },
                    onSetPublic: { isPublic in onSetPublic(card, isPublic) },
                    onRemoveFromBoard: { onRemoveFromBoard(card) }
                )
                .equatable()
                .onAppear {
                    guard let onReachEnd, card.id == loadMoreTriggerID else {
                        return
                    }
                    onReachEnd()
                }
            }
        }
    }

    private var loadMoreTriggerID: UUID? {
        guard !cards.isEmpty else {
            return nil
        }
        let configuredDistance = max(0, loadMorePrefetchDistance)
        let adaptiveDistance = min(configuredDistance, max(1, cards.count / 4))
        let distance = min(adaptiveDistance, cards.count - 1)
        return cards[cards.count - 1 - distance].id
    }

    /// `ForEach` keys on `card.id` alone. An explicit identity that folded in favorite state
    /// rebuilt the card on every heart, which reset its selected style.
    private func openingStyleFor(_ card: HomeCard) -> Style? {
        switch presentation {
        case .favoriteAngles:
            return card.latestFavoriteStyle
        case .library, .tallLibrary:
            return openingStyle
        }
    }
}

/// Experiment (tall Home cards): one card per row, sized to its text.
/// Neighbors scale down slightly as they leave the viewport.
struct TallHomeCardGrid: View, Equatable {
    let cards: [HomeCard]
    /// Viewport cap. Cards stay shorter than this; the reply scrolls if they would pass it.
    var cardMaxHeight: CGFloat = 520
    var rowSpacing: CGFloat = HeaderCollapse.horizontalPadding
    var openingStyle: Style? = nil
    var menuRole: (HomeCard) -> ReframeCardMenuRole = { card in
        card.isOwner ? .owner : .feed
    }
    var onDelete: (HomeCard) -> Void = { _ in }
    var onToggleFavorite: (HomeCard, Style) -> Void = { _, _ in }
    var onSetPublic: (HomeCard, Bool) -> Void = { _, _ in }
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }
    /// Fires before the end is visible, so a server-paged grid can append off screen.
    var onReachEnd: (() -> Void)? = nil
    var loadMorePrefetchDistance = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (lhs: TallHomeCardGrid, rhs: TallHomeCardGrid) -> Bool {
        lhs.cards == rhs.cards
            && lhs.cardMaxHeight == rhs.cardMaxHeight
            && lhs.rowSpacing == rhs.rowSpacing
            && lhs.openingStyle == rhs.openingStyle
            && lhs.loadMorePrefetchDistance == rhs.loadMorePrefetchDistance
    }

    var body: some View {
        LazyVStack(spacing: rowSpacing) {
            ForEach(cards) { card in
                ReframeCardView(
                    card: card,
                    presentation: .tallLibrary,
                    menuRole: menuRole(card),
                    openingStyle: openingStyle,
                    tallCardMaxHeight: cardMaxHeight,
                    onDelete: { onDelete(card) },
                    onToggleFavorite: { style in onToggleFavorite(card, style) },
                    onSetPublic: { isPublic in onSetPublic(card, isPublic) },
                    onRemoveFromBoard: { onRemoveFromBoard(card) }
                )
                .equatable()
                .modifier(TallCardFocusTransition(enabled: !reduceMotion))
                .onAppear {
                    guard let onReachEnd, card.id == loadMoreTriggerID else {
                        return
                    }
                    onReachEnd()
                }
            }
        }
    }

    private var loadMoreTriggerID: UUID? {
        guard !cards.isEmpty else {
            return nil
        }
        let configuredDistance = max(0, loadMorePrefetchDistance)
        let adaptiveDistance = min(configuredDistance, max(1, cards.count / 4))
        let distance = min(adaptiveDistance, cards.count - 1)
        return cards[cards.count - 1 - distance].id
    }
}

/// Focus effect: the settled card is full size; neighbors scale down as they travel in.
private struct TallCardFocusTransition: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.scrollTransition(.interactive, axis: .vertical) { effect, phase in
                let distance = CGFloat(min(1, abs(phase.value)))
                return effect.scaleEffect(1 - (0.04 * distance))
            }
        } else {
            content
        }
    }
}
