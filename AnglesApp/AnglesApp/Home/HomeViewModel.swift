import Foundation
import Observation

struct HomeCardSlide: Identifiable, Equatable {
    let id: UUID
    let thought: String
    var result: ReframeResult
    var isFavorite: Bool
    var favoritedAt: Date?
}

struct HomeCard: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    /// Exact server timestamp retained for cursor pagination.
    let createdAtCursor: String
    var slides: [HomeCardSlide]
    var spotlightStyle: Style
    /// Cleaned thought in the language it was typed in, when that is not English.
    var thoughtOriginal: String?
    var isPublic: Bool
    var isOwner: Bool
    var authorInitials: String
    /// In memory only until History (SwiftData) lands. Shape exists now for matching later.
    var meta: ReframeMeta?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        createdAtCursor: String? = nil,
        slides: [HomeCardSlide],
        spotlightStyle: Style = .stoic,
        thoughtOriginal: String? = nil,
        isPublic: Bool = false,
        isOwner: Bool = true,
        authorInitials: String = UserInitials.letters,
        meta: ReframeMeta? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.createdAtCursor = createdAtCursor ?? ISO8601Dates.string(from: createdAt)
        self.slides = slides
        self.spotlightStyle = spotlightStyle
        self.thoughtOriginal = thoughtOriginal
        self.isPublic = isPublic
        self.isOwner = isOwner
        self.authorInitials = authorInitials
        self.meta = meta
    }

    init?(stored: StoredCard) {
        guard let id = UUID(uuidString: stored.id) else {
            return nil
        }
        let slides = stored.results.map { result in
            HomeCardSlide(
                id: UUID(),
                thought: stored.thought,
                result: ReframeResult(style: result.style, reframe: result.reframe),
                isFavorite: result.isFavorite,
                favoritedAt: result.favoritedAt.flatMap { ISO8601Dates.date(from: $0) }
            )
        }
        guard !slides.isEmpty else {
            return nil
        }
        self.init(
            id: id,
            createdAt: ISO8601Dates.date(from: stored.createdAt) ?? Date(),
            createdAtCursor: stored.createdAt,
            slides: slides,
            spotlightStyle: stored.spotlightStyle,
            thoughtOriginal: stored.thoughtOriginal,
            isPublic: stored.isPublic,
            isOwner: stored.isOwner,
            authorInitials: stored.author.initials,
            meta: stored.reframeMeta
        )
    }

    var thought: String {
        slides.first?.thought ?? ""
    }

    var hasFavoriteAngle: Bool {
        slides.contains(where: \.isFavorite)
    }

    var latestFavoritedAt: Date? {
        slides.compactMap(\.favoritedAt).max()
    }

    var latestFavoriteStyle: Style? {
        slides
            .filter(\.isFavorite)
            .max { ($0.favoritedAt ?? .distantPast) < ($1.favoritedAt ?? .distantPast) }?
            .result
            .style
    }

    func hasStyle(_ style: Style) -> Bool {
        slides.contains { $0.result.style == style }
    }

    func isStyleFavorited(_ style: Style) -> Bool {
        slides.first(where: { $0.result.style == style })?.isFavorite ?? false
    }

    mutating func apply(_ stored: StoredCard) {
        isPublic = stored.isPublic
        thoughtOriginal = stored.thoughtOriginal
        for index in slides.indices {
            let style = slides[index].result.style
            guard let match = stored.results.first(where: { $0.style == style }) else {
                continue
            }
            slides[index].result = ReframeResult(style: match.style, reframe: match.reframe)
            slides[index].isFavorite = match.isFavorite
            slides[index].favoritedAt = match.favoritedAt.flatMap { ISO8601Dates.date(from: $0) }
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

/// One Home shelf. `Recent` first, then life-domain and mood shelves zipped together.
enum FeedShelf: Equatable, Hashable {
    case recent
    case category(ThoughtCategory)
    case emotion(Emotion)

    var key: String {
        switch self {
        case .recent:
            return "recent"
        case .category(let category):
            return "category-\(category.rawValue)"
        case .emotion(let emotion):
            return "emotion-\(emotion.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .recent:
            return "Recent"
        case .category(let category):
            return category.displayName
        case .emotion(let emotion):
            return emotion.displayName
        }
    }

    var hint: String {
        switch self {
        case .recent:
            return "Shows the newest published thoughts"
        case .category, .emotion:
            return "Shows every published thought in \(title)"
        }
    }

    var emptyCopy: String {
        switch self {
        case .recent:
            return "No recent thoughts"
        case .category, .emotion:
            return "No cards in \(title)"
        }
    }
}

struct FeedSection: Identifiable, Equatable {
    let shelf: FeedShelf
    let cards: [HomeCard]

    var id: String { shelf.key }
}

struct FeedSubsetState: Equatable {
    var cards: [HomeCard] = []
    var cardIDs: Set<UUID> = []
    var loadState: LibraryLoadState = .loading
    var isLoadingMore = false
    var hasMore = true
    /// `createdAt` of the last card in hand; the cursor the next page asks for.
    var before: String?
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
@Observable
final class HomeViewModel {
    private(set) var cards: [HomeCard]

    var composeText = ""
    private(set) var statement = ""
    private(set) var turns: [RefineTurn] = []
    private(set) var phase: RefinePhase = .composing
    private(set) var cookHaptic = 0
    private(set) var recookingStyle: Style?
    /// Set when a recook comes back as `continue` (that style no longer fits).
    private(set) var recookNotice: String?
    var profileGridFilter: ProfileGridFilter = .all
    /// Home shelves cap at 6, so this filter runs in SQL. Changing it refetches the shelves.
    var homeGridFilter: ProfileGridFilter = .all {
        didSet {
            guard oldValue != homeGridFilter else {
                return
            }
            reloadFeedForFilterChange()
        }
    }
    var selectedModel: LlmModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelDefaultsKey)
        }
    }
    private(set) var libraryLoadState: LibraryLoadState
    /// Every card any shelf references, once. Shelves hold ids into this pool.
    private(set) var feedCards: [HomeCard] = []
    private(set) var feedShelves: [FeedShelfIDs] = []
    private(set) var feedLoadState: LibraryLoadState = .loading
    private(set) var feedSubsets: [String: FeedSubsetState] = [:]
    private(set) var isSaving = false
    private(set) var saveError: String?
    /// A heart, privacy flag, or delete that did not reach the server. The rollback is
    /// invisible on its own, so the root banner reads this.
    private(set) var writeError: String?

    struct FeedShelfIDs: Equatable {
        let shelf: FeedShelf
        let cardIDs: [UUID]
    }

    private let reframeService: ReframeService
    private let cardsService: CardsService
    private var refineTask: Task<Void, Never>?
    private var saveTask: Task<Bool, Never>?
    private var libraryTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var feedSubsetTasks: [String: Task<Void, Never>] = [:]
    private var hasLoadedFeed = false
    private var hasLoadedLibrary = false
    private var favoriteTasks: [String: Task<Void, Never>] = [:]
    private var publicTasks: [UUID: Task<Void, Never>] = [:]
    private var deleteTasks: [UUID: Task<Void, Never>] = [:]
    private var boardTasks: [UUID: Task<Void, Never>] = [:]
    private var writeErrorTask: Task<Void, Never>?

    private static let modelDefaultsKey = "angles.llmModel"
    private static let writeErrorDuration: Duration = .seconds(3)

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

    static let stripLimit = 6
    static let feedSubsetPageSize = 24

    var ownedCards: [HomeCard] {
        cards.filter(\.isOwner)
    }

    var favoriteAngleCards: [HomeCard] {
        cards
            .filter(\.hasFavoriteAngle)
            .sorted { ($0.latestFavoritedAt ?? .distantPast) > ($1.latestFavoritedAt ?? .distantPast) }
    }

    var stripFavoriteCards: [HomeCard] {
        Array(favoriteAngleCards.prefix(Self.stripLimit))
    }

    var filteredProfileCards: [HomeCard] {
        guard let style = profileGridFilter.matchingStyle else {
            return ownedCards
        }

        return ownedCards.filter { $0.hasStyle(style) }
    }

    /// Recent, then the domain/mood zipper. Cards come from the shared pool so an
    /// optimistic heart lands on every shelf that shows that card.
    var feedSections: [FeedSection] {
        guard !feedShelves.isEmpty else {
            return []
        }

        var pool: [UUID: HomeCard] = [:]
        pool.reserveCapacity(feedCards.count)
        for card in feedCards {
            pool[card.id] = card
        }

        return feedShelves.compactMap { shelf in
            let cards = shelf.cardIDs.compactMap { pool[$0] }
            guard !cards.isEmpty else {
                return nil
            }
            return FeedSection(shelf: shelf.shelf, cards: cards)
        }
    }

    func feedSectionCards(_ shelf: FeedShelf) -> [HomeCard] {
        guard let match = feedShelves.first(where: { $0.shelf == shelf }) else {
            return []
        }

        return match.cardIDs.compactMap { id in feedCards.first(where: { $0.id == id }) }
    }

    var feedEmptyCopy: String {
        guard let style = homeGridFilter.matchingStyle else {
            return "No published thoughts yet."
        }

        return "No cards with a \(style.displayName) angle yet"
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

    /// Popping back from a subset must not re-run a cold load.
    func loadLibraryIfNeeded() async {
        guard !hasLoadedLibrary else {
            return
        }

        await loadLibrary()
    }

    func loadLibrary(showsLoading: Bool = true) async {
        if showsLoading, cards.isEmpty {
            libraryLoadState = .loading
        }
        do {
            let stored = try await cardsService.list(limit: 200)
            guard !Task.isCancelled else {
                return
            }
            cards = merged(cards, with: stored)
            hasLoadedLibrary = true
            libraryLoadState = .loaded
        } catch {
            guard !Task.isCancelled else {
                return
            }
            if cards.isEmpty {
                libraryLoadState = .failed("Couldn't load your cards.")
            }
        }
    }

    func retryLoadLibrary() {
        libraryTask?.cancel()
        libraryTask = Task { @MainActor in
            defer { libraryTask = nil }
            await loadLibrary()
        }
    }

    func loadFeedIfNeeded() async {
        guard !hasLoadedFeed else {
            return
        }

        await loadFeed()
    }

    func loadFeed(showsLoading: Bool = true) async {
        if showsLoading, feedCards.isEmpty {
            feedLoadState = .loading
        }
        let style = homeGridFilter.matchingStyle
        do {
            let home = try await cardsService.homeFeed(style: style, perSection: Self.stripLimit)
            guard !Task.isCancelled, style == homeGridFilter.matchingStyle else {
                return
            }
            applyHomeFeed(home)
            hasLoadedFeed = true
            feedLoadState = .loaded
        } catch {
            guard !Task.isCancelled else {
                return
            }
            if feedCards.isEmpty {
                feedLoadState = .failed("Couldn't load Home.")
            }
        }
    }

    func retryLoadFeed() {
        feedTask?.cancel()
        feedTask = Task { @MainActor in
            defer { feedTask = nil }
            await loadFeed()
        }
    }

    private func reloadFeedForFilterChange() {
        for task in feedSubsetTasks.values {
            task.cancel()
        }
        feedSubsetTasks = [:]
        feedSubsets = [:]
        feedTask?.cancel()
        feedTask = Task { @MainActor in
            defer { feedTask = nil }
            // Keep the shelves on screen while the filtered payload lands.
            await loadFeed(showsLoading: false)
        }
    }

    private func applyHomeFeed(_ home: FeedHomeResponse) {
        feedCards = merged(feedCards, with: home.cards)
        feedShelves = Self.zipperedShelves(home)
    }

    /// Deterministic zipper: Recent, then next unused life domain, next unused mood, in
    /// catalog order, skipping shelves the server left out because they were empty.
    private static func zipperedShelves(_ home: FeedHomeResponse) -> [FeedShelfIDs] {
        var shelves: [FeedShelfIDs] = []
        let recent = home.recent.compactMap(UUID.init(uuidString:))
        if !recent.isEmpty {
            shelves.append(FeedShelfIDs(shelf: .recent, cardIDs: recent))
        }

        var categories: [FeedShelfIDs] = []
        var emotions: [FeedShelfIDs] = []
        for section in home.sections {
            let ids = section.cardIds.compactMap(UUID.init(uuidString:))
            guard !ids.isEmpty else {
                continue
            }
            switch section.kind {
            case .category:
                guard let category = ThoughtCategory(rawValue: section.id) else {
                    continue
                }
                categories.append(FeedShelfIDs(shelf: .category(category), cardIDs: ids))
            case .emotion:
                guard let emotion = Emotion(rawValue: section.id) else {
                    continue
                }
                emotions.append(FeedShelfIDs(shelf: .emotion(emotion), cardIDs: ids))
            }
        }

        var categoryIndex = 0
        var emotionIndex = 0
        while categoryIndex < categories.count || emotionIndex < emotions.count {
            if categoryIndex < categories.count {
                shelves.append(categories[categoryIndex])
                categoryIndex += 1
            }
            if emotionIndex < emotions.count {
                shelves.append(emotions[emotionIndex])
                emotionIndex += 1
            }
        }

        return shelves
    }

    /// Updates cards in place so `HomeCardSlide` ids survive a reload and in-card pagers
    /// keep their page.
    private func merged(_ current: [HomeCard], with stored: [StoredCard]) -> [HomeCard] {
        var pool: [UUID: HomeCard] = [:]
        pool.reserveCapacity(current.count)
        for card in current {
            pool[card.id] = card
        }

        var next: [HomeCard] = []
        next.reserveCapacity(stored.count)
        for item in stored {
            guard let id = UUID(uuidString: item.id) else {
                continue
            }
            if var existing = pool[id] {
                existing.apply(item)
                next.append(existing)
            } else if let created = HomeCard(stored: item) {
                next.append(created)
            }
        }

        return next
    }

    func feedSubset(_ shelf: FeedShelf) -> FeedSubsetState {
        feedSubsets[shelf.key] ?? FeedSubsetState()
    }

    /// Seeds the screen with the shelf's cards. The exact last-card cursor lets threshold
    /// prefetch append the next page directly instead of replacing these rows after push.
    func loadFeedSubsetIfNeeded(_ shelf: FeedShelf) async {
        guard feedSubsets[shelf.key] == nil else {
            return
        }

        let seed = feedSectionCards(shelf)
        var state = FeedSubsetState()
        state.cards = seed
        state.cardIDs = Set(seed.map(\.id))
        state.loadState = seed.isEmpty ? .loading : .loaded
        state.before = seed.last?.createdAtCursor
        state.hasMore = seed.isEmpty || seed.count >= Self.stripLimit
        feedSubsets[shelf.key] = state
        if seed.isEmpty {
            await fetchFeedSubsetPage(shelf, replacing: true)
        }
    }

    func retryFeedSubset(_ shelf: FeedShelf) {
        feedSubsetTasks[shelf.key]?.cancel()
        feedSubsetTasks[shelf.key] = Task { @MainActor in
            defer { feedSubsetTasks[shelf.key] = nil }
            await fetchFeedSubsetPage(shelf, replacing: true)
        }
    }

    func loadMoreFeedSubset(_ shelf: FeedShelf) {
        let state = feedSubset(shelf)
        guard state.hasMore, !state.isLoadingMore, state.before != nil, feedSubsetTasks[shelf.key] == nil else {
            return
        }

        feedSubsets[shelf.key]?.isLoadingMore = true
        feedSubsetTasks[shelf.key] = Task { @MainActor in
            defer { feedSubsetTasks[shelf.key] = nil }
            await fetchFeedSubsetPage(shelf, replacing: false)
        }
    }

    private func fetchFeedSubsetPage(_ shelf: FeedShelf, replacing: Bool) async {
        let before = replacing ? nil : feedSubsets[shelf.key]?.before
        var category: ThoughtCategory?
        var emotion: Emotion?
        switch shelf {
        case .recent:
            break
        case .category(let value):
            category = value
        case .emotion(let value):
            emotion = value
        }

        do {
            let stored = try await cardsService.listFeed(
                limit: Self.feedSubsetPageSize,
                before: before,
                category: category,
                emotion: emotion,
                style: homeGridFilter.matchingStyle
            )
            guard !Task.isCancelled, var state = feedSubsets[shelf.key] else {
                return
            }
            if replacing {
                let page = merged(state.cards, with: stored)
                state.cards = page
                state.cardIDs = Set(page.map(\.id))
            } else {
                state.cards.reserveCapacity(state.cards.count + stored.count)
                for item in stored {
                    guard let card = HomeCard(stored: item),
                          state.cardIDs.insert(card.id).inserted
                    else {
                        continue
                    }
                    state.cards.append(card)
                }
            }
            state.before = stored.last?.createdAt
            state.hasMore = stored.count >= Self.feedSubsetPageSize
            state.isLoadingMore = false
            state.loadState = .loaded
            feedSubsets[shelf.key] = state
        } catch {
            guard !Task.isCancelled, var state = feedSubsets[shelf.key] else {
                return
            }
            state.isLoadingMore = false
            if state.cards.isEmpty {
                state.loadState = .failed("Couldn't load \(shelf.title).")
            }
            feedSubsets[shelf.key] = state
        }
    }

    func deleteCard(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].isOwner else {
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
                reportWriteFailure(error, "Couldn't delete that card. Check your connection.")
            }
        }
    }

    func removeFromBoard(_ id: UUID) {
        guard let snapshot = card(id: id), !snapshot.isOwner else {
            return
        }

        applyLocal(id: id) { card in
            for index in card.slides.indices {
                card.slides[index].isFavorite = false
                card.slides[index].favoritedAt = nil
            }
        }
        if let current = card(id: id) {
            syncSavedOtherIntoLibrary(current)
        }

        boardTasks[id]?.cancel()
        boardTasks[id] = Task { @MainActor in
            defer { boardTasks[id] = nil }
            do {
                try await cardsService.removeFromBoard(id: id.uuidString.lowercased())
                guard !Task.isCancelled else {
                    return
                }
                applyLocal(id: id) { card in
                    for index in card.slides.indices {
                        card.slides[index].isFavorite = false
                        card.slides[index].favoritedAt = nil
                    }
                }
                if let current = card(id: id) {
                    syncSavedOtherIntoLibrary(current)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                replaceCard(snapshot)
                syncSavedOtherIntoLibrary(snapshot)
                reportWriteFailure(error, "Couldn't remove that card. Check your connection.")
            }
        }
    }

    func toggleFavorite(_ id: UUID, style: Style) {
        guard let snapshot = card(id: id),
              let slideIndex = snapshot.slides.firstIndex(where: { $0.result.style == style })
        else {
            return
        }

        let previousFavorite = snapshot.slides[slideIndex].isFavorite
        let previousFavoritedAt = snapshot.slides[slideIndex].favoritedAt
        let nextFavorite = !previousFavorite
        applyLocal(id: id) { card in
            guard let currentSlide = card.slides.firstIndex(where: { $0.result.style == style }) else {
                return
            }
            card.slides[currentSlide].isFavorite = nextFavorite
            card.slides[currentSlide].favoritedAt = nextFavorite ? Date() : nil
        }
        if let current = card(id: id) {
            syncSavedOtherIntoLibrary(current)
        }

        let key = Self.favoriteTaskKey(id: id, style: style)
        favoriteTasks[key]?.cancel()
        favoriteTasks[key] = Task { @MainActor in
            defer { favoriteTasks[key] = nil }
            do {
                let stored: StoredCard
                if snapshot.isOwner {
                    stored = try await cardsService.patch(
                        id: id.uuidString.lowercased(),
                        PatchCardRequest(isFavorite: nextFavorite, style: style)
                    )
                } else if nextFavorite {
                    stored = try await cardsService.saveFeedAngle(id: id.uuidString.lowercased(), style: style)
                } else {
                    stored = try await cardsService.unsaveFeedAngle(id: id.uuidString.lowercased(), style: style)
                }
                guard !Task.isCancelled else {
                    return
                }
                applyStored(stored)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                applyLocal(id: id) { card in
                    guard let currentSlide = card.slides.firstIndex(where: { $0.result.style == style }) else {
                        return
                    }
                    card.slides[currentSlide].isFavorite = previousFavorite
                    card.slides[currentSlide].favoritedAt = previousFavoritedAt
                }
                if let current = card(id: id) {
                    syncSavedOtherIntoLibrary(current)
                }
                reportWriteFailure(error, "Couldn't save that. Check your connection.")
            }
        }
    }

    func setPublic(_ id: UUID, isPublic: Bool) {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].isOwner else {
            return
        }

        let previous = cards[index].isPublic
        cards[index].isPublic = isPublic

        publicTasks[id]?.cancel()
        publicTasks[id] = Task { @MainActor in
            defer { publicTasks[id] = nil }
            do {
                let stored = try await cardsService.patch(
                    id: id.uuidString.lowercased(),
                    PatchCardRequest(isPublic: isPublic)
                )
                guard !Task.isCancelled else {
                    return
                }
                if let current = cards.firstIndex(where: { $0.id == id }) {
                    cards[current].apply(stored)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                if let current = cards.firstIndex(where: { $0.id == id }) {
                    cards[current].isPublic = previous
                }
                reportWriteFailure(error, "Couldn't change who can see this. Check your connection.")
            }
        }
    }

    /// Every write here is optimistic, so a rollback looks like the tap never happened.
    /// Say so instead.
    private func reportWriteFailure(_ error: Error, _ message: String) {
        guard !Self.isCancellation(error) else {
            return
        }

        writeError = message
        writeErrorTask?.cancel()
        writeErrorTask = Task { @MainActor in
            defer { writeErrorTask = nil }
            try? await Task.sleep(for: Self.writeErrorDuration)
            guard !Task.isCancelled else {
                return
            }
            writeError = nil
        }
    }

    func dismissWriteError() {
        writeErrorTask?.cancel()
        writeErrorTask = nil
        writeError = nil
    }

    private static func favoriteTaskKey(id: UUID, style: Style) -> String {
        "\(id.uuidString)-\(style.rawValue)"
    }

    private func card(id: UUID) -> HomeCard? {
        if let match = feedCards.first(where: { $0.id == id }) {
            return match
        }
        if let match = cards.first(where: { $0.id == id }) {
            return match
        }
        for state in feedSubsets.values {
            if let match = state.cards.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    private func applyLocal(id: UUID, _ body: (inout HomeCard) -> Void) {
        if let index = feedCards.firstIndex(where: { $0.id == id }) {
            body(&feedCards[index])
        }
        if let index = cards.firstIndex(where: { $0.id == id }) {
            body(&cards[index])
        }
        for (key, state) in feedSubsets {
            guard let index = state.cards.firstIndex(where: { $0.id == id }) else {
                continue
            }
            var next = state
            body(&next.cards[index])
            feedSubsets[key] = next
        }
    }

    private func applyStored(_ stored: StoredCard) {
        guard let id = UUID(uuidString: stored.id) else {
            return
        }
        applyLocal(id: id) { card in
            card.apply(stored)
        }
        if let current = card(id: id) {
            syncSavedOtherIntoLibrary(current)
        } else if let created = HomeCard(stored: stored) {
            syncSavedOtherIntoLibrary(created)
        }
    }

    private func replaceCard(_ card: HomeCard) {
        if let index = feedCards.firstIndex(where: { $0.id == card.id }) {
            feedCards[index] = card
        }
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        }
        for (key, state) in feedSubsets {
            guard let index = state.cards.firstIndex(where: { $0.id == card.id }) else {
                continue
            }
            var next = state
            next.cards[index] = card
            feedSubsets[key] = next
        }
    }

    private func syncSavedOtherIntoLibrary(_ card: HomeCard) {
        guard !card.isOwner else {
            return
        }

        let keep = card.hasFavoriteAngle
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            if keep {
                cards[index] = card
            } else {
                cards.remove(at: index)
            }
        } else if keep {
            cards.insert(card, at: 0)
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
