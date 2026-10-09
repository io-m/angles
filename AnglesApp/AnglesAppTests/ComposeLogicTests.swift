import CoreGraphics
import Foundation
import Testing
@testable import Angles

private let metaJSON = #"{"category":"work","tags":[],"intensity":3,"timeframe":"present","emotions":[],"safety":"none","inputLanguage":"en","skippedStyles":[],"matching":{"category":"work","tags":[],"intensityBand":"mid"}}"#

private func cook(results: Int = 1) -> ReadyCook {
    let decoder = JSONDecoder()
    let meta = try! decoder.decode(ReframeMeta.self, from: Data(metaJSON.utf8))
    let all = #"[{"style":"stoic","reframe":"A.","signature":"s1"},{"style":"hopeful","reframe":"B.","signature":"s2"}]"#
    let signed = try! decoder.decode([SignedReframeResult].self, from: Data(all.utf8))
    return ReadyCook(
        thought: "A thought.",
        results: Array(signed.prefix(results)),
        meta: meta,
        signature: "cook",
        model: "m"
    )
}

private func turn(_ message: String, reply: String? = nil) -> RefineTurn {
    RefineTurn(id: UUID(), message: message, options: [], safety: .none, reply: reply)
}

private func near(_ value: CGFloat, _ expected: CGFloat) -> Bool {
    abs(value - expected) < 0.000_001
}

private func ids(_ statement: String, _ turns: [RefineTurn], _ phase: RefinePhase) -> [String] {
    ComposeThreadRow.rows(statement: statement, turns: turns, phase: phase).map(\.id)
}

@Suite("Compose thread rows")
struct ComposeThreadRowTests {
    @Test("no thought, no rows")
    func emptyThread() {
        #expect(ids("", [], .composing).isEmpty)
        #expect(ids("", [], .cooking).isEmpty)
    }

    @Test("the open question keeps its id when it is answered, and only the answer is added")
    func answeringKeepsTheQuestionsID() {
        var question = turn("What happened?")
        let open = ids("Bad day", [question], .awaitingReply)
        #expect(open == ["statement", "q-\(question.id)"])

        question.reply = "Work"
        let answered = ids("Bad day", [question], .cooking)
        #expect(answered == ["statement", "q-\(question.id)", "a-\(question.id)", "cooking"])
        #expect(Array(answered.prefix(open.count)) == open)
    }

    @Test("each phase changes only the last row")
    func phaseRows() {
        let done = turn("Since when?", reply: "Spring")
        let base = ["statement", "q-\(done.id)", "a-\(done.id)"]
        #expect(ids("x", [done], .composing) == base)
        #expect(ids("x", [done], .cooking) == base + ["cooking"])
        #expect(ids("x", [done], .ready(cook())) == base + ["angles"])
        #expect(ids("x", [done], .error("No")) == base + ["error"])
    }

    @Test("rows carry what they show")
    func rowKinds() {
        let rows = ComposeThreadRow.rows(statement: "x", turns: [], phase: .error("Nope"))
        #expect(rows.last?.kind == .error("Nope"))
        #expect(rows.first?.kind == .statement)
    }
}

@Suite("Compose bottom bar")
struct ComposeBottomModeTests {
    @Test("composer, then Post, then the held place")
    func modes() {
        #expect(ComposeBottomMode(phase: .composing) == .composer)
        #expect(ComposeBottomMode(phase: .awaitingReply) == .composer)
        #expect(ComposeBottomMode(phase: .error("x")) == .composer)
        #expect(ComposeBottomMode(phase: .cooking) == .held)
        #expect(ComposeBottomMode(phase: .ready(cook())) == .post)
        #expect(ComposeBottomMode(phase: .ready(cook(results: 0))) == .held)
    }
}

@Suite("Compose thread mask")
struct ThreadMaskStopsTests {
    @Test("before the bar reports, the bottom is solid to the end")
    func noBottomEdge() {
        let stops = ThreadMaskStops.compute(height: 800, minY: 0, header: 120, bottom: 0)
        #expect(stops.bottomEnd == 1)
        #expect(stops.belowOpacity == 1)
        #expect(near(stops.topEnd, 0.15))
        #expect(near(stops.topStart, 0.125))
        #expect(near(stops.bottomStart, 0.955))
    }

