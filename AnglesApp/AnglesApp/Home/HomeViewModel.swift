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
    var slides: [HomeCardSlide]
    var isFavorite: Bool
    var spotlightStyle: Style
    var favoritedAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        slides: [HomeCardSlide],
        isFavorite: Bool = false,
        spotlightStyle: Style = .stoic,
        favoritedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.slides = slides
        self.isFavorite = isFavorite
        self.spotlightStyle = spotlightStyle
        self.favoritedAt = favoritedAt
    }

    var thought: String {
        slides.first?.thought ?? ""
    }

    var spotlightSlideID: UUID? {
        slides.first(where: { $0.result.style == spotlightStyle })?.id ?? slides.first?.id
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

struct ClarifyRound: Identifiable, Equatable {
    let id: UUID
    let question: String
    let options: [String]
    var selectedAnswer: String?
    var selectedIsCustom: Bool = false

    var isAnswered: Bool {
        selectedAnswer != nil
    }
}

enum RefinePhase: Equatable {
    case composing
    case cooking
    case awaitingClarify
    case ready([ReframeResult])
    case error(String)
}

enum ProfileGridFilter: Equatable, Hashable, CaseIterable {
    case all
    case stoic
    case optimistic
    case humorous
    case toughLove

    var title: String {
        matchingStyle?.displayName ?? "All"
    }

    var matchingStyle: Style? {
        switch self {
        case .all:
            return nil
        case .stoic:
            return .stoic
        case .optimistic:
            return .optimistic
        case .humorous:
            return .humorous
        case .toughLove:
            return .toughLove
        }
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var cards: [HomeCard]

    @Published var composeText = ""
    @Published var writeNewText = ""
    @Published var isWritingNew = false
    @Published private(set) var statement = ""
    @Published private(set) var clarifyRounds: [ClarifyRound] = []
    @Published private(set) var phase: RefinePhase = .composing
    @Published private(set) var cookHaptic = 0
    @Published private(set) var recookingStyle: Style?
    @Published var profileGridFilter: ProfileGridFilter = .all
    @Published var selectedModel: LlmModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelDefaultsKey)
        }
    }

    private let reframeService: ReframeService
    private var refineTask: Task<Void, Never>?

    private static let modelDefaultsKey = "angles.llmModel"

    init(cards: [HomeCard]? = nil, reframeService: ReframeService = ReframeService()) {
        self.cards = cards ?? Self.sampleCards
        self.reframeService = reframeService
        if let raw = UserDefaults.standard.string(forKey: Self.modelDefaultsKey),
           let model = LlmModel(rawValue: raw) {
            selectedModel = model
        } else {
            selectedModel = .mistral
        }
    }

    var isModelLocked: Bool {
        isCooking || recookingStyle != nil
    }

    static let favoriteStripLimit = 6

    var favoriteCards: [HomeCard] {
        cards
            .filter(\.isFavorite)
            .sorted { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) }
    }

    var stripFavoriteCards: [HomeCard] {
        Array(favoriteCards.prefix(Self.favoriteStripLimit))
    }

    var filteredProfileCards: [HomeCard] {
        guard let style = profileGridFilter.matchingStyle else {
            return cards
        }

        return cards.filter { $0.spotlightStyle == style }
    }

    var canSubmit: Bool {
        phase == .composing
            && !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmitWriteNew: Bool {
        guard case .awaitingClarify = phase, openRound != nil else {
            return false
        }

        return !writeNewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canPublish: Bool {
        if case .ready(let results) = phase {
            return results.count == Style.allCases.count
        }

        return false
    }

    var isCooking: Bool {
        if case .cooking = phase {
            return true
        }

        return false
    }

    private var openRound: ClarifyRound? {
        clarifyRounds.last(where: { !$0.isAnswered })
    }

    private var answeredFollowUps: [FollowUpAnswer] {
        clarifyRounds.compactMap { round in
            guard let answer = round.selectedAnswer else {
                return nil
            }

            return FollowUpAnswer(question: round.question, answer: answer)
        }
    }

    func submitStatement() {
        let thought = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else {
            return
        }

        statement = thought
        composeText = ""
        clarifyRounds = []
        isWritingNew = false
        writeNewText = ""
        startRefine()
    }

    func answerClarify(_ answer: String, isCustom: Bool = false) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .awaitingClarify = phase,
              !trimmed.isEmpty,
              let index = clarifyRounds.lastIndex(where: { !$0.isAnswered })
        else {
            return
        }

        clarifyRounds[index].selectedAnswer = trimmed
        clarifyRounds[index].selectedIsCustom = isCustom
        isWritingNew = false
        writeNewText = ""
        startRefine()
    }

    func submitWriteNew() {
        guard canSubmitWriteNew else {
            return
        }

        answerClarify(writeNewText, isCustom: true)
    }

    func beginWriteNew() {
        guard case .awaitingClarify = phase, openRound != nil else {
            return
        }

        isWritingNew = true
        writeNewText = ""
    }

    func retryRefine() {
        guard case .error = phase, !statement.isEmpty else {
            return
        }

        startRefine()
    }

    func publishSelected() {
        guard case .ready(let results) = phase, !statement.isEmpty else {
            return
        }

        let slides = results.map { result in
            HomeCardSlide(id: UUID(), thought: statement, result: result)
        }
        let styles = Style.allCases
        let spotlight = styles[cards.count % styles.count]

        cards.insert(
            HomeCard(
                createdAt: Date(),
                slides: slides,
                spotlightStyle: spotlight
            ),
            at: 0
        )
    }

    func deleteCard(_ id: UUID) {
        cards.removeAll { $0.id == id }
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else {
            return
        }

        if cards[index].isFavorite {
            cards[index].isFavorite = false
            cards[index].favoritedAt = nil
        } else {
            cards[index].isFavorite = true
            cards[index].favoritedAt = Date()
        }
    }

    func recookStyle(_ style: Style) {
        guard case .ready(let results) = phase,
              recookingStyle == nil,
              results.contains(where: { $0.style == style })
        else {
            return
        }

        recookingStyle = style
        let text = statement
        let followUps = answeredFollowUps
        let model = selectedModel

        refineTask?.cancel()
        refineTask = Task { @MainActor in
            defer {
                if recookingStyle == style {
                    recookingStyle = nil
                }
                refineTask = nil
            }

            do {
                let response = try await reframeService.refine(
                    text: text,
                    followUps: followUps,
                    styles: [style],
                    model: model
                )
                guard !Task.isCancelled else {
                    return
                }

                guard case .ready(let incoming) = response,
                      let replacement = incoming.first(where: { $0.style == style }) ?? incoming.first,
                      case .ready(var current) = phase,
                      let index = current.firstIndex(where: { $0.style == style })
                else {
                    return
                }

                current[index] = ReframeResult(style: style, reframe: replacement.reframe)
                phase = .ready(current)
                cookHaptic += 1
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }
        }
    }

    func resetCompose() {
        refineTask?.cancel()
        refineTask = nil
        composeText = ""
        writeNewText = ""
        isWritingNew = false
        statement = ""
        clarifyRounds = []
        recookingStyle = nil
        phase = .composing
    }

    private func startRefine() {
        refineTask?.cancel()
        recookingStyle = nil
        phase = .cooking
        let text = statement
        let followUps = answeredFollowUps
        let model = selectedModel

        refineTask = Task { @MainActor in
            do {
                let response = try await reframeService.refine(
                    text: text,
                    followUps: followUps,
                    model: model
                )
                guard !Task.isCancelled else {
                    return
                }

                switch response {
                case .clarify(let question, let options):
                    clarifyRounds.append(
                        ClarifyRound(
                            id: UUID(),
                            question: question,
                            options: options
                        )
                    )
                    phase = .awaitingClarify
                case .ready(let results):
                    phase = .ready(results)
                }
                cookHaptic += 1
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                phase = .error("Couldn't generate a reframe. Try again.")
            }
            refineTask = nil
        }
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

    private static func minutesAgo(_ minutes: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(-minutes * 60))
    }

    private static func hoursAgo(_ hours: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(-hours * 3600))
    }

    private static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private static func slides(
        thought: String,
        highlight: Style,
        highlightText: String
    ) -> [HomeCardSlide] {
        Style.allCases.map { style in
            let reframe: String
            if style == highlight {
                reframe = highlightText
            } else {
                reframe = RefineMock.cannedReframes[style] ?? highlightText
            }

            return HomeCardSlide(
                id: UUID(),
                thought: thought,
                result: ReframeResult(style: style, reframe: reframe)
            )
        }
    }

    private static func sampleCard(
        createdAt: Date,
        thought: String,
        highlight: Style,
        highlightText: String,
        isFavorite: Bool = false
    ) -> HomeCard {
        HomeCard(
            createdAt: createdAt,
            slides: slides(thought: thought, highlight: highlight, highlightText: highlightText),
            isFavorite: isFavorite,
            spotlightStyle: highlight,
            favoritedAt: isFavorite ? createdAt : nil
        )
    }

    private static let sampleCards: [HomeCard] = [
        sampleCard(
            createdAt: minutesAgo(18),
            thought: "I bombed my job interview today.",
            highlight: .stoic,
            highlightText: "You can't control the outcome, only how you showed up.",
            isFavorite: true
        ),
        sampleCard(
            createdAt: hoursAgo(4),
            thought: "My friend cancelled on me again.",
            highlight: .humorous,
            highlightText: "Congrats, you've joined the club of every human who's sweated through this.",
            isFavorite: true
        ),
        sampleCard(
            createdAt: daysAgo(2),
            thought: "I keep procrastinating on my project.",
            highlight: .toughLove,
            highlightText: "Stop waiting to feel ready. Start now and feel ready later."
        ),
        sampleCard(
            createdAt: daysAgo(3),
            thought: "I feel behind compared to my peers.",
            highlight: .optimistic,
            highlightText: "Different pace, same direction. You're not behind, you're on your own clock."
        ),
        sampleCard(
            createdAt: daysAgo(4),
            thought: "I replayed that awkward meeting all night.",
            highlight: .stoic,
            highlightText: "The moment has passed. What remains is how you choose to respond now."
        ),
        sampleCard(
            createdAt: daysAgo(5),
            thought: "They ended the text with a period.",
            highlight: .humorous,
            highlightText: "Your brain wrote a twelve-season drama from one punctuation mark."
        ),
        sampleCard(
            createdAt: daysAgo(6),
            thought: "I missed two days of my new habit.",
            highlight: .optimistic,
            highlightText: "Two missed days do not erase every day you chose to begin."
        ),
        sampleCard(
            createdAt: daysAgo(7),
            thought: "I keep avoiding a difficult conversation.",
            highlight: .toughLove,
            highlightText: "Avoiding it is still a choice. Choose the conversation that moves you forward."
        ),
        sampleCard(
            createdAt: daysAgo(8),
            thought: "I stumbled over my presentation.",
            highlight: .humorous,
            highlightText: "A few words tripped. The presentation survived, and so did everyone in the room."
        ),
        sampleCard(
            createdAt: daysAgo(9),
            thought: "This week has not gone to plan.",
            highlight: .stoic,
            highlightText: "The plan changed. Your ability to choose the next useful action did not."
        ),
        sampleCard(
            createdAt: daysAgo(10),
            thought: "Starting over feels like failure.",
            highlight: .optimistic,
            highlightText: "Starting over means you know more this time than you did the first."
        ),
        sampleCard(
            createdAt: daysAgo(11),
            thought: "I have been waiting for motivation.",
            highlight: .toughLove,
            highlightText: "Motivation can catch up. Give it something in motion to follow."
        ),
    ]
}
