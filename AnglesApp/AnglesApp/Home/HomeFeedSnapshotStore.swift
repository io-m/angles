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
