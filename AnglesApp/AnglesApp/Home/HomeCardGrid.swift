import SwiftUI

struct HomeCardGrid: View, Equatable {
    let cards: [HomeCard]
    let usesSingleColumn: Bool
    var columnSpacing: CGFloat = 12
    var rowSpacing: CGFloat = 8
    var presentation: ReframeCardPresentation = .library
    var openingStyle: Style? = nil
    var onDelete: (HomeCard) -> Void = { _ in }
    var onToggleFavorite: (HomeCard, Style) -> Void = { _, _ in }
    var onTogglePin: (HomeCard) -> Void = { _ in }
    var onSetPublic: (HomeCard, Bool) -> Void = { _, _ in }

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
                    openingStyle: openingStyleFor(card),
                    onDelete: { onDelete(card) },
                    onToggleFavorite: { style in onToggleFavorite(card, style) },
                    onTogglePin: { onTogglePin(card) },
                    onSetPublic: { isPublic in onSetPublic(card, isPublic) }
                )
                .id(cardIdentity(card))
            }
        }
    }

    private func openingStyleFor(_ card: HomeCard) -> Style? {
        switch presentation {
        case .favoriteAngles:
            return card.latestFavoriteStyle
        case .library, .pinned:
            return openingStyle
        }
    }

    private func cardIdentity(_ card: HomeCard) -> String {
        let liked = card.slides.filter(\.isFavorite).map(\.result.style.rawValue).joined(separator: ",")
        return "\(card.id.uuidString)-\(presentation.rawValue)-\(openingStyle?.rawValue ?? "all")-\(liked)"
    }
}
