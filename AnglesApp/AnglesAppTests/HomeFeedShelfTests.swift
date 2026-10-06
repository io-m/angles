import Foundation
import Testing
@testable import Angles

@Suite("Home feed shelves")
struct HomeFeedShelfTests {
    @Test("shelves keep independent cursors and orders")
    func independentCursors() {
        var board = HomeFeedBoard()
        let older = card(.stoic, day: 1)
        let newer = card(.humorous, day: 2)

        #expect(
            board.replace(
                [older], on: .all, before: "all-cursor", hasMore: true,
                generation: 0, filter: { _ in true }, pageSize: 24
            ) == .applied
        )
        #expect(
            board.replace(
                [newer], on: .stoic, before: "stoic-cursor", hasMore: false,
                generation: 0, filter: { _ in true }, pageSize: 24
            ) == .applied
        )

        #expect(board.cards(on: .all).map(\.id) == [older.id])
        #expect(board.cards(on: .stoic).map(\.id) == [newer.id])
        #expect(board.shelf(.all).before == "all-cursor")
        #expect(board.shelf(.stoic).before == "stoic-cursor")
        #expect(board.shelf(.all).hasMore)
        #expect(!board.shelf(.stoic).hasMore)
    }

    @Test("a filter reset blanks every shelf and rejects a stale commit")
    func filterResetRejectsStaleWork() {
        var board = HomeFeedBoard()
        let kept = card(.stoic, day: 1)
        _ = board.replace(
            [kept], on: .all, before: "cursor", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        _ = board.replace(
            [kept], on: .optimistic, before: "style", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 24
        )

        board.invalidate(blank: true)
        #expect(board.cards(on: .all).isEmpty)
        #expect(board.cards(on: .optimistic).isEmpty)
        #expect(
            board.replace(
                [kept], on: .all, before: "stale", hasMore: true,
                generation: 0, filter: { _ in true }, pageSize: 24
            ) == .stale
        )
        #expect(board.cards(on: .all).isEmpty)

        #expect(
            board.replace(
                [kept], on: .all, before: "fresh", hasMore: false,
                generation: board.shelf(.all).generation, filter: { _ in true }, pageSize: 24
            ) == .applied
        )
        #expect(board.shelf(.all).before == "fresh")
    }

    @Test("a heart updates every shelf and removal leaves all of them")
    func mutationPropagates() {
        var board = HomeFeedBoard()
        let shared = card(.stoic, day: 1)
        _ = board.replace(
            [shared], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        _ = board.replace(
            [shared], on: .stoic, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )

        board.update(shared.id) { item in
            item.slides[0].isFavorite = true
        }
        #expect(board.cards(on: .all)[0].slides[0].isFavorite)
        #expect(board.cards(on: .stoic)[0].slides[0].isFavorite)

        board.remove(shared.id)
        #expect(board.cards(on: .all).isEmpty)
        #expect(board.cards(on: .stoic).isEmpty)
        #expect(board.record(shared.id) == nil)
    }

    @Test("refreshing one shelf does not reorder another")
    func selectedShelfRefresh() {
        var board = HomeFeedBoard()
        let first = card(.stoic, day: 2)
        let second = card(.optimistic, day: 1)
        _ = board.replace(
            [first, second], on: .all, before: "all", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        _ = board.replace(
            [first], on: .stoic, before: "stoic", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 24
        )

        let generation = board.beginRefresh(on: .stoic)
        #expect(generation == 1)
        #expect(board.beginRefresh(on: .stoic) == nil)
        #expect(
            board.rotate(
                [second], on: .stoic, before: "next", hasMore: false,
                generation: generation ?? -1, filter: { _ in true }, pageSize: 24
            ) == .applied
        )
        #expect(board.publish(.rotated, on: .stoic, generation: generation ?? -1) == .applied)

        #expect(board.cards(on: .all).map(\.id) == [first.id, second.id])
        #expect(board.cards(on: .stoic).map(\.id) == [second.id])
        #expect(board.shelf(.stoic).before == "next")
        #expect(board.shelf(.all).before == "all")
        #expect(board.shelf(.stoic).refreshOutcome == .rotated)
        #expect(board.shelf(.all).refreshOutcome == nil)
        #expect(board.shelf(.stoic).isRotated)
        #expect(!board.shelf(.all).isRotated)
    }

    @Test("a pull ends even when its generation moved, so the next pull starts")
    func pullEndsAfterGenerationMoved() {
        var board = HomeFeedBoard()
        _ = board.replace(
            [card(.stoic, day: 1)], on: .all, before: "all", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 24
        )

        let first = board.beginRefresh(on: .all) ?? -1
        _ = board.bump(.all)
        board.endRefresh(on: .all, refreshID: first)
        #expect(!board.shelf(.all).isRefreshing)
        #expect(board.beginRefresh(on: .all) != nil)
    }

    @Test("an old pull's end does not clear a newer pull")
    func stalePullLeavesNewerOne() {
        var board = HomeFeedBoard()
        let first = board.beginRefresh(on: .all) ?? -1
        board.invalidate(blank: false)
        let second = board.beginRefresh(on: .all)
        #expect(second != nil)

        board.endRefresh(on: .all, refreshID: first)
        #expect(board.shelf(.all).isRefreshing)
        board.endRefresh(on: .all, refreshID: second ?? -1)
        #expect(!board.shelf(.all).isRefreshing)
    }

    @Test("a new post lands on loaded shelves that contain its angle")
    func publishedCardJoinsLoadedShelves() {
        var board = HomeFeedBoard()
        let existing = card(.humorous, day: 1)
        _ = board.replace(
            [existing], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        _ = board.replace(
            [existing], on: .stoic, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )

        let posted = card(.stoic, day: 3)
        board.insertPublishedAtFront(posted)

        #expect(board.cards(on: .all).first?.id == posted.id)
        #expect(board.cards(on: .stoic).first?.id == posted.id)
        #expect(board.cards(on: .humorous).isEmpty)
    }

    @Test("a private owner library record evicts every shelf and its anchor")
    func privateOwnerRecordEvictsPublishedAnchor() {
        var board = HomeFeedBoard()
        let existing = card(.stoic, day: 1)
        _ = board.replace(
            [existing], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        _ = board.replace(
            [existing], on: .stoic, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        let posted = card(.stoic, day: 3, isOwner: true)
        board.insertPublishedAtFront(posted)

        _ = board.replace(
            [existing], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        #expect(board.cards(on: .all).first?.id == posted.id)
        #expect(board.anchors[posted.id] != nil)

        var hidden = posted
        hidden.isPublic = false
        hidden.moderationHidden = true
        let change = board.reconcileOwnerVisibility([hidden], admits: { _ in true })

        #expect(change.removed == [posted.id])
        #expect(board.record(posted.id) == nil)
        #expect(board.anchors[posted.id] == nil)
        #expect(!board.cards(on: .all).contains(where: { $0.id == posted.id }))
        #expect(!board.cards(on: .stoic).contains(where: { $0.id == posted.id }))
        _ = board.replace(
            [existing], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        #expect(!board.cards(on: .all).contains(where: { $0.id == posted.id }))

        let order = board.cards(on: .all).map(\.id)
        let again = board.reconcileOwnerVisibility([hidden], admits: { _ in true })
        #expect(again == OwnerVisibilityChange())
        #expect(!again.changed)
        #expect(board.cards(on: .all).map(\.id) == order)
    }

    @Test("hide, then publish: the card comes back once in place, anchored, without a restart")
    func hiddenThenPublishedReturnsOnce() {
        var board = HomeFeedBoard()
        let newest = card(.optimistic, day: 5)
        let mine = card(.stoic, day: 3, isOwner: true)
        let oldest = card(.humorous, day: 1)
        _ = board.replace(
            [newest, mine, oldest], on: .all, before: "cursor", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 3
        )
        _ = board.replace(
            [mine], on: .stoic, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )

        var hidden = mine
        hidden.isPublic = false
        hidden.moderationHidden = true
        #expect(board.reconcileOwnerVisibility([hidden], admits: { _ in true }).removed == [mine.id])
        #expect(board.cards(on: .all).map(\.id) == [newest.id, oldest.id])
        #expect(board.cards(on: .stoic).isEmpty)
        #expect(board.privateOwnerIDs == [mine.id])

        let published = board.reconcileOwnerVisibility([mine], admits: { _ in true })
        #expect(published.placed.map(\.id) == [mine.id])
        #expect(published.republished.map(\.id) == [mine.id])
        #expect(board.cards(on: .all).map(\.id) == [newest.id, mine.id, oldest.id])
        #expect(board.cards(on: .stoic).map(\.id) == [mine.id])
        #expect(board.anchors[mine.id] != nil)
        #expect(board.privateOwnerIDs.isEmpty)

        let order = board.cards(on: .all)
        let again = board.reconcileOwnerVisibility([mine], admits: { _ in true })
        #expect(!again.changed)
        #expect(board.cards(on: .all) == order)
        #expect(board.cards(on: .all).filter { $0.id == mine.id }.count == 1)

        _ = board.replace(
            [newest, oldest], on: .all, before: "cursor", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 3
        )
        #expect(board.cards(on: .all).map(\.id) == [newest.id, mine.id, oldest.id])
    }

    @Test("a republished card older than every loaded card still lands, at the tail")
    func republishedPastTheTailStillLands() {
        var board = HomeFeedBoard()
        let newer = card(.optimistic, day: 5)
        let mine = card(.stoic, day: 1, isOwner: true)
        _ = board.replace(
            [newer], on: .all, before: "cursor", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 1
        )
        var hidden = mine
        hidden.isPublic = false
        _ = board.reconcileOwnerVisibility([hidden], admits: { _ in true })

        let change = board.reconcileOwnerVisibility([mine], admits: { _ in true })
        #expect(change.placed.map(\.id) == [mine.id])
        #expect(board.cards(on: .all).map(\.id) == [newer.id, mine.id])

        _ = board.append(
            [mine], on: .all, before: "next", hasMore: false, generation: 0
        )
        #expect(board.cards(on: .all).map(\.id) == [newer.id, mine.id])
    }

    @Test("a republished card the filter excludes is not placed, and is not placed later")
    func filteredRepublishIsNotPlaced() {
        var board = HomeFeedBoard()
        let other = card(.optimistic, day: 5)
        let mine = card(.stoic, day: 3, isOwner: true)
        _ = board.replace(
            [other], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        var hidden = mine
        hidden.isPublic = false
        _ = board.reconcileOwnerVisibility([hidden], admits: { _ in true })

        let change = board.reconcileOwnerVisibility([mine], admits: { _ in false })
        #expect(change.placed.isEmpty)
        #expect(change.republished.map(\.id) == [mine.id])
        #expect(board.cards(on: .all).map(\.id) == [other.id])
        #expect(!board.reconcileOwnerVisibility([mine], admits: { _ in true }).changed)
    }

    @Test("a public owner card the library repeats keeps its Home value, face, order, and anchor")
    func unchangedPublicOwnerCardIsUntouched() {
        var board = HomeFeedBoard()
        let other = card(.optimistic, day: 1)
        let mine = card(.stoic, day: 2, isOwner: true, styles: [.stoic, .humorous])
        _ = board.replace(
            [other], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        board.insertPublishedAtFront(mine)
        _ = board.update(mine.id) { $0.spotlightStyle = .humorous }
        let record = board.record(mine.id)
        let anchor = board.anchors[mine.id]
        let order = board.cards(on: .all).map(\.id)

        var library = mine
        library.spotlightStyle = .stoic
        library.slides[0].isFavorite = true
        library.slides[0].heartCount = 9
        let change = board.reconcileOwnerVisibility([library], admits: { _ in true })

        #expect(!change.changed)
        #expect(board.record(mine.id) == record)
        #expect(board.record(mine.id)?.spotlightStyle == .humorous)
        #expect(board.anchors[mine.id] == anchor)
        #expect(board.cards(on: .all).map(\.id) == order)
    }

    @Test("a still-public posted owner card survives refresh at the top")
    func publicOwnerAnchorSurvivesRefresh() {
        var board = HomeFeedBoard()
        let existing = card(.optimistic, day: 1)
        _ = board.replace(
            [existing], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        let posted = card(.stoic, day: 3, isOwner: true)
        board.insertPublishedAtFront(posted)

        _ = board.replace(
            [existing], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        #expect(!board.reconcileOwnerVisibility([posted], admits: { _ in true }).changed)
        _ = board.replace(
            [existing], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )

        #expect(board.cards(on: .all).first?.id == posted.id)
        #expect(board.anchors[posted.id]?.isPublic == true)
    }

    @Test("a ranked page takes the server's arrival mark, not its newest card")
    func rankedPageUsesServerMark() {
        var board = HomeFeedBoard()
        // The ranked page leads with an older card; a newer one ranked lower is off the page.
        let shown = card(.stoic, day: 3)
        let offPage = card(.stoic, day: 9)
        _ = board.replace(
            [shown], on: .all, before: "ranked", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 24,
            arrivalsAfter: offPage.pageCursor
        )
        #expect(board.shelf(.all).highWater == FeedCardMark(offPage))
    }

    @Test("a chronological page marks its own newest card")
    func chronologicalPageUsesNewestCard() {
        var board = HomeFeedBoard()
        let newest = card(.stoic, day: 5)
        let older = card(.stoic, day: 2)
        _ = board.replace(
            [newest, older], on: .all, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        #expect(board.shelf(.all).highWater == FeedCardMark(newest))
    }

    @Test("your own new post does not move the arrival mark")
    func localInsertKeepsMark() {
        var board = HomeFeedBoard()
        let loaded = card(.stoic, day: 3)
        _ = board.replace(
            [loaded], on: .all, before: "ranked", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 24,
            arrivalsAfter: loaded.pageCursor
        )
        let posted = card(.stoic, day: 10, isOwner: true)
        board.insertPublishedAtFront(posted)
        #expect(board.cards(on: .all).first?.id == posted.id)
        #expect(board.shelf(.all).highWater == FeedCardMark(loaded))
        #expect(board.shelf(.all).seenIDs.contains(posted.id))
    }

    @Test("arrivals move the mark to the newest one")
    func prependAdvancesMark() {
        var board = HomeFeedBoard()
        let loaded = card(.stoic, day: 3)
        _ = board.replace(
            [loaded], on: .all, before: "ranked", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 24,
            arrivalsAfter: loaded.pageCursor
        )
        let newer = card(.stoic, day: 7)
        let newest = card(.stoic, day: 8)
        _ = board.prepend([newest, newer], on: .all, generation: 0)
        #expect(board.shelf(.all).highWater == FeedCardMark(newest))
    }
}

private func card(
    _ style: Style,
    day: Int,
    isPublic: Bool = true,
    isOwner: Bool = false,
    styles: [Style]? = nil
) -> HomeCard {
    HomeCard(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
        slides: (styles ?? [style]).map { style in
            HomeCardSlide(
                id: UUID(),
                thought: "A thought",
                result: ReframeResult(style: style, reframe: "An angle"),
                isFavorite: false
            )
        },
        spotlightStyle: style,
        isPublic: isPublic,
        isOwner: isOwner,
        authorId: UUID(),
        authorInitials: "AL"
    )
}
