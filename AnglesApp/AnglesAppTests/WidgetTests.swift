import Foundation
import Testing
@testable import Angles

struct WidgetTests {
    @Test @MainActor
    func heartSnapshotIsNewestFirstAndContainsOnlyHeartAnswers() {
        let older = makeCard(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            thought: "A private older thought",
            answer: "Older answer",
            heartedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeCard(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            thought: "A private newer thought",
            answer: "Newer answer",
            heartedAt: Date(timeIntervalSince1970: 200)
        )
        let notHeart = makeCard(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            thought: "This must not leave the app",
            answer: "Not heart",
            heartedAt: nil,
            isHearted: false
        )

        let snapshot = HeartAngleWidgetPublisher.makeSnapshot(
            from: [older, notHeart, newer],
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        #expect(snapshot.items.map(\.answer) == ["Newer answer", "Older answer"])
        #expect(snapshot.items.allSatisfy { !$0.answer.contains("private") })
        #expect(snapshot.items.map(\.styleDisplayName) == ["Stoic", "Stoic"])
    }

    @Test @MainActor
    func heartSnapshotIsBounded() {
        let cards = (0 ..< HeartAngleWidgetPublisher.maximumItemCount + 3).map { index in
            makeCard(
                id: UUID(),
                thought: "Private \(index)",
                answer: "Answer \(index)",
                heartedAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        let snapshot = HeartAngleWidgetPublisher.makeSnapshot(from: cards)
        #expect(snapshot.items.count == HeartAngleWidgetPublisher.maximumItemCount)
        #expect(snapshot.items.first?.answer == "Answer 14")
    }

    @Test
    func snapshotStoreCanSaveAndClearPersonalText() {
        let suite = "WidgetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let item = HeartAngleWidgetItem(
            id: "card-stoic",
            cardID: "card",
            answer: "Kept answer",
            style: "stoic",
            styleDisplayName: "Stoic",
            lifeAreaLabel: "Work",
            heartedAt: Date(timeIntervalSince1970: 100)
        )

        store.saveHeartAngles(HeartAngleWidgetSnapshot(items: [item], updatedAt: Date()))
        #expect(store.loadHeartAngles().items == [item])

        store.clearHeartAngles()
        #expect(store.loadHeartAngles() == .empty)
    }

    @Test
    func widgetURLsAcceptOnlyKnownAnglesRoutes() {
        #expect(AnglesDeepLink(url: URL(string: "angles://hearts")!) == .hearts)
        #expect(AnglesDeepLink(url: URL(string: "angles://compose")!) == .compose)
        #expect(AnglesDeepLink(url: URL(string: "angles://unknown")!) == nil)
        #expect(AnglesDeepLink(url: URL(string: "https://hearts")!) == nil)
    }

    @MainActor
    private func makeCard(
        id: UUID,
        thought: String,
        answer: String,
        heartedAt: Date?,
        isHearted: Bool = true
    ) -> HomeCard {
        HomeCard(
            id: id,
            createdAt: Date(timeIntervalSince1970: 10),
            slides: [
                HomeCardSlide(
                    id: UUID(),
                    thought: thought,
                    result: ReframeResult(style: .stoic, reframe: answer),
                    isHearted: isHearted,
                    heartedAt: heartedAt,
                    heartCount: nil
                ),
            ]
        )
    }
}
