import SwiftUI

struct HomeCardGrid: View, Equatable {
    let cards: [HomeCard]
    let usesSingleColumn: Bool
    var columnSpacing: CGFloat = 12
    var rowSpacing: CGFloat = 16
    var presentation: ReframeCardPresentation = .library
    var openingStyle: Style? = nil
    var menuRole: (HomeCard) -> ReframeCardMenuRole = { card in
        card.isOwner ? .owner : .savedFromFeed
    }
    var onDelete: (HomeCard) -> Void = { _ in }
    var onToggleFavorite: (HomeCard, Style) -> Void = { _, _ in }
    var onSetPublic: (HomeCard, Bool) -> Void = { _, _ in }
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }
    /// Fires when the last cell is mounted, so a server-paged grid can ask for more.
    var onReachEnd: (() -> Void)? = nil

    static func == (lhs: HomeCardGrid, rhs: HomeCardGrid) -> Bool {
        lhs.cards == rhs.cards
            && lhs.usesSingleColumn == rhs.usesSingleColumn
            && lhs.columnSpacing == rhs.columnSpacing
            && lhs.rowSpacing == rhs.rowSpacing
            && lhs.presentation == rhs.presentation
            && lhs.openingStyle == rhs.openingStyle
    }

    private var columns: [GridItem] {
        if usesSingleColumn {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(.flexible(), spacing: columnSpacing),
            GridItem(.flexible(), spacing: columnSpacing),
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: rowSpacing) {
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
                    guard let onReachEnd, card.id == cards.last?.id else {
                        return
                    }
                    onReachEnd()
                }
            }
        }
    }

    /// `ForEach` keys on `card.id` alone. An explicit identity that folded in favorite state
    /// rebuilt the card on every heart, which reset its selected style.
    private func openingStyleFor(_ card: HomeCard) -> Style? {
        switch presentation {
        case .favoriteAngles:
            return card.latestFavoriteStyle
        case .library:
            return openingStyle
        }
    }
}
