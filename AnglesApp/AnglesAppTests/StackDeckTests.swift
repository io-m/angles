import Foundation
import Testing
import UIKit
@testable import Angles

struct StackDeckTests {
    private static let fourStyles: [Style] = [.stoic, .hopeful, .witty, .tough]

    private static func card(
        opening: Style = .stoic,
        decision: CardDecision? = nil,
        isOwner: Bool = false
    ) -> HomeCard {
        HomeCard(
            slides: fourStyles.map { style in
                HomeCardSlide(
                    id: UUID(),
                    thought: "A thought.",
                    result: ReframeResult(style: style, reframe: "An angle.")
                )
            },
            openingStyle: opening,
            isOwner: isOwner,
            authorId: UUID(),
            decision: decision
        )
    }

    private static func deck(_ cards: [HomeCard], exhausted: Bool = false) -> StackDeck {
        var deck = StackDeck()
        deck.receive(
            cards,
            receivedIds: cards.map { $0.id.uuidString.lowercased() },
            session: "s1",
            exhausted: exhausted
        )
        return deck
    }

    @Test func theOpeningAngleAndEveryShownAngleCountAsChecked() throws {
        let card = Self.card(opening: .hopeful)
        var deck = Self.deck([card])
        deck.show(.witty, on: card.id)

        let stepResult = deck.decide(.pass)
        let step = try #require(stepResult)
        #expect(step.request.kind == .pass)
        #expect(step.request.style == .witty)
        #expect(step.request.checkedStyles == [.hopeful, .witty])
        #expect(step.request.passes == 1)
    }

    @Test func aSecondPassKeepsEarlierAnglesAndCapsThePasses() throws {
        let prior = CardDecision(kind: .pass, style: .stoic, checkedStyles: [.stoic], passes: 1, decidedAt: "2026-10-01T10:00:00.000Z")
        let card = Self.card(opening: .tough, decision: prior)
        var deck = Self.deck([card])

        let stepResult = deck.decide(.pass)
        let step = try #require(stepResult)
        #expect(step.request.checkedStyles == [.stoic, .tough])
        #expect(step.request.passes == maxDecisionPasses)
    }

    @Test func aSaveKeepsThePassCount() throws {
        let prior = CardDecision(kind: .pass, style: .stoic, checkedStyles: [.stoic], passes: 1, decidedAt: "2026-10-01T10:00:00.000Z")
        var deck = Self.deck([Self.card(opening: .hopeful, decision: prior)])

        let stepResult = deck.decide(.save)
        let step = try #require(stepResult)
        #expect(step.request.kind == .save)
        #expect(step.request.passes == 1)
    }

    @Test func rewindStepsBackThroughEveryDecisionAndRestoresEachRow() throws {
        let fresh = Self.card(opening: .stoic)
        let prior = CardDecision(kind: .pass, style: .witty, checkedStyles: [.witty], passes: 1, decidedAt: "2026-10-01T10:00:00.000Z")
        let returning = Self.card(opening: .hopeful, decision: prior)
        var deck = Self.deck([fresh, returning])

        deck.show(.tough, on: fresh.id)
        _ = deck.decide(.save)
        _ = deck.decide(.pass)
        #expect(deck.top == nil)

        let secondResult = deck.rewind()
        let second = try #require(secondResult)
        #expect(deck.top?.id == returning.id)
        #expect(second.write == .put(DecisionRequest(kind: .pass, style: .witty, checkedStyles: [.witty], passes: 1)))

        let firstResult = deck.rewind()
        let first = try #require(firstResult)
        #expect(deck.top?.id == fresh.id)
        #expect(deck.style(for: fresh) == .tough)
        #expect(deck.checked(for: fresh) == [.stoic, .tough])
        #expect(first.write == .clear)
        #expect(!deck.canRewind)
        #expect(deck.rewind() == nil)
    }

