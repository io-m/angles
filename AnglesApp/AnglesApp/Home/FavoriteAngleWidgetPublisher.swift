import Foundation
import WidgetKit

enum FavoriteAngleWidgetPublisher {
    static let maximumItemCount = 12

    static func makeSnapshot(
        from cards: [HomeCard],
        updatedAt: Date = Date()
    ) -> FavoriteAngleWidgetSnapshot {
        let items = cards
            .flatMap { card in
                card.slides.compactMap { slide -> FavoriteAngleWidgetItem? in
                    guard slide.isFavorite else {
                        return nil
                    }
                    return FavoriteAngleWidgetItem(
                        id: "\(card.id.uuidString.lowercased())-\(slide.result.style.rawValue)",
                        cardID: card.id.uuidString.lowercased(),
                        answer: slide.result.reframe,
                        style: slide.result.style.rawValue,
                        styleDisplayName: slide.result.style.displayName,
                        lifeAreaLabel: card.lifeAreaPresentation?.label,
                        favoritedAt: slide.favoritedAt ?? card.createdAt
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.favoritedAt == rhs.favoritedAt {
                    return lhs.id < rhs.id
                }
                return lhs.favoritedAt > rhs.favoritedAt
            }

        return FavoriteAngleWidgetSnapshot(
            items: Array(items.prefix(maximumItemCount)),
            updatedAt: updatedAt
        )
    }

    static func publish(cards: [HomeCard]) {
        guard let store = WidgetSnapshotStore() else {
            return
        }
        let next = makeSnapshot(from: cards)
        guard store.loadFavoriteAngles().items != next.items else {
            return
        }
        if next.items.isEmpty {
            store.clearFavoriteAngles()
        } else {
            store.saveFavoriteAngles(next)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: AnglesWidgetConstants.favoriteWidgetKind)
    }
}
