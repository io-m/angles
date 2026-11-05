import Foundation
import WidgetKit

enum SavedAngleWidgetPublisher {
    static let maximumItemCount = 12

    static func makeSnapshot(
        from cards: [HomeCard],
        updatedAt: Date = Date()
    ) -> SavedAngleWidgetSnapshot {
        // One item per saved card, on the angle it was saved from.
        let items = cards
            .compactMap { card -> SavedAngleWidgetItem? in
                guard let decision = card.decision, decision.kind == .save,
                      let slide = card.slide(for: decision.style) ?? card.slides.first
                else {
                    return nil
                }
                return SavedAngleWidgetItem(
                    id: "\(card.id.uuidString.lowercased())-\(slide.result.style.rawValue)",
                    cardID: card.id.uuidString.lowercased(),
                    answer: slide.result.reframe,
                    style: slide.result.style.rawValue,
                    styleDisplayName: slide.result.style.displayName,
                    lifeAreaLabel: card.lifeAreaPresentation?.label,
                    savedAt: ISO8601Dates.date(from: decision.decidedAt) ?? card.createdAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.savedAt == rhs.savedAt {
                    return lhs.id < rhs.id
                }
                return lhs.savedAt > rhs.savedAt
            }

        return SavedAngleWidgetSnapshot(
            items: Array(items.prefix(maximumItemCount)),
            updatedAt: updatedAt
        )
    }

    /// What this process last wrote or read, so an unchanged library skips the disk.
    @MainActor private static var lastPublishedItems: [SavedAngleWidgetItem]?

    @MainActor
    static func publish(cards: [HomeCard]) {
        let next = makeSnapshot(from: cards)
        guard next.items != lastPublishedItems else {
            return
        }
        guard let store = WidgetSnapshotStore() else {
            return
        }
        guard store.loadSavedAngles().items != next.items else {
            lastPublishedItems = next.items
            return
        }
        lastPublishedItems = next.items
        if next.items.isEmpty {
            store.clearSavedAngles()
        } else {
            store.saveSavedAngles(next)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: AnglesWidgetConstants.savedWidgetKind)
    }
}
