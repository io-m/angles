import Foundation
import Testing
@testable import Angles

struct WidgetTests {
    @Test @MainActor
    func savedSnapshotIsNewestFirstAndContainsOnlySavedCards() {
        let older = makeCard(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            thought: "A private older thought",
            answer: "Older answer",
            savedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeCard(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            thought: "A private newer thought",
            answer: "Newer answer",
            savedAt: Date(timeIntervalSince1970: 200)
        )
        let passed = makeCard(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            thought: "This must not leave the app",
            answer: "Passed",
            savedAt: Date(timeIntervalSince1970: 300),
            kind: .pass
        )

        let snapshot = SavedAngleWidgetPublisher.makeSnapshot(
            from: [older, passed, newer],
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        #expect(snapshot.items.map(\.answer) == ["Newer answer", "Older answer"])
        #expect(snapshot.items.allSatisfy { !$0.answer.contains("private") })
        #expect(snapshot.items.map(\.styleDisplayName) == ["Stoic", "Stoic"])
    }

    @Test @MainActor
    func savedSnapshotIsBounded() {
        let cards = (0 ..< SavedAngleWidgetPublisher.maximumItemCount + 3).map { index in
            makeCard(
                id: UUID(),
                thought: "Private \(index)",
                answer: "Answer \(index)",
                savedAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        let snapshot = SavedAngleWidgetPublisher.makeSnapshot(from: cards)
        #expect(snapshot.items.count == SavedAngleWidgetPublisher.maximumItemCount)
        #expect(snapshot.items.first?.answer == "Answer 14")
    }

    @Test
    func snapshotStoreCanSaveAndClearPersonalText() {
        let suite = "WidgetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let item = SavedAngleWidgetItem(
            id: "card-stoic",
            cardID: "card",
            answer: "Kept answer",
            style: "stoic",
            styleDisplayName: "Stoic",
            lifeAreaLabel: "Work",
            savedAt: Date(timeIntervalSince1970: 100)
        )

        store.saveSavedAngles(SavedAngleWidgetSnapshot(items: [item], updatedAt: Date()))
        #expect(store.loadSavedAngles().items == [item])

        store.clearSavedAngles()
        #expect(store.loadSavedAngles() == .empty)
    }

    @Test
    func widgetURLsAcceptOnlyKnownAnglesRoutes() {
        #expect(AnglesDeepLink(url: URL(string: "angles://saved")!) == .saved)
        #expect(AnglesDeepLink(url: URL(string: "angles://compose")!) == .compose)
        #expect(AnglesDeepLink(url: URL(string: "angles://unknown")!) == nil)
        #expect(AnglesDeepLink(url: URL(string: "https://hearts")!) == nil)
    }

    @MainActor
    private func makeCard(
        id: UUID,
        thought: String,
        answer: String,
        savedAt: Date,
        kind: DecisionKind = .save
    ) -> HomeCard {
        HomeCard(
            id: id,
            createdAt: Date(timeIntervalSince1970: 10),
            slides: [
                HomeCardSlide(
                    id: UUID(),
                    thought: thought,
                    result: ReframeResult(style: .stoic, reframe: answer)
                ),
            ],
            decision: CardDecision(
                kind: kind,
                style: .stoic,
                checkedStyles: [.stoic],
                passes: kind == .pass ? 1 : 0,
                decidedAt: ISO8601Dates.string(from: savedAt)
            )
        )
    }
}
