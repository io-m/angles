import Combine
import Foundation

struct HomeCard: Identifiable, Equatable {
    let id: Int
    let thought: String
    let result: ReframeResult
}

enum DrawerDestination: String, CaseIterable, Hashable, Identifiable {
    case profile = "Profile"
    case settings = "Settings"
    case subscription = "Subscription"
    case about = "About"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .profile:
            return "person"
        case .settings:
            return "gearshape"
        case .subscription:
            return "creditcard"
        case .about:
            return "info.circle"
        }
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
    var result: ReframeResult?
    var error: String?
}

@MainActor
final class HomeViewModel: ObservableObject {
    let cards: [HomeCard]

    @Published var composeText = ""
    @Published var selectedStyle: Style = .optimistic
    @Published private(set) var turns: [ComposeTurn] = []
    @Published private(set) var isCooking = false
    @Published private(set) var cookHaptic = 0

    private var cookTask: Task<Void, Never>?
    private var cookingTurnID: UUID?

    init(cards: [HomeCard]? = nil) {
        self.cards = cards ?? Self.sampleCards
    }

    var canSubmit: Bool {
        !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isCooking
    }

    func selectStyle(_ style: Style, animatedDelay: Bool) {
        let shouldRecook = !turns.isEmpty && selectedStyle != style
        selectedStyle = style

        guard shouldRecook else {
            return
        }

        beginCook(animatedDelay: animatedDelay)
    }

    func submitCompose(animatedDelay: Bool) {
        let thought = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thought.isEmpty, !isCooking else {
            return
        }

        let turn = ComposeTurn(id: UUID(), thought: thought)
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

    func resetCompose() {
        cookTask?.cancel()
        cookTask = nil
        cookingTurnID = nil
        composeText = ""
        selectedStyle = .optimistic
        turns = []
        isCooking = false
    }

    private func beginCook(animatedDelay: Bool, turnID: UUID? = nil) {
        let targetID = turnID ?? turns.last?.id
        guard let targetID, turns.contains(where: { $0.id == targetID }) else {
            return
        }

        let style = selectedStyle

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
            id: 0,
            thought: "I bombed my job interview today.",
            result: ReframeResult(
                style: .stoic,
                reframe: "You can't control the outcome, only how you showed up."
            )
        ),
        HomeCard(
            id: 1,
            thought: "My friend cancelled on me again.",
            result: ReframeResult(
                style: .humorous,
                reframe: "Congrats, you've joined the club of every human who's sweated through this."
            )
        ),
        HomeCard(
            id: 2,
            thought: "I keep procrastinating on my project.",
            result: ReframeResult(
                style: .toughLove,
                reframe: "Stop waiting to feel ready. Start now and feel ready later."
            )
        ),
        HomeCard(
            id: 3,
            thought: "I feel behind compared to my peers.",
            result: ReframeResult(
                style: .optimistic,
                reframe: "Different pace, same direction. You're not behind, you're on your own clock."
            )
        ),
        HomeCard(
            id: 4,
            thought: "I replayed that awkward meeting all night.",
            result: ReframeResult(
                style: .stoic,
                reframe: "The moment has passed. What remains is how you choose to respond now."
            )
        ),
        HomeCard(
            id: 5,
            thought: "They ended the text with a period.",
            result: ReframeResult(
                style: .humorous,
                reframe: "Your brain wrote a twelve-season drama from one punctuation mark."
            )
        ),
        HomeCard(
            id: 6,
            thought: "I missed two days of my new habit.",
            result: ReframeResult(
                style: .optimistic,
                reframe: "Two missed days do not erase every day you chose to begin."
            )
        ),
        HomeCard(
            id: 7,
            thought: "I keep avoiding a difficult conversation.",
            result: ReframeResult(
                style: .toughLove,
                reframe: "Avoiding it is still a choice. Choose the conversation that moves you forward."
            )
        ),
        HomeCard(
            id: 8,
            thought: "I stumbled over my presentation.",
            result: ReframeResult(
                style: .humorous,
                reframe: "A few words tripped. The presentation survived, and so did everyone in the room."
            )
        ),
        HomeCard(
            id: 9,
            thought: "This week has not gone to plan.",
            result: ReframeResult(
                style: .stoic,
                reframe: "The plan changed. Your ability to choose the next useful action did not."
            )
        ),
        HomeCard(
            id: 10,
            thought: "Starting over feels like failure.",
            result: ReframeResult(
                style: .optimistic,
                reframe: "Starting over means you know more this time than you did the first."
            )
        ),
        HomeCard(
            id: 11,
            thought: "I have been waiting for motivation.",
            result: ReframeResult(
                style: .toughLove,
                reframe: "Motivation can catch up. Give it something in motion to follow."
            )
        ),
    ]
}