    @Test func theEndCardWaitsForTheServerToRunOut() throws {
        var deck = Self.deck([Self.card()])
        #expect(!deck.isFinished)
        _ = deck.decide(.pass)
        #expect(!deck.isFinished)
        #expect(deck.wantsMore)

        deck.receive([], receivedIds: [], session: "s1", exhausted: true)
        #expect(deck.isFinished)
        #expect(!deck.wantsMore)
    }

    @Test func ownCardsNeverReachTheStackAndConfirmedCardsLeaveSeen() throws {
        let mine = Self.card(isOwner: true)
        let theirs = Self.card()
        var deck = Self.deck([mine, theirs])
        #expect(deck.cards.map(\.id) == [theirs.id])

        _ = deck.decide(.pass)
        let key = theirs.id.uuidString.lowercased()
        #expect(deck.seen.contains(key))
        deck.confirm(theirs.id)
        #expect(!deck.seen.contains(key))
    }

    @Test func unsavingFromAListRetiresTheCard() {
        let saved = CardDecision(kind: .save, style: .hopeful, checkedStyles: [.hopeful], passes: 0, decidedAt: "2026-10-01T10:00:00.000Z")
        let request = StackDeck.unsaveRequest(for: Self.card(decision: saved))
        #expect(request.kind == .pass)
        #expect(request.style == .hopeful)
        #expect(request.checkedStyles == Self.fourStyles)
        #expect(request.passes == maxDecisionPasses)
    }
}

struct AngleTypeFitTests {
    /// iPhone SE (3rd generation): 375 × 667 points, 20 top and 0 bottom safe area.
    private static let screen = CGSize(width: 375, height: 667)
    private static let safeTop: CGFloat = 20
    private static let safeBottom: CGFloat = 0

    /// The longest thought and answer the cook asks for (`THOUGHT_MAX_CHARS`, `REFRAME_MAX_CHARS`).
    private static let capThought = String(repeating: "I keep replaying what I said and it feels worse. ", count: 6)
        .prefix(200)
        .description
    private static let capAnswer = String(repeating: "Name what happened, then the next small step you can take today. ", count: 6)
        .prefix(280)
        .description
    /// What the server lets through at most (`THOUGHT_HARD_MAX_CHARS`, `REFRAME_HARD_MAX_CHARS`).
    private static let hardThought = String(capThought.prefix(200) + capThought.prefix(40))
    private static let hardAnswer = String(capAnswer + capAnswer.prefix(60))
    /// About the 95th percentile of real cards.
    private static let typicalThought = String(capThought.prefix(118))
    private static let typicalAnswer = String(capAnswer.prefix(178))

    private static var card: CGSize {
        StackLayout.frame(screen: screen, safeTop: safeTop, safeBottom: safeBottom).card
    }

    /// The answer box on the stack, built from the same metrics and sizes the views use.
    private static func box(
        thought: String = typicalThought,
        sizeCategory: UIContentSizeCategory = .large,
        card: CGSize = card
    ) -> CGSize {
        let textWidth = card.width - AngleCardMetrics.stackInset * 2
        let thoughtSize = AngleTypeFit.thoughtSize(
            for: thought,
            width: textWidth,
            cardHeight: card.height,
            sizeCategory: sizeCategory
        )
        let thoughtHeight = AngleTypeFit.thoughtHeight(thought, size: thoughtSize, width: textWidth, sizeCategory: sizeCategory)
        let chrome = AngleCardMetrics.stackChrome(thoughtHeight: thoughtHeight)
        return CGSize(width: textWidth, height: card.height - chrome)
    }

    private static func fit(_ answer: String, in box: CGSize = box()) -> AngleAnswerSize {
        AngleTypeFit.answerSize(for: answer, in: box, sizeCategory: .large)
    }

