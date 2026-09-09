import Combine
import Foundation

struct HomeCardSlide: Identifiable, Equatable {
    let id: UUID
    let thought: String
    let result: ReframeResult
}

struct HomeCard: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let slides: [HomeCardSlide]

    init(id: UUID = UUID(), createdAt: Date = Date(), slides: [HomeCardSlide]) {
        self.id = id
        self.createdAt = createdAt
        self.slides = slides
    }

    init(id: UUID = UUID(), createdAt: Date = Date(), thought: String, result: ReframeResult) {
        self.id = id
        self.createdAt = createdAt
        self.slides = [
            HomeCardSlide(id: id, thought: thought, result: result)
        ]
    }
}

extension Style {
    var displayName: String {
        switch self {
        case .stoic:
            return "Stoic"
        case .optimistic:
            return "Optimistic"
        case .humorous:
            return "Humorous"
        case .toughLove:
            return "Tough Love"
        }
    }
}

struct ComposeTurn: Identifiable, Equatable {
    let id: UUID
    let thought: String
    let style: Style
    var result: ReframeResult?
    var isSaved: Bool = true
    var error: String?
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var cards: [HomeCard]

    @Published var composeText = ""
    @Published var selectedStyle: Style = .optimistic
    @Published private(set) var turns: [ComposeTurn] = []
    @Published private(set) var isCooking = false
    @Published private(set) var cookHaptic = 0

    private var cookTask: Task<Void, Never>?
    private var cookingTurnID: UUID?
    private var editingCardID: UUID?

    init(cards: [HomeCard]? = nil) {
        self.cards = cards ?? Self.sampleCards
    }

    var canSubmit: Bool {
        !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isCooking
    }

    func selectStyle(_ style: Style) {
        selectedStyle = style
    }

    func submitCompose(animatedDelay: Bool) {
        let thought = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thought.isEmpty, !isCooking else {
            return
        }

        let turn = ComposeTurn(
            id: UUID(),
            thought: thought,
            style: selectedStyle
        )
        turns.append(turn)
        composeText = ""
        beginCook(animatedDelay: animatedDelay, turnID: turn.id)
    }

    func retryCook(animatedDelay: Bool) {
        guard let last = turns.last, !isCooking else {
            return
        }

        beginCook(animatedDelay: animatedDelay, turnID: last.id)
    }

    func toggleSave(turnID: UUID) {
        updateTurn(turnID) { turn in
            guard turn.result != nil else {
                return
            }

            turn.isSaved.toggle()
        }
    }

    func isSaved(turnID: UUID) -> Bool {
        turns.first(where: { $0.id == turnID })?.isSaved == true
    }

    var canPublish: Bool {
        turns.contains { $0.isSaved && $0.result != nil }
    }

    func publishSelected() {
        let slides: [HomeCardSlide] = turns.compactMap { turn in
            guard turn.isSaved, let result = turn.result else {
                return nil
            }

            return HomeCardSlide(
                id: turn.id,
                thought: turn.thought,
                result: result
            )
        }

        guard !slides.isEmpty else {
            return
        }

        if let editingCardID,
           let index = cards.firstIndex(where: { $0.id == editingCardID })
        {
            cards[index] = HomeCard(
                id: editingCardID,
                createdAt: cards[index].createdAt,
                slides: slides
            )
        } else {
            cards.insert(HomeCard(createdAt: Date(), slides: slides), at: 0)
        }
    }

    func beginEdit(_ card: HomeCard) {
        cookTask?.cancel()
        cookTask = nil
        cookingTurnID = nil
        composeText = ""
        isCooking = false
        editingCardID = card.id
        turns = card.slides.map { slide in
            ComposeTurn(
                id: slide.id,
                thought: slide.thought,
                style: slide.result.style,
                result: slide.result,
                isSaved: true
            )
        }
        selectedStyle = turns.last?.style ?? .optimistic
    }

    func deleteCard(_ id: UUID) {
        cards.removeAll { $0.id == id }
        if editingCardID == id {
            resetCompose()
        }
    }

    func resetCompose() {
        cookTask?.cancel()
        cookTask = nil
        cookingTurnID = nil
        editingCardID = nil
        composeText = ""
        selectedStyle = .optimistic
        turns = []
        isCooking = false
    }

