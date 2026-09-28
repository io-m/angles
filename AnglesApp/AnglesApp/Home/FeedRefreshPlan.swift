import Foundation

/// Newest-first ordering: the same `(createdAt, id)` the server pages with.
enum FeedOrder {
    /// True when `card` belongs above `other`.
    static func isBefore(_ card: HomeCard, _ other: HomeCard) -> Bool {
        if card.createdAt != other.createdAt {
            return card.createdAt > other.createdAt
        }
        return card.id.uuidString.lowercased() > other.id.uuidString.lowercased()
    }

    /// True when `card` is strictly newer than a mark already loaded.
    static func isNewer(_ card: HomeCard, than mark: FeedCardMark) -> Bool {
        if card.createdAt != mark.createdAt {
            return card.createdAt > mark.createdAt
        }
        return card.id.uuidString.lowercased() > mark.id
    }
}

/// The newest card a visit has loaded. Composite rather than a bare date: cards
/// can share a millisecond, and a date-only mark then re-counts or skips them.
struct FeedCardMark: Equatable {
    let createdAt: Date
    /// Lowercased UUID, matching the server's `createdAt|id` cursor.
    let id: String
    /// This mark as a cursor, so a refresh can ask the server for posts newer than it.
    let cursor: String

    init(_ card: HomeCard) {
        createdAt = card.createdAt
        id = card.id.uuidString.lowercased()
        cursor = card.pageCursor
    }
}

extension HomeCard {
    /// This card as a `createdAt|id` page cursor.
    var pageCursor: String {
        "\(createdAtCursor)|\(id.uuidString.lowercased())"
    }
}

/// What a Home pull-to-refresh should do with the pages it just fetched.
///
/// Arrivals never share a page with a rotated batch. A page that started today
/// and jumped to last week would hide every card in between, and the count in
/// the banner would be a lie.
enum FeedRefreshPlan: Equatable {
    /// Real new posts. They go above the loaded page, which stays put.
    case prepend(arrivals: [HomeCard])
    /// Nothing but arrivals came back, so more may be hiding behind the head's
    /// small limit. Reload the newest page instead of guessing.
    case catchUp(newCount: Int)
    /// Nothing new: show the next batch this visit has not shown yet.
    case rotate(Rotation)
    /// Nothing new and nothing older left unseen. Begin the rotation again.
    case restart
    /// Nothing on offer that is not already on screen.
    case unchanged

    struct Rotation: Equatable {
        let page: [HomeCard]
        /// `createdAt|id` of the last tail card this rotation consumed. Cards the
        /// page cap left untouched stay ahead of it, so nothing is skipped.
        let nextBefore: String
        /// False when the cap stopped before the tail ran out, so more is certain
        /// regardless of what the tail response said.
        let consumedWholeTail: Bool
    }
}

enum FeedRefreshPlanner {
    /// - Parameters:
    ///   - head: the newest page, or nil when that fetch did not land.
    ///   - headLimit: the limit the head was fetched with.
    ///   - tail: the page after the loaded cursor. Empty means nothing older exists.
    ///   - highWater: newest card loaded this visit. Nil means nothing is loaded.
    ///   - seenIDs: every card this visit has loaded, not just the page on screen.
    ///   - isRotated: whether a pull has already moved off the newest page.
    static func plan(
        head: [HomeCard]?,
        headLimit: Int,
        tail: [HomeCard],
        highWater: FeedCardMark?,
        seenIDs: Set<UUID>,
        pageSize: Int,
        isRotated: Bool
    ) -> FeedRefreshPlan {
        guard let highWater else {
            // Nothing is loaded, so the newest page is the whole answer.
            return head?.isEmpty == false ? .restart : .unchanged
        }

        let arrivals = (head ?? []).filter { FeedOrder.isNewer($0, than: highWater) }
        if !arrivals.isEmpty {
            if let head, head.count >= headLimit, arrivals.count == head.count {
                return .catchUp(newCount: arrivals.count)
            }
            return .prepend(arrivals: arrivals)
        }

        if let rotation = rotation(tail: tail, seenIDs: seenIDs, pageSize: pageSize) {
            return .rotate(rotation)
        }

        // Starting over only means something once a pull has moved off the newest
        // page. A catalog that fits on one page has nowhere to go.
        return isRotated ? .restart : .unchanged
    }

    private static func rotation(
        tail: [HomeCard],
        seenIDs: Set<UUID>,
        pageSize: Int
    ) -> FeedRefreshPlan.Rotation? {
        var page: [HomeCard] = []
        var consumed = 0
        for card in tail {
            if page.count >= pageSize {
                break
            }
            consumed += 1
            guard !seenIDs.contains(card.id) else {
                continue
            }
            page.append(card)
        }

        guard !page.isEmpty, let last = tail.prefix(consumed).last else {
            return nil
        }
        return FeedRefreshPlan.Rotation(
            page: page,
            nextBefore: last.pageCursor,
            consumedWholeTail: consumed == tail.count
        )
    }
}
