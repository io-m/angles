import Foundation
import WidgetKit

enum HeartAngleWidgetPublisher {
    static let maximumItemCount = 12

    static func makeSnapshot(
        from cards: [HomeCard],
        updatedAt: Date = Date()
    ) -> HeartAngleWidgetSnapshot {
        let items = cards
            .flatMap { card in
                card.slides.compactMap { slide -> HeartAngleWidgetItem? in
                    guard slide.isHearted else {
                        return nil
                    }
                    return HeartAngleWidgetItem(
                        id: "\(card.id.uuidString.lowercased())-\(slide.result.style.rawValue)",
                        cardID: card.id.uuidString.lowercased(),
                        answer: slide.result.reframe,
                        style: slide.result.style.rawValue,
                        styleDisplayName: slide.result.style.displayName,
                        lifeAreaLabel: card.lifeAreaPresentation?.label,
                        heartedAt: slide.heartedAt ?? card.createdAt
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.heartedAt == rhs.heartedAt {
                    return lhs.id < rhs.id
                }
                return lhs.heartedAt > rhs.heartedAt
            }

        return HeartAngleWidgetSnapshot(
            items: Array(items.prefix(maximumItemCount)),
            updatedAt: updatedAt
        )
    }

    /// What this process last wrote or read, so an unchanged library skips the disk.
    @MainActor private static var lastPublishedItems: [HeartAngleWidgetItem]?

    @MainActor
    static func publish(cards: [HomeCard]) {
        let next = makeSnapshot(from: cards)
        guard next.items != lastPublishedItems else {
            return
        }
        guard let store = WidgetSnapshotStore() else {
            return
        }
        guard store.loadHeartAngles().items != next.items else {
            lastPublishedItems = next.items
            return
        }
        lastPublishedItems = next.items
        if next.items.isEmpty {
            store.clearHeartAngles()
        } else {
            store.saveHeartAngles(next)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: AnglesWidgetConstants.heartWidgetKind)
    }
}