    private func beginCook(animatedDelay: Bool, turnID: UUID? = nil) {
        let targetID = turnID ?? turns.last?.id
        guard let targetID,
              let turn = turns.first(where: { $0.id == targetID })
        else {
            return
        }

        let style = turn.style

        cookTask?.cancel()
        cookingTurnID = targetID
        updateTurn(targetID) { turn in
            turn.result = nil
            turn.error = nil
        }
        isCooking = true

        cookTask = Task { @MainActor in
            if animatedDelay {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else {
                return
            }

            updateTurn(targetID) { turn in
                turn.result = ReframeResult(
                    style: style,
                    reframe: Self.fakeReframe(for: style)
                )
                turn.error = nil
            }
            isCooking = false
            cookingTurnID = nil
            cookHaptic += 1
            cookTask = nil
        }
    }

    private func updateTurn(_ id: UUID, mutate: (inout ComposeTurn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&turns[index])
    }

    func isCookingTurn(_ turn: ComposeTurn) -> Bool {
        isCooking && cookingTurnID == turn.id
    }

    private static func minutesAgo(_ minutes: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(-minutes * 60))
    }

    private static func hoursAgo(_ hours: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(-hours * 3600))
    }

    private static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    static func dateLabel(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
            if minutes < 1 {
                return "Just now"
            }
            if minutes < 60 {
                return "\(minutes)m ago"
            }
            return "\(minutes / 60)h ago"
        }

        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = false
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        }
        return formatter.string(from: date)
    }

    private static func fakeReframe(for style: Style) -> String {
        switch style {
        case .stoic:
            return "You cannot control the outcome, only how you meet the moment."
        case .optimistic:
            return "This is one hard moment, not the shape of everything ahead."
        case .humorous:
            return "Your brain has submitted a dramatic first draft. Edits are allowed."
        case .toughLove:
            return "Stop waiting for certainty. Take the smallest useful step now."
        }
    }

    private static let sampleCards: [HomeCard] = [
        HomeCard(
            createdAt: minutesAgo(18),
            slides: [
                HomeCardSlide(
                    id: UUID(),
                    thought: "I bombed my job interview today.",
                    result: ReframeResult(
                        style: .stoic,
                        reframe: "You can't control the outcome, only how you showed up."
                    )
                ),
                HomeCardSlide(
                    id: UUID(),
                    thought: "I bombed my job interview today.",
                    result: ReframeResult(
                        style: .optimistic,
                        reframe: "This is one hard moment, not the shape of everything ahead."
                    )
                ),
            ]
        ),
        HomeCard(
            createdAt: hoursAgo(4),
            thought: "My friend cancelled on me again.",
            result: ReframeResult(
                style: .humorous,
                reframe: "Congrats, you've joined the club of every human who's sweated through this."
            )
        ),
        HomeCard(
            createdAt: daysAgo(2),
            thought: "I keep procrastinating on my project.",
            result: ReframeResult(
                style: .toughLove,
                reframe: "Stop waiting to feel ready. Start now and feel ready later."
            )
        ),
        HomeCard(
            createdAt: daysAgo(3),
            thought: "I feel behind compared to my peers.",
            result: ReframeResult(
                style: .optimistic,
                reframe: "Different pace, same direction. You're not behind, you're on your own clock."
            )
        ),
        HomeCard(
            createdAt: daysAgo(4),
            thought: "I replayed that awkward meeting all night.",
            result: ReframeResult(
                style: .stoic,
                reframe: "The moment has passed. What remains is how you choose to respond now."
            )
        ),
        HomeCard(
            createdAt: daysAgo(5),
            thought: "They ended the text with a period.",
            result: ReframeResult(
                style: .humorous,
                reframe: "Your brain wrote a twelve-season drama from one punctuation mark."
            )
        ),
        HomeCard(
            createdAt: daysAgo(6),
            thought: "I missed two days of my new habit.",
            result: ReframeResult(
                style: .optimistic,
                reframe: "Two missed days do not erase every day you chose to begin."
            )
        ),
        HomeCard(
            createdAt: daysAgo(7),
            thought: "I keep avoiding a difficult conversation.",
            result: ReframeResult(
                style: .toughLove,
                reframe: "Avoiding it is still a choice. Choose the conversation that moves you forward."
            )
        ),
        HomeCard(
            createdAt: daysAgo(8),
            thought: "I stumbled over my presentation.",
            result: ReframeResult(
                style: .humorous,
                reframe: "A few words tripped. The presentation survived, and so did everyone in the room."
            )
        ),
        HomeCard(
            createdAt: daysAgo(9),
            thought: "This week has not gone to plan.",
            result: ReframeResult(
                style: .stoic,
                reframe: "The plan changed. Your ability to choose the next useful action did not."
            )
        ),
        HomeCard(
            createdAt: daysAgo(10),
            thought: "Starting over feels like failure.",
            result: ReframeResult(
                style: .optimistic,
                reframe: "Starting over means you know more this time than you did the first."
            )
        ),
        HomeCard(
            createdAt: daysAgo(11),
            thought: "I have been waiting for motivation.",
            result: ReframeResult(
                style: .toughLove,
                reframe: "Motivation can catch up. Give it something in motion to follow."
            )
        ),
    ]
}
