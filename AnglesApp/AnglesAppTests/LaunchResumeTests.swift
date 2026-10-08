import Foundation
import Testing
@testable import Angles

struct ForYouMixTests {
    @Test func identicalOrderIsNotANewMix() {
        let ids = [
            UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
        ]
        #expect(ForYouMix.differs(pendingIDs: ids, onScreenIDs: ids) == false)
    }

    @Test func reorderedOrSwappedIdsAreANewMix() {
        let a = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        #expect(ForYouMix.differs(pendingIDs: [a, b], onScreenIDs: [b, a]))
        #expect(ForYouMix.differs(pendingIDs: [a], onScreenIDs: [a, b]))
    }
}

struct SessionSnapshotStoreTests {
    @Test func roundTripsAndClears() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SessionSnapshotStore(directory: directory)
        #expect(store.load() == nil)

        let body = SessionBody(
            id: "00000000-0000-4000-8000-000000000001",
            initials: "JM",
            name: "Josip",
            tasteCompletedAt: "2026-10-01T12:00:00.000Z",
            tasteConsumedAt: nil,
            termsAcceptedAt: "2026-10-01T12:00:00.000Z",
            avatarUrl: nil,
            notifyFollows: true
        )
        store.save(body)
        #expect(store.load() == body)

        store.delete()
        #expect(store.load() == nil)
    }
}

struct HomeFeedSnapshotStoreTests {
    @Test func loadsOnlyForMatchingAccount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = HomeFeedSnapshotStore(directory: directory)
        let userId = "00000000-0000-4000-8000-000000000001"
        let card = try Self.decodeCard()
        store.save(
            HomeFeedSnapshot(
                userId: userId,
                cards: [card],
                nextCursor: "seed|t|24",
                arrivalsAfter: "2026-10-08T10:00:00.000Z|\(card.id)",
                hasMore: true,
                savedAt: Date(timeIntervalSince1970: 1_775_000_000)
            )
        )

        #expect(store.load(userId: userId)?.cards.count == 1)
        #expect(store.load(userId: userId)?.nextCursor == "seed|t|24")
        #expect(store.load(userId: "00000000-0000-4000-8000-000000000099") == nil)

        store.delete()
        #expect(store.load(userId: userId) == nil)
    }

    private static func decodeCard() throws -> StoredCard {
        let json = """
        {
          "id": "22222222-2222-4222-8222-222222222222",
          "thought": "I keep waiting for a reply.",
          "inputLanguage": "en",
          "category": "work",
          "tags": [],
          "intensity": 3,
          "intensityBand": "mid",
          "timeframe": "ongoing",
          "emotions": [],
          "safety": "none",
          "skippedStyles": [],
          "matching": { "category": "work", "tags": [], "intensityBand": "mid" },
          "results": [
            { "style": "stoic", "reframe": "Wait without shrinking.", "isFavorite": false }
          ],
          "model": "mistral-small-latest",
          "spotlightStyle": "stoic",
          "isPublic": true,
          "createdAt": "2026-10-08T10:00:00.000Z",
          "isOwner": false,
          "author": { "id": "00000000-0000-4000-8000-000000000099", "initials": "AL", "following": false }
        }
        """
        return try JSONDecoder().decode(StoredCard.self, from: Data(json.utf8))
    }
}
