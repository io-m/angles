import Foundation
import Testing
@testable import Angles

@Suite("For you covers")
struct ForYouCoversTests {
    @Test("neighbours never share an angle when a card has another one")
    func noRepeatsWhenAvoidable() {
        let page = (0 ..< 24).map { index in
            cover(.stoic, styles: Style.allCases, day: 30 - index)
        }
        let faced = ForYouCovers.assign(page)
        #expect(faced.map(\.id) == page.map(\.id))
        for index in faced.indices.dropFirst() {
            #expect(faced[index].spotlightStyle != faced[index - 1].spotlightStyle)
        }
        for card in faced {
            #expect(card.hasStyle(card.spotlightStyle))
        }
    }

    @Test("a card that already differs keeps the angle it came with")
    func keepsServerFace() {
        let page = [
            cover(.stoic, styles: Style.allCases, day: 3),
            cover(.witty, styles: Style.allCases, day: 2),
            cover(.hopeful, styles: Style.allCases, day: 1),
        ]
        #expect(ForYouCovers.assign(page).map(\.spotlightStyle) == [.stoic, .witty, .hopeful])
    }

    @Test("your own cards keep their saved cover and the neighbour steps aside")
    func ownCoverIsFixed() {
        let mine = cover(.stoic, styles: Style.allCases, day: 2, isOwner: true)
        let theirs = cover(.stoic, styles: Style.allCases, day: 3)
        let faced = ForYouCovers.assign([theirs, mine])
        #expect(faced[1].spotlightStyle == .stoic)
        #expect(faced[0].spotlightStyle != .stoic)
    }

    @Test("a card with one angle keeps it rather than leaving the page")
    func singleAngleMayRepeat() {
        let page = [
            cover(.stoic, styles: [.stoic], day: 2),
            cover(.stoic, styles: [.stoic], day: 1),
        ]
        let faced = ForYouCovers.assign(page)
        #expect(faced.count == 2)
        #expect(faced.allSatisfy { $0.spotlightStyle == .stoic })
    }

    @Test("an appended page avoids the card already shown above it")
    func appendRespectsAbove() {
        let faced = ForYouCovers.assign([cover(.witty, styles: Style.allCases, day: 1)], above: .witty)
        #expect(faced[0].spotlightStyle != .witty)
    }

    @Test("arrivals avoid the card they sit on")
    func prependRespectsBelow() {
        let faced = ForYouCovers.assign([cover(.hopeful, styles: Style.allCases, day: 9)], below: .hopeful)
        #expect(faced[0].spotlightStyle != .hopeful)
    }

    @Test("the board faces only For you and keeps cards already there")
    func boardFacesForYouOnly() {
        var board = HomeFeedBoard()
        let first = cover(.stoic, styles: Style.allCases, day: 5)
        let second = cover(.stoic, styles: Style.allCases, day: 4)
        _ = board.replace(
            [first, second], on: .all, before: "cursor", hasMore: true,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        let faces = board.cards(on: .all).map(\.spotlightStyle)
        #expect(faces[0] == .stoic)
        #expect(faces[1] != .stoic)

        let third = cover(faces[1], styles: Style.allCases, day: 3)
        _ = board.append(
            [board.cards(on: .all)[1], third], on: .all, before: "next", hasMore: false,
            generation: 0
        )
        let appended = board.cards(on: .all)
        #expect(appended[1].spotlightStyle == faces[1])
        #expect(appended[2].spotlightStyle != appended[1].spotlightStyle)

        let stoicOnly = cover(.stoic, styles: Style.allCases, day: 2)
        let stoicNext = cover(.stoic, styles: Style.allCases, day: 1)
        _ = board.replace(
            [stoicOnly, stoicNext], on: .stoic, before: nil, hasMore: false,
            generation: 0, filter: { _ in true }, pageSize: 24
        )
        #expect(board.cards(on: .stoic).map(\.spotlightStyle) == [.stoic, .stoic])
    }

    @Test("a card never opens on an angle you hearted while it has another")
    func skipsKeptAngles() {
        let card = cover(.stoic, styles: Style.allCases, day: 2, kept: [.stoic])
        #expect(ForYouCovers.assign([card]).first?.spotlightStyle != .stoic)
    }

    @Test("an unread angle beats avoiding a repeat")
    func unreadBeatsNoRepeat() {
        let card = cover(.stoic, styles: [.stoic, .hopeful, .witty, .tough], day: 2, kept: [.stoic, .witty, .tough])
        #expect(ForYouCovers.assign([card], above: .hopeful).first?.spotlightStyle == .hopeful)
    }

    @Test("a card with every angle hearted keeps the face it came with")
    func everyAngleKept() {
        let card = cover(.witty, styles: Style.allCases, day: 2, kept: Set(Style.allCases))
        #expect(ForYouCovers.assign([card]).first?.spotlightStyle == .witty)
    }
}

private func cover(
    _ face: Style,
    styles: [Style],
    day: Int,
    isOwner: Bool = false,
    kept: Set<Style> = []
) -> HomeCard {
    HomeCard(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
        slides: styles.map { style in
            HomeCardSlide(
                id: UUID(),
                thought: "A thought",
                result: ReframeResult(style: style, reframe: "An angle"),
                isHearted: kept.contains(style)
            )
        },
        spotlightStyle: face,
        isPublic: true,
        isOwner: isOwner,
        authorId: UUID(),
        authorInitials: "AL"
    )
}
