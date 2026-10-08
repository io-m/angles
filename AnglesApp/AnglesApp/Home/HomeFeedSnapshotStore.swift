import Foundation

/// Last For you page this account saw. Cold launch paints it immediately; the live
/// mix is parked until the user asks for it.
struct HomeFeedSnapshot: Codable, Equatable, Sendable {
    var userId: String
    var cards: [StoredCard]
    var nextCursor: String?
    var arrivalsAfter: String?
    var hasMore: Bool
    var savedAt: Date

    init(
        userId: String,
        cards: [StoredCard],
        nextCursor: String?,
        arrivalsAfter: String?,
        hasMore: Bool,
        savedAt: Date
    ) {
        self.userId = userId
        self.cards = cards
        self.nextCursor = nextCursor
        self.arrivalsAfter = arrivalsAfter
        self.hasMore = hasMore
        self.savedAt = savedAt
    }

    /// One card a later build cannot read drops that card, not the whole cold-launch page.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        cards = try container.decode([Failable<StoredCard>].self, forKey: .cards).compactMap(\.value)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        arrivalsAfter = try container.decodeIfPresent(String.self, forKey: .arrivalsAfter)
        hasMore = try container.decode(Bool.self, forKey: .hasMore)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
    }
}

enum ForYouMix {
    /// Ranked pages are a new visit, not an insert-on-top. Any change of ids or order
    /// is a different mix.
    static func differs(pendingIDs: [UUID], onScreenIDs: [UUID]) -> Bool {
        pendingIDs != onScreenIDs
    }
}

struct HomeFeedSnapshotStore: Sendable {
    private let fileURL: URL

    init(directory: URL = HomeFeedSnapshotStore.defaultDirectory()) {
        fileURL = directory.appendingPathComponent("foryou.json", isDirectory: false)
    }

    func load(userId: String) -> HomeFeedSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(HomeFeedSnapshot.self, from: data),
              snapshot.userId == userId,
              !snapshot.cards.isEmpty
        else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: HomeFeedSnapshot) {
        guard !snapshot.cards.isEmpty else {
            delete()
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Home still has the in-memory page; the next launch just waits on the network.
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func defaultDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("angles", isDirectory: true)
    }
}