    /// What the view draws: at most `fill` of the box, or the whole box at the smallest size.
    private static func expectInside(_ answer: String, in box: CGSize = box()) {
        let size = fit(answer, in: box)
        let height = AngleTypeFit.answerHeight(answer, pointSize: size.pointSize, width: box.width)
        let limit = size.pointSize > AngleTypeFit.smallest ? box.height * AngleTypeFit.fill : box.height
        #expect(!size.scrolls, "box \(box), size \(size.pointSize)")
        #expect(height <= limit, "box \(box), size \(size.pointSize), height \(height)")
    }

    @Test func aShortAnswerGetsTheLargestSize() {
        #expect(Self.fit("Breathe. This passes.").pointSize == AngleTypeFit.largest)
    }

    @Test func aTypicalAnswerStaysLargeOnAnIPhoneSE() {
        let size = Self.fit(Self.typicalAnswer)
        #expect(!size.scrolls)
        #expect(size.pointSize >= 18, "box \(Self.box()), size \(size.pointSize)")
    }

    @Test func aLongerAnswerGetsASmallerSizeOnTheSameCard() {
        let short = Self.fit("Name it, then take the next small step.")
        let long = Self.fit(Self.typicalAnswer)
        #expect(long.pointSize < short.pointSize)
    }

    @Test func eachAngleGetsItsOwnSizeAndTheSizesAreReused() {
        let answers: [Style: String] = [.stoic: "Breathe.", .hopeful: Self.typicalAnswer]
        let sizes = AngleTypeFit.answerSizes(for: answers, in: Self.box(), sizeCategory: .large)
        #expect(sizes[.stoic]?.pointSize == AngleTypeFit.largest)
        #expect(sizes[.hopeful] == Self.fit(Self.typicalAnswer))
        #expect(AngleTypeFit.answerSizes(for: answers, in: Self.box(), sizeCategory: .large) == sizes)
    }

    @Test func everyAnswerStaysInsideItsBox() {
        for answer in ["", "Breathe.", "Name it, then take the next small step.", Self.typicalAnswer, Self.capAnswer] {
            Self.expectInside(answer)
        }
    }

    @Test func awkwardTextStillFits() {
        let token = String(repeating: "x", count: 60)
        let emoji = "One step 🌱 then another 🌿 and you are further than you were 🌳."
        let japanese = "失敗したと感じても、それはあなたの価値を決めるものではありません。小さな一歩から始めましょう。"
        for answer in [token, emoji, japanese] {
            Self.expectInside(answer)
        }
    }

    @Test func theLongestCardTheCookWritesFitsOnAnIPhoneSE() {
        let box = Self.box(thought: Self.capThought)
        let size = Self.fit(Self.capAnswer, in: box)
        #expect(size.pointSize >= AngleTypeFit.smallest, "box \(box), size \(size.pointSize)")
        Self.expectInside(Self.capAnswer, in: box)
    }

    /// Past what the cook asks for, a small phone scrolls the answer rather than clipping it;
    /// a regular phone (6.1 inch, 852 points tall) still fits it.
    @Test func theHardCapsScrollOnAnIPhoneSEAndFitOnARegularPhone() {
        let small = Self.box(thought: Self.hardThought)
        let size = Self.fit(Self.hardAnswer, in: small)
        let height = AngleTypeFit.answerHeight(Self.hardAnswer, pointSize: size.pointSize, width: small.width)
        #expect(size.scrolls || height <= small.height)

        let phone = StackLayout.frame(screen: CGSize(width: 393, height: 852), safeTop: 59, safeBottom: 34).card
        Self.expectInside(Self.hardAnswer, in: Self.box(thought: Self.hardThought, card: phone))
    }

    @Test func aLongThoughtStepsDownBeforeItTakesTheCard() {
        let width = Self.card.width - AngleCardMetrics.stackInset * 2
        let short = AngleTypeFit.thoughtSize(for: Self.typicalThought, width: width, cardHeight: Self.card.height, sizeCategory: .large)
        let long = AngleTypeFit.thoughtSize(for: Self.hardThought, width: width, cardHeight: Self.card.height, sizeCategory: .large)
        #expect(short == .body)
        #expect(long.rawValue > short.rawValue)
    }

