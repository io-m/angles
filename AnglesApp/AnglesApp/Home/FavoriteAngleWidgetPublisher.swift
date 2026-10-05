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

    /// What this process last wrote or read, so an unchanged library skips the disk.
    @MainActor private static var lastPublishedItems: [FavoriteAngleWidgetItem]?

    @MainActor
    static func publish(cards: [HomeCard]) {
        let next = makeSnapshot(from: cards)
        guard next.items != lastPublishedItems else {
            return
        }
        guard let store = WidgetSnapshotStore() else {
            return
        }
        guard store.loadFavoriteAngles().items != next.items else {
            lastPublishedItems = next.items
            return
        }
        lastPublishedItems = next.items
        if next.items.isEmpty {
            store.clearFavoriteAngles()
        } else {
            store.saveFavoriteAngles(next)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: AnglesWidgetConstants.favoriteWidgetKind)
    }
}
