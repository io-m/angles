import Foundation
import Testing
@testable import Angles

struct WidgetTests {
    @Test @MainActor
    func favoriteSnapshotIsNewestFirstAndContainsOnlyFavoriteAnswers() {
        let older = makeCard(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            thought: "A private older thought",
            answer: "Older answer",
            favoritedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeCard(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            thought: "A private newer thought",
            answer: "Newer answer",
            favoritedAt: Date(timeIntervalSince1970: 200)
        )
        let notFavorite = makeCard(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            thought: "This must not leave the app",
            answer: "Not favorite",
            favoritedAt: nil,
            isFavorite: false
        )

        let snapshot = FavoriteAngleWidgetPublisher.makeSnapshot(
            from: [older, notFavorite, newer],
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        #expect(snapshot.items.map(\.answer) == ["Newer answer", "Older answer"])
        #expect(snapshot.items.allSatisfy { !$0.answer.contains("private") })
        #expect(snapshot.items.map(\.styleDisplayName) == ["Stoic", "Stoic"])
    }

    @Test @MainActor
    func favoriteSnapshotIsBounded() {
        let cards = (0 ..< FavoriteAngleWidgetPublisher.maximumItemCount + 3).map { index in
            makeCard(
                id: UUID(),
                thought: "Private \(index)",
                answer: "Answer \(index)",
                favoritedAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        let snapshot = FavoriteAngleWidgetPublisher.makeSnapshot(from: cards)
        #expect(snapshot.items.count == FavoriteAngleWidgetPublisher.maximumItemCount)
        #expect(snapshot.items.first?.answer == "Answer 14")
    }

    @Test
    func snapshotStoreCanSaveAndClearPersonalText() {
        let suite = "WidgetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let item = FavoriteAngleWidgetItem(
            id: "card-stoic",
            cardID: "card",
            answer: "Kept answer",
            style: "stoic",
            styleDisplayName: "Stoic",
            lifeAreaLabel: "Work",
            favoritedAt: Date(timeIntervalSince1970: 100)
        )

        store.saveFavoriteAngles(FavoriteAngleWidgetSnapshot(items: [item], updatedAt: Date()))
        #expect(store.loadFavoriteAngles().items == [item])

        store.clearFavoriteAngles()
        #expect(store.loadFavoriteAngles() == .empty)
    }

    @Test
    func widgetURLsAcceptOnlyKnownAnglesRoutes() {
        #expect(AnglesDeepLink(url: URL(string: "angles://favorites")!) == .favorites)
        #expect(AnglesDeepLink(url: URL(string: "angles://compose")!) == .compose)
        #expect(AnglesDeepLink(url: URL(string: "angles://unknown")!) == nil)
        #expect(AnglesDeepLink(url: URL(string: "https://favorites")!) == nil)
    }

    @MainActor
    private func makeCard(
        id: UUID,
        thought: String,
        answer: String,
        favoritedAt: Date?,
        isFavorite: Bool = true
    ) -> HomeCard {
        HomeCard(
            id: id,
            createdAt: Date(timeIntervalSince1970: 10),
            slides: [
                HomeCardSlide(
                    id: UUID(),
                    thought: thought,
                    result: ReframeResult(style: .stoic, reframe: answer),
                    isFavorite: isFavorite,
                    favoritedAt: favoritedAt,
                    heartCount: nil
                ),
            ]
        )
    }
}
