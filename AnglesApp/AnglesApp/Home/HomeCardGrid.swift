import SwiftUI

struct HomeCardGrid: View, Equatable {
    let cards: [HomeCard]
    let usesSingleColumn: Bool
    let spacing: CGFloat
    var onDelete: (HomeCard) -> Void = { _ in }
    var onToggleFavorite: (HomeCard) -> Void = { _ in }

    static func == (lhs: HomeCardGrid, rhs: HomeCardGrid) -> Bool {
        lhs.cards == rhs.cards
            && lhs.usesSingleColumn == rhs.usesSingleColumn
            && lhs.spacing == rhs.spacing
    }

    private var columns: [GridItem] {
        if usesSingleColumn {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing),
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(cards) { card in
                ReframeCardView(
                    card: card,
                    onDelete: { onDelete(card) },
                    onToggleFavorite: { onToggleFavorite(card) }
                )
            }
        }
    }
}
