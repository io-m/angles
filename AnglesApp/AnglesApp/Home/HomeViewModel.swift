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
    /// Cleaned thought in the language it was typed in, when that is not English.
    var thoughtOriginal: String?
    /// In memory only until History (SwiftData) lands. Shape exists now for matching later.
    var meta: ReframeMeta?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        slides: [HomeCardSlide],
        isFavorite: Bool = false,
        spotlightStyle: Style = .stoic,
        favoritedAt: Date? = nil,
        thoughtOriginal: String? = nil,
        meta: ReframeMeta? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.slides = slides
        self.isFavorite = isFavorite
        self.spotlightStyle = spotlightStyle
        self.favoritedAt = favoritedAt
        self.thoughtOriginal = thoughtOriginal
        self.meta = meta
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

/// One `kind: "continue"` turn from the API plus whatever the user sent back.
struct RefineTurn: Identifiable, Equatable {
    let id: UUID
    let message: String
    let options: [String]
    let safety: SafetyFlag
    var reply: String?
    var replyWasChip: Bool = false

    var isAnswered: Bool {
        reply != nil
    }
}

struct ReadyCook: Equatable {
    var thought: String
    var thoughtOriginal: String?
    var results: [ReframeResult]
    var meta: ReframeMeta
}

enum RefinePhase: Equatable {
    case composing
    case cooking
    /// The AI asked for more. The composer stays up.
    case awaitingReply
    case ready(ReadyCook)
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
    @Published private(set) var statement = ""
    @Published private(set) var turns: [RefineTurn] = []
    @Published private(set) var phase: RefinePhase = .composing
    @Published private(set) var cookHaptic = 0
    @Published private(set) var recookingStyle: Style?
    /// Set when a recook comes back as `continue` (that style no longer fits).
    @Published private(set) var recookNotice: String?
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

    /// The composer stays alive for every turn that is not a finished cook.
    var isComposerVisible: Bool {
        switch phase {
        case .composing, .awaitingReply, .error:
            return true
        case .cooking, .ready:
            return false
        }
    }

    var canSubmit: Bool {
        isComposerVisible
            && !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canPublish: Bool {
        if case .ready(let cook) = phase {
            return !cook.results.isEmpty
        }

        return false
    }

    var isCooking: Bool {
        if case .cooking = phase {
            return true
        }

        return false
    }

    var openTurn: RefineTurn? {
        turns.last(where: { !$0.isAnswered })
    }

    private var answeredFollowUps: [FollowUpAnswer] {
        turns.compactMap { turn in
            guard let reply = turn.reply else {
                return nil
            }

            return FollowUpAnswer(question: turn.message, answer: reply)
        }
    }

    /// One entry point for the composer: first thought, reply to a question, or
    /// extra context after an error.
    func sendComposer() {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else {
            return
        }

        composeText = ""
        send(text, isChip: false)
    }

    func chooseOption(_ option: String) {
        let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .awaitingReply = phase, !trimmed.isEmpty else {
            return
        }

        send(trimmed, isChip: true)
    }

    private func send(_ text: String, isChip: Bool) {
        if statement.isEmpty {
            statement = text
            turns = []
        } else if let index = turns.lastIndex(where: { !$0.isAnswered }) {
            turns[index].reply = text
            turns[index].replyWasChip = isChip
        } else {
            statement = "\(statement)\n\n\(text)"
        }

        startRefine()
    }

    func retryRefine() {
        guard case .error = phase, !statement.isEmpty else {
            return
        }

        startRefine()
    }

    func publishSelected() {
        guard case .ready(let cook) = phase, !cook.results.isEmpty else {
            return
        }

        let slides = cook.results.map { result in
            HomeCardSlide(id: UUID(), thought: cook.thought, result: result)
        }
        let styles = cook.results.map(\.style)
        let spotlight = styles[cards.count % styles.count]

        cards.insert(
            HomeCard(
                createdAt: Date(),
                slides: slides,
                spotlightStyle: spotlight,
                thoughtOriginal: cook.thoughtOriginal,
                meta: cook.meta
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
        guard case .ready(let cook) = phase,
              recookingStyle == nil,
              cook.results.contains(where: { $0.style == style })
        else {
            return
        }

        recookingStyle = style
        recookNotice = nil
        // Recook works from the cleaned English thought, not the raw paste.
        let text = cook.thought
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
                    styles: [style],
                    model: model
                )
                guard !Task.isCancelled else {
                    return
                }

                switch response {
                case .continueTurn(let message, _, _):
                    // That style no longer fits this thought; keep what we have.
                    recookNotice = message
                case .ready(_, _, let incoming, _):
                    guard let replacement = incoming.first(where: { $0.style == style }) ?? incoming.first,
                          case .ready(var current) = phase,
                          let index = current.results.firstIndex(where: { $0.style == style })
                    else {
                        return
                    }

                    current.results[index] = ReframeResult(style: style, reframe: replacement.reframe)
                    phase = .ready(current)
                    cookHaptic += 1
                }
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
        statement = ""
        turns = []
        recookingStyle = nil
        recookNotice = nil
        phase = .composing
    }

    private func startRefine() {
        refineTask?.cancel()
        recookingStyle = nil
        recookNotice = nil
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
                case .continueTurn(let message, let options, let safety):
                    turns.append(
                        RefineTurn(
                            id: UUID(),
                            message: message,
                            options: options,
                            safety: safety
                        )
                    )
                    phase = .awaitingReply
                case .ready(let thought, let thoughtOriginal, let results, let meta):
                    phase = .ready(
                        ReadyCook(
                            thought: thought,
                            thoughtOriginal: thoughtOriginal,
                            results: results,
                            meta: meta
                        )
                    )
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
                reframe = SampleCardCopy.reframes[style] ?? highlightText
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
