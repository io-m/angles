import Foundation
import Testing
@testable import Angles

private let base = Date(timeIntervalSince1970: 1_790_000_000)

private func card(
    _ minutesOld: Int,
    id: UUID = UUID(),
    style: Style = .stoic
) -> HomeCard {
    let createdAt = base.addingTimeInterval(TimeInterval(-60 * minutesOld))
    return HomeCard(
        id: id,
        createdAt: createdAt,
        slides: [
            HomeCardSlide(
                id: UUID(),
                thought: "A thought.",
                result: ReframeResult(style: style, reframe: "An answer."),
                isFavorite: false
            )
        ],
        spotlightStyle: style,
        isPublic: true,
        isOwner: false
    )
}

/// Two cards sharing a millisecond, ordered the way the server pages them.
private func twins() -> (high: HomeCard, low: HomeCard) {
    let first = card(30, id: UUID(uuidString: "00000000-0000-4000-8000-0000000000ff")!)
    let second = card(30, id: UUID(uuidString: "00000000-0000-4000-8000-000000000011")!)
    return (first, second)
}

private func plan(
    head: [HomeCard]? = [],
    headLimit: Int = 8,
    tail: [HomeCard] = [],
    highWater: FeedCardMark?,
    seen: Set<UUID> = [],
    onShelf: [HomeCard] = [],
    displayed: Set<UUID> = [],
    pageSize: Int = 24,
    isRotated: Bool = false
) -> FeedRefreshPlan {
    FeedRefreshPlanner.plan(
        head: head,
        headLimit: headLimit,
        tail: tail,
        highWater: highWater,
        seenIDs: seen,
        onShelf: onShelf,
        displayedIDs: displayed,
        pageSize: pageSize,
        isRotated: isRotated
    )
}

@Suite("Feed refresh planner")
struct FeedRefreshPlanTests {
    @Test("nothing loaded yet takes the newest page")
    func coldRefresh() {
        #expect(plan(head: [card(1)], highWater: nil) == .restart)
        #expect(plan(head: [], highWater: nil) == .unchanged)
    }

    @Test("arrivals win over a ready tail")
    func arrivalsBeatRotation() {
        let loaded = card(60)
        let arrival = card(1)
        let older = card(600)
        let result = plan(
            head: [arrival, loaded],
            tail: [older],
            highWater: FeedCardMark(loaded),
            seen: [loaded.id],
            isRotated: false
        )
        #expect(result == .prepend(arrivals: [arrival]))
    }

    @Test("a head that is nothing but arrivals reloads instead of guessing")
    func fullHeadOfArrivals() {
        let loaded = card(600)
        let arrivals = (1 ... 8).map { card($0) }
        let result = plan(
            head: arrivals,
            headLimit: 8,
            tail: [card(900)],
            highWater: FeedCardMark(loaded),
            seen: [loaded.id]
        )
        #expect(result == .catchUp(newCount: 8))
    }

    @Test("a card sharing the newest millisecond is not counted twice")
    func equalTimestampsAreNotArrivals() {
        let (high, low) = twins()
        // `high` is the mark, so its twin below it must not read as new.
        let result = plan(
            head: [high, low],
            tail: [card(900)],
            highWater: FeedCardMark(high),
            seen: [high.id],
            isRotated: false
        )
        #expect(result != .prepend(arrivals: [low]))
        if case .rotate = result {} else {
            Issue.record("expected a rotation, got \(result)")
        }
    }

    @Test("the twin above the mark is still an arrival")
    func higherTwinIsAnArrival() {
        let (high, low) = twins()
        let result = plan(head: [high, low], highWater: FeedCardMark(low), seen: [low.id])
        #expect(result == .prepend(arrivals: [high]))
    }

    @Test("rotation drops cards this visit already showed")
    func rotationSkipsSeen() {
        let loaded = card(10)
        let seenAgain = card(100)
        let fresh = card(200)
        let result = plan(
            head: [loaded],
            tail: [seenAgain, fresh],
            highWater: FeedCardMark(loaded),
            seen: [loaded.id, seenAgain.id]
        )
        #expect(result == .rotate(.init(page: [fresh], nextBefore: fresh.pageCursor, consumedWholeTail: true)))
    }

