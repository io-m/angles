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
}

private func card(_ style: Style, day: Int) -> HomeCard {
    HomeCard(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
        slides: [
            HomeCardSlide(
                id: UUID(),
                thought: "A thought",
                result: ReframeResult(style: style, reframe: "An angle"),
                isFavorite: false
            )
        ],
        spotlightStyle: style,
        isPublic: true,
        isOwner: false,
        authorId: UUID(),
        authorInitials: "AL"
    )
}