    @Test("clear under the header, fading to 14% just above the bar")
    func typicalEdges() {
        let stops = ThreadMaskStops.compute(height: 1000, minY: 0, header: 100, bottom: 900)
        #expect(near(stops.topStart, 0.08))
        #expect(near(stops.topEnd, 0.1))
        #expect(near(stops.bottomEnd, 0.9))
        #expect(near(stops.bottomStart, 0.864))
        #expect(stops.belowOpacity == 0.14)
    }

    @Test("the mask's own top offsets the bar edge")
    func offsetMask() {
        let stops = ThreadMaskStops.compute(height: 1000, minY: 100, header: 100, bottom: 900)
        #expect(near(stops.bottomEnd, 0.8))
    }

    @Test("stops stay ordered and in range")
    func clamping() {
        let tall = ThreadMaskStops.compute(height: 100, minY: 0, header: 400, bottom: 10)
        #expect(near(tall.topEnd, 0.5))
        #expect(near(tall.bottomEnd, 0.51))
        #expect(tall.bottomStart >= tall.topEnd)
        #expect(tall.topStart >= 0.005)

        let tiny = ThreadMaskStops.compute(height: 0, minY: 0, header: 0, bottom: 0)
        #expect(near(tiny.topEnd, 0.02))
        #expect(near(tiny.topStart, 0.005))
    }
}

@Suite("Compose scroll follow")
struct ThreadFollowTests {
    @Test("a new row scrolls and arms; its settling keeps the end in view until it has arrived")
    func arrival() {
        var follow = ThreadFollow()
        #expect(!follow.contentHeightChanged())
        let scrolled = follow.rowsChanged(from: ["statement"], to: ["statement", "cooking"])
        #expect(scrolled)
        #expect(follow.isArmed)
        #expect(follow.contentHeightChanged())
        follow.arrivalSettled()
        #expect(!follow.isArmed)
        #expect(!follow.contentHeightChanged())
    }

    @Test("a replaced row (cooking to card) is an arrival")
    func replacement() {
        var follow = ThreadFollow()
        let toCard = follow.rowsChanged(from: ["statement", "cooking"], to: ["statement", "angles"])
        #expect(toCard)
        let toError = follow.rowsChanged(from: ["statement", "cooking"], to: ["statement", "error"])
        #expect(toError)
    }

    @Test("an answered question adds only its answer, and that is an arrival")
    func answer() {
        var follow = ThreadFollow()
        let scrolled = follow.rowsChanged(from: ["statement", "q-1"], to: ["statement", "q-1", "a-1", "cooking"])
        #expect(scrolled)
    }

    @Test("a removal or the same rows never scroll and disarm")
    func removal() {
        var follow = ThreadFollow()
        _ = follow.rowsChanged(from: [], to: ["statement"])
        let removed = follow.rowsChanged(from: ["statement"], to: [])
        #expect(!removed)
        #expect(!follow.isArmed)
        _ = follow.rowsChanged(from: [], to: ["statement"])
        let unchanged = follow.rowsChanged(from: ["statement"], to: ["statement"])
        #expect(!unchanged)
        #expect(!follow.contentHeightChanged())
    }

    @Test("the user taking the scroll view stops the follow")
    func userScroll() {
        var follow = ThreadFollow()
        _ = follow.rowsChanged(from: [], to: ["statement"])
        follow.userScrolled()
        #expect(!follow.contentHeightChanged())
    }
}

@Suite("Compose leave prompt")
struct ComposeLeavePromptTests {
    @Test("saving beats writing beats discarding; an empty compose closes at once")
    func resolution() {
        #expect(ComposeLeavePrompt.resolve(isSaving: true, isBusy: true, hasWork: true) == .busySaving)
        #expect(ComposeLeavePrompt.resolve(isSaving: false, isBusy: true, hasWork: true) == .busyWriting)
        #expect(ComposeLeavePrompt.resolve(isSaving: false, isBusy: false, hasWork: true) == .discard)
        #expect(ComposeLeavePrompt.resolve(isSaving: false, isBusy: false, hasWork: false) == nil)
    }

    @Test("a running save offers no way to leave")
    func savingOnlyWaits() {
        #expect(!ComposeLeavePrompt.busySaving.allowsLeaving)
        #expect(ComposeLeavePrompt.discard.allowsLeaving)
        #expect(ComposeLeavePrompt.discard.confirmTitle == "Discard")
        #expect(ComposeLeavePrompt.busyWriting.cancelTitle == "Keep going")
    }
}