    @Test("the cap keeps the cursor on the last card it consumed")
    func capStopsTheCursor() {
        let loaded = card(10)
        let tail = (1 ... 4).map { card(100 + $0) }
        let result = plan(
            head: [loaded],
            tail: tail,
            highWater: FeedCardMark(loaded),
            seen: [loaded.id],
            pageSize: 2
        )
        #expect(
            result == .rotate(
                .init(page: [tail[0], tail[1]], nextBefore: tail[1].pageCursor, consumedWholeTail: false)
            )
        )
    }

    @Test("an exhausted tail restarts once a pull has rotated")
    func exhaustedTailRestarts() {
        let loaded = card(500)
        #expect(
            plan(head: [loaded], tail: [], highWater: FeedCardMark(loaded), seen: [loaded.id], isRotated: true)
                == .restart
        )
    }

    @Test("a fully seen tail restarts rather than dead-ending")
    func fullySeenTailRestarts() {
        let loaded = card(500)
        let old = card(900)
        let result = plan(
            head: [loaded],
            tail: [old],
            highWater: FeedCardMark(loaded),
            seen: [loaded.id, old.id],
            isRotated: true
        )
        #expect(result == .restart)
    }

    @Test("a catalog that fits on one page reports unchanged")
    func smallCatalogIsUnchanged() {
        let loaded = (1 ... 20).map { card($0 * 10) }
        let newest = loaded[0]
        let result = plan(
            head: Array(loaded.prefix(8)),
            tail: [],
            highWater: FeedCardMark(newest),
            seen: Set(loaded.map(\.id)),
            isRotated: false
        )
        #expect(result == .unchanged)
    }

    @Test("a head that did not land still rotates on the tail")
    func headFailureStillRotates() {
        let loaded = card(10)
        let older = card(400)
        let result = plan(
            head: nil,
            tail: [older],
            highWater: FeedCardMark(loaded),
            seen: [loaded.id]
        )
        #expect(result == .rotate(.init(page: [older], nextBefore: older.pageCursor, consumedWholeTail: true)))
    }

    @Test("a card already on the shelf is not an arrival")
    func seenCardIsNotAnArrival() {
        // Your own post, placed at the top when you published it, comes back after the mark.
        let mine = card(1)
        let loaded = card(60)
        let result = plan(
            head: [mine],
            tail: [],
            highWater: FeedCardMark(loaded),
            seen: [mine.id, loaded.id]
        )
        #expect(result == .unchanged)
    }

    @Test("a full head that is partly your own cards prepends only the rest")
    func seenCardsInAFullHeadDoNotCatchUp() {
        let loaded = card(600)
        let mine = card(1)
        let arrivals = (2 ... 8).map { card($0) }
        let result = plan(
            head: [mine] + arrivals,
            headLimit: 8,
            highWater: FeedCardMark(loaded),
            seen: [loaded.id, mine.id]
        )
        #expect(result == .prepend(arrivals: arrivals))
    }

    @Test("rotation brings up cards the reader never reached, then the next page")
    func rotationPrefersUndisplayed() {
        let read = card(10)
        let below = [card(20), card(30)]
        let next = card(400)
        let result = plan(
            head: [],
            tail: [next],
            highWater: FeedCardMark(read),
            seen: Set(([read] + below).map(\.id)),
            onShelf: [read] + below,
            displayed: [read.id]
        )
        #expect(
            result == .rotate(
                .init(page: below + [next], nextBefore: next.pageCursor, consumedWholeTail: true)
            )
        )
    }

    @Test("with nothing left to load, rotation still brings up the unread cards")
    func rotationOfUnreadOnly() {
        let read = card(10)
        let below = card(20)
        let result = plan(
            head: [],
            tail: [],
            highWater: FeedCardMark(read),
            seen: [read.id, below.id],
            onShelf: [read, below],
            displayed: [read.id]
        )
        #expect(result == .rotate(.init(page: [below], nextBefore: nil, consumedWholeTail: true)))
    }

    @Test("a shelf nobody has read and nothing new behind it does not rotate")
    func unreadShelfWithNothingNewIsUnchanged() {
        let top = card(10)
        let below = card(20)
        let result = plan(
            head: [],
            tail: [],
            highWater: FeedCardMark(top),
            seen: [top.id, below.id],
            onShelf: [top, below],
            displayed: []
        )
        #expect(result == .unchanged)
    }

    @Test("a fully read shelf with nothing new restarts once rotated")
    func readShelfRestarts() {
        let top = card(10)
        let result = plan(
            head: [],
            tail: [],
            highWater: FeedCardMark(top),
            seen: [top.id],
            onShelf: [top],
            displayed: [top.id],
            isRotated: true
        )
        #expect(result == .restart)
    }
}

@Suite("Feed arrival mark")
struct FeedCardMarkTests {
    @Test("a server cursor parses into a mark")
    func parsesServerCursor() {
        let newest = card(5)
        let mark = FeedCardMark(cursor: newest.pageCursor)
        #expect(mark == FeedCardMark(newest))
    }

    @Test("a malformed cursor is nil")
    func rejectsMalformed() {
        #expect(FeedCardMark(cursor: "") == nil)
        #expect(FeedCardMark(cursor: "not-a-date|00000000-0000-4000-8000-000000000001") == nil)
        #expect(FeedCardMark(cursor: "2026-10-06T10:00:00.000Z|not-a-uuid") == nil)
        #expect(FeedCardMark(cursor: "2026-10-06T10:00:00.000Z") == nil)
    }

    @Test("a mark only moves forward")
    func latestKeepsTheNewer() {
        let (high, low) = twins()
        #expect(FeedCardMark.latest(FeedCardMark(low), FeedCardMark(high)) == FeedCardMark(high))
        #expect(FeedCardMark.latest(FeedCardMark(high), FeedCardMark(low)) == FeedCardMark(high))
        #expect(FeedCardMark.latest(nil, FeedCardMark(low)) == FeedCardMark(low))
    }
}
