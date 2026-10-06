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

/// Where a pull starts looking for new posts. Composite rather than a bare date: cards
/// can share a millisecond, and a date-only mark then re-counts or skips them.
///
/// Under ranking this is the server's `arrivalsAfter`, the newest card the visit could
/// show, and not the newest card on screen: a ranked page need not hold the newest posts,
/// and asking after the newest one shown brings back older posts as if they were new.
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

    /// A server `createdAt|id` cursor. Nil when it does not parse.
    init?(cursor raw: String) {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let date = ISO8601Dates.date(from: String(parts[0])),
              UUID(uuidString: String(parts[1])) != nil
        else {
            return nil
        }
        createdAt = date
        id = String(parts[1]).lowercased()
        cursor = raw
    }

    /// The later of two marks, so a mark only ever moves forward.
    static func latest(_ left: FeedCardMark?, _ right: FeedCardMark?) -> FeedCardMark? {
        guard let left else {
            return right
        }
        guard let right else {
            return left
        }
        if left.createdAt != right.createdAt {
            return left.createdAt > right.createdAt ? left : right
        }
        return left.id >= right.id ? left : right
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
    /// Nothing new: move the cards the reader has not reached yet to the top, followed by
    /// the next page this visit has not loaded.
    case rotate(Rotation)
    /// Nothing new and nothing older left unseen. Begin the rotation again.
    case restart
    /// Nothing on offer that is not already on screen.
    case unchanged

    struct Rotation: Equatable {
        let page: [HomeCard]
        /// `createdAt|id` of the last tail card this rotation consumed, or nil when it
        /// took none (the shelf keeps its cursor). Cards the page cap left untouched stay
        /// ahead of it, so nothing is skipped.
        let nextBefore: String?
        /// False when the cap stopped before the tail ran out, so more is certain
        /// regardless of what the tail response said.
        let consumedWholeTail: Bool
    }
}

enum FeedRefreshPlanner {
    /// - Parameters:
    ///   - head: arrivals after `highWater` (or the newest page when nothing is loaded),
    ///     nil when that fetch did not land.
    ///   - headLimit: the limit the head was fetched with.
    ///   - tail: the page after the loaded cursor. Empty means nothing older exists.
    ///   - highWater: where arrivals start. Nil means nothing is loaded.
    ///   - seenIDs: every card this visit has loaded, not just the page on screen.
    ///   - onShelf: the cards on the shelf now, top to bottom.
    ///   - displayedIDs: cards this visit has put on screen. A loaded card that never
    ///     reached the screen is still unread, so a rotation brings it up first.
    ///   - isRotated: whether a pull has already moved off the newest page.
    static func plan(
        head: [HomeCard]?,
        headLimit: Int,
        tail: [HomeCard],
        highWater: FeedCardMark?,
        seenIDs: Set<UUID>,
        onShelf: [HomeCard] = [],
        displayedIDs: Set<UUID> = [],
        pageSize: Int,
        isRotated: Bool
    ) -> FeedRefreshPlan {
        guard let highWater else {
            // Nothing is loaded, so the newest page is the whole answer.
            return head?.isEmpty == false ? .restart : .unchanged
        }

        // A card already on the shelf (your own new post, placed when you published it)
        // is not news.
        let arrivals = (head ?? []).filter {
            FeedOrder.isNewer($0, than: highWater) && !seenIDs.contains($0.id)
        }
        if !arrivals.isEmpty {
            if let head, head.count >= headLimit, arrivals.count == head.count {
                return .catchUp(newCount: arrivals.count)
            }
            return .prepend(arrivals: arrivals)
        }

        if let rotation = rotation(
            tail: tail,
            seenIDs: seenIDs,
            onShelf: onShelf,
            displayedIDs: displayedIDs,
            pageSize: pageSize
        ) {
            return .rotate(rotation)
        }

        // Starting over only means something once a pull has moved off the newest
        // page. A catalog that fits on one page has nowhere to go.
        return isRotated ? .restart : .unchanged
    }

    private static func rotation(
        tail: [HomeCard],
        seenIDs: Set<UUID>,
        onShelf: [HomeCard],
        displayedIDs: Set<UUID>,
        pageSize: Int
    ) -> FeedRefreshPlan.Rotation? {
        // Cards below where the reader got to, in the order the server ranked them.
        let unread = onShelf.filter { !displayedIDs.contains($0.id) }

        var fresh: [HomeCard] = []
        var consumed = 0
        for card in tail {
            if fresh.count >= pageSize {
                break
            }
            consumed += 1
            guard !seenIDs.contains(card.id) else {
                continue
            }
            fresh.append(card)
        }

        // Nothing read yet and nothing new behind it: the same page again is no rotation.
        if fresh.isEmpty, unread.count == onShelf.count {
            return nil
        }
        let page = unread + fresh
        guard !page.isEmpty else {
            return nil
        }
        return FeedRefreshPlan.Rotation(
            page: page,
            nextBefore: tail.prefix(consumed).last?.pageCursor,
            consumedWholeTail: consumed == tail.count
        )
    }
}
