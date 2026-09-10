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

    init?(stored: StoredCard) {
        guard let id = UUID(uuidString: stored.id) else {
            return nil
        }
        let slides = stored.results.map { result in
            HomeCardSlide(id: UUID(), thought: stored.thought, result: result)
        }
        guard !slides.isEmpty else {
            return nil
        }
        self.init(
            id: id,
            createdAt: ISO8601Dates.date(from: stored.createdAt) ?? Date(),
            slides: slides,
            isFavorite: stored.isFavorite,
            spotlightStyle: stored.spotlightStyle,
            favoritedAt: stored.favoritedAt.flatMap { ISO8601Dates.date(from: $0) },
            thoughtOriginal: stored.thoughtOriginal,
            meta: stored.reframeMeta
        )
    }

    var thought: String {
        slides.first?.thought ?? ""
    }

    var spotlightSlideID: UUID? {
        slides.first(where: { $0.result.style == spotlightStyle })?.id ?? slides.first?.id
    }

    func hasStyle(_ style: Style) -> Bool {
        slides.contains { $0.result.style == style }
    }

    func openingSlideID(preferring style: Style?) -> UUID? {
        if let style {
            return slides.first(where: { $0.result.style == style })?.id ?? spotlightSlideID
        }

        return spotlightSlideID
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
    var model: LlmModel
}

enum LibraryLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
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
    @Published private(set) var libraryLoadState: LibraryLoadState
    @Published private(set) var isSaving = false
    @Published private(set) var saveError: String?

    private let reframeService: ReframeService
    private let cardsService: CardsService
    private var refineTask: Task<Void, Never>?
    private var saveTask: Task<Bool, Never>?
    private var libraryTask: Task<Void, Never>?
    private var favoriteTasks: [UUID: Task<Void, Never>] = [:]
    private var deleteTasks: [UUID: Task<Void, Never>] = [:]

    private static let modelDefaultsKey = "angles.llmModel"

    init(
        cards: [HomeCard] = [],
        reframeService: ReframeService = ReframeService(),
        cardsService: CardsService = CardsService(),
        libraryLoadState: LibraryLoadState = .loading
    ) {
        self.cards = cards
        self.reframeService = reframeService
        self.cardsService = cardsService
        self.libraryLoadState = libraryLoadState
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

        return cards.filter { $0.hasStyle(style) }
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

    var isSessionBusy: Bool {
        isCooking || recookingStyle != nil || isSaving
    }

    var hasSessionWork: Bool {
        if isSessionBusy {
            return true
        }
        if !statement.isEmpty || !turns.isEmpty {
            return true
        }
        switch phase {
        case .ready, .error:
            return true
        case .composing, .awaitingReply, .cooking:
            return !statement.isEmpty
        }
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

    func saveCook() async -> Bool {
        guard case .ready(let cook) = phase, !cook.results.isEmpty, !isSaving else {
            return false
        }

        isSaving = true
        saveError = nil
        let styles = cook.results.map(\.style)
        let spotlight = styles[cards.count % styles.count]
        let task = Task { @MainActor in
            do {
                let stored = try await cardsService.create(
                    CreateCardRequest(
                        thought: cook.thought,
                        thoughtOriginal: cook.thoughtOriginal,
                        results: cook.results,
                        meta: cook.meta,
                        model: cook.model.rawValue,
                        spotlightStyle: spotlight
                    )
                )
                guard !Task.isCancelled else {
                    isSaving = false
                    return false
                }
                if let card = HomeCard(stored: stored) {
                    cards.insert(card, at: 0)
                }
                isSaving = false
                return true
            } catch {
                isSaving = false
                guard !Task.isCancelled, !Self.isCancellation(error) else {
                    return false
                }
                saveError = "Couldn't save this card. Try again."
                return false
            }
        }
        saveTask = task
        let saved = await task.value
        saveTask = nil
        return saved
    }

    func loadLibrary() async {
        libraryTask?.cancel()
        libraryLoadState = .loading
        do {
            let stored = try await cardsService.list(limit: 100)
            guard !Task.isCancelled else {
                return
            }
            cards = stored.compactMap { HomeCard(stored: $0) }
            libraryLoadState = .loaded
        } catch {
            guard !Task.isCancelled else {
                return
            }
            libraryLoadState = .failed("Couldn't load your cards.")
        }
    }

    func retryLoadLibrary() {
        libraryTask?.cancel()
        libraryTask = Task { @MainActor in
            await loadLibrary()
        }
    }

    func deleteCard(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removed = cards.remove(at: index)
        deleteTasks[id]?.cancel()
        deleteTasks[id] = Task { @MainActor in
            defer { deleteTasks[id] = nil }
            do {
                try await cardsService.delete(id: id.uuidString.lowercased())
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                let insertAt = min(index, cards.count)
                cards.insert(removed, at: insertAt)
            }
        }
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else {
            return
        }

        let previousFavorite = cards[index].isFavorite
        let previousFavoritedAt = cards[index].favoritedAt
        let nextFavorite = !previousFavorite
        cards[index].isFavorite = nextFavorite
        cards[index].favoritedAt = nextFavorite ? Date() : nil

        favoriteTasks[id]?.cancel()
        favoriteTasks[id] = Task { @MainActor in
            defer { favoriteTasks[id] = nil }
            do {
                let stored = try await cardsService.setFavorite(
                    id: id.uuidString.lowercased(),
                    isFavorite: nextFavorite
                )
                guard !Task.isCancelled else {
                    return
                }
                if let updated = HomeCard(stored: stored),
                   let current = cards.firstIndex(where: { $0.id == id }) {
                    cards[current].isFavorite = updated.isFavorite
                    cards[current].favoritedAt = updated.favoritedAt
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                if let current = cards.firstIndex(where: { $0.id == id }) {
                    cards[current].isFavorite = previousFavorite
                    cards[current].favoritedAt = previousFavoritedAt
                }
            }
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
                guard !Task.isCancelled, !Self.isCancellation(error) else {
                    return
                }
            }
        }
    }

    func resetCompose() {
        refineTask?.cancel()
        refineTask = nil
        saveTask?.cancel()
        saveTask = nil
        composeText = ""
        statement = ""
        turns = []
        recookingStyle = nil
        recookNotice = nil
        saveError = nil
        isSaving = false
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
                            meta: meta,
                            model: model
                        )
                    )
                }
                cookHaptic += 1
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else {
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

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }
}