    @Test func aBoxWithNoRoomScrolls() {
        let size = AngleTypeFit.answerSize(
            for: Self.hardAnswer,
            in: CGSize(width: 300, height: 40),
            sizeCategory: .accessibilityExtraExtraLarge
        )
        #expect(size.scrolls)
    }
}

@MainActor
struct StackDragTests {
    @Test func aFingerUnderTheSlopIsStillATap() {
        let drag = StackDrag()
        drag.beginTouch()
        drag.noteFingerTravel(CGSize(width: StackDrag.tapSlop, height: 0))
        #expect(!drag.touchWasDrag)
    }

    @Test func aMovePastTheSlopStaysADragWhenTheFingerLifts() {
        let drag = StackDrag()
        drag.beginTouch()
        drag.noteFingerTravel(CGSize(width: 0, height: StackDrag.tapSlop + 1))
        drag.finishTouch()
        #expect(drag.touchWasDrag)
    }

    @Test func theNextTouchCanTapAgain() {
        let drag = StackDrag()
        drag.beginTouch()
        drag.noteFingerTravel(CGSize(width: 40, height: 0))
        drag.finishTouch()
        drag.beginTouch()
        #expect(!drag.touchWasDrag)
    }
}

struct StackLayoutTests {
    private static let phones: [(name: String, screen: CGSize, safeTop: CGFloat, safeBottom: CGFloat)] = [
        ("iPhone Pro Max", CGSize(width: 430, height: 932), 59, 34),
        ("iPhone 15", CGSize(width: 393, height: 852), 59, 34),
        ("iPhone SE", CGSize(width: 375, height: 667), 20, 0),
    ]

    @Test func everyPhoneGetsAProportionedCardWithEvenGaps() {
        for phone in Self.phones {
            let frame = StackLayout.frame(screen: phone.screen, safeTop: phone.safeTop, safeBottom: phone.safeBottom)
            #expect(frame.card.width == phone.screen.width - StackMetrics.horizontalInset * 2, "\(phone.name)")
            #expect(frame.card.height <= frame.card.width * StackLayout.maxAspect, "\(phone.name)")
            #expect((StackLayout.topGap...120).contains(frame.topGap), "\(phone.name) top \(frame.topGap)")
            #expect((StackLayout.barGap...112).contains(frame.barGap), "\(phone.name) bar \(frame.barGap)")
            let topExtra = frame.topGap - StackLayout.topGap
            let barExtra = frame.barGap - StackLayout.barGap
            #expect(barExtra - topExtra == frame.lift, "\(phone.name)")
            #expect(frame.lift == min(StackLayout.lift, barExtra), "\(phone.name) lift \(frame.lift)")
        }
    }

    @Test func theCardAndGapsAddUpToTheScreen() {
        for phone in Self.phones {
            let frame = StackLayout.frame(screen: phone.screen, safeTop: phone.safeTop, safeBottom: phone.safeBottom)
            let used = phone.safeTop + StackMetrics.headerHeight + frame.topGap + frame.card.height
                + StackMetrics.sliver + frame.barGap + StackMetrics.inspireSize(screenHeight: phone.screen.height)
                + StackMetrics.barBottom(safeBottom: phone.safeBottom) + frame.lift
            #expect(abs(used - phone.screen.height) < 0.5, "\(phone.name) used \(used)")
        }
    }

    @Test func aSmallPhoneGetsSmallerButtons() {
        #expect(StackMetrics.inspireSize(screenHeight: 667) < StackMetrics.inspireSize(screenHeight: 852))
        #expect(StackMetrics.decideSize(screenHeight: 667) < StackMetrics.decideSize(screenHeight: 852))
        #expect(StackMetrics.sideSize(screenHeight: 667) < StackMetrics.sideSize(screenHeight: 852))
    }
}
