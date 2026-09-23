import Foundation
import Observation
import SwiftUI

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
    /// Model that wrote the answer. Unknown ids stay nil so the card does not invent a logo.
    var model: LlmModel?
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
        model: LlmModel? = nil,
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
        self.model = model
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
            model: LlmModel(rawValue: stored.model),
            meta: stored.reframeMeta
        )
    }

    var thought: String {
        slides.first?.thought ?? ""
    }

    /// Life-area chrome: closed category plus a proposed label when the cook landed on `other`.
    var lifeAreaPresentation: (category: ThoughtCategory, label: String)? {
        guard let meta else {
            return nil
        }
        let label =
            meta.category == .other
            ? (meta.proposedLabel ?? meta.category.displayName)
            : meta.category.displayName
        return (meta.category, label)
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
        model = LlmModel(rawValue: stored.model)
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

struct HomeFeedFilter: Equatable, Sendable {
    var categories: Set<ThoughtCategory> = []
    var emotions: Set<Emotion> = []

    var appliedCount: Int {
        categories.count + emotions.count
    }
}

enum FeedFooterState: Equatable {
    case idle
    case loading
    case failed
}

enum HomeFeedTab: Equatable, Hashable, CaseIterable {
    case all
    case stoic
    case optimistic
    case humorous
    case toughLove

    var title: String {
        matchingStyle?.displayName ?? "All published thoughts"
    }

    var chipTitle: String {
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

    var systemImage: String {
        guard let style = matchingStyle else {
            return "square.grid.2x2"
        }

        return CardStyleAppearance(style: style).systemImage
    }

    func symbolColor(ink: Color) -> Color {
        guard let style = matchingStyle else {
            return ink
        }

        return CardStyleAppearance(style: style).ink
    }

    var headerWashInk: Color {
        guard let style = matchingStyle else {
            return .clear
        }

        return CardStyleAppearance(style: style).ink
    }

    func emptyCopy(appliedFilter: HomeFeedFilter) -> String {
        if let style = matchingStyle {
            return appliedFilter.appliedCount == 0
                ? "No published \(style.displayName) angles yet."
                : "No cards match these filters."
        }
        return appliedFilter.appliedCount == 0
            ? "No published thoughts yet."
            : "No cards match these filters."
    }
}

enum ProfileGridFilter: Equatable, Hashable, CaseIterable {
    case favorites
    case stoic
    case optimistic
    case humorous
    case toughLove

    var title: String {
        matchingStyle?.displayName ?? "Favorite angles"
    }

    var chipTitle: String {
        matchingStyle?.displayName ?? "Favorites"
    }

    var matchingStyle: Style? {
        switch self {
        case .stoic:
            return .stoic
        case .optimistic:
            return .optimistic
        case .humorous:
            return .humorous
        case .toughLove:
            return .toughLove
        case .favorites:
            return nil
        }
    }

    var systemImage: String {
        guard let style = matchingStyle else {
            return "heart.fill"
        }

        return CardStyleAppearance(style: style).systemImage
    }

    func symbolColor(ink: Color) -> Color {
        guard let style = matchingStyle else {
            return ink
        }

        return CardStyleAppearance(style: style).ink
    }

    var presentation: ReframeCardPresentation {
        self == .favorites ? .favoriteAngles : .library
    }

    var emptyCopy: String {
        switch self {
        case .favorites:
            return "No favorite angles"
        case .stoic, .optimistic, .humorous, .toughLove:
            return "No cards with a \(title) angle yet"
        }
    }

    var headerWashInk: Color {
        guard let style = matchingStyle else {
            return .clear
        }

        return CardStyleAppearance(style: style).ink
    }

    init(spotlight style: Style) {
        switch style {
        case .stoic:
            self = .stoic
        case .optimistic:
            self = .optimistic
        case .humorous:
            self = .humorous
        case .toughLove:
            self = .toughLove
        }
    }
}

enum SaveLanding: Equatable {
    case home
    case profile(ProfileGridFilter)
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var cards: [HomeCard]

    var composeText = ""
    /// Compose Save defaults public; Start again and a new overlay reset this.
    var composeIsPublic = true
    private(set) var statement = ""
    private(set) var turns: [RefineTurn] = []
    private(set) var phase: RefinePhase = .composing
    private(set) var cookHaptic = 0
    private(set) var recookingStyle: Style?
    /// Set when a recook comes back as `continue` (that style no longer fits).
    private(set) var recookNotice: String?
    var profileGridFilter: ProfileGridFilter = .favorites
    var homeFeedTab: HomeFeedTab = .all
    private(set) var appliedFilter = HomeFeedFilter()
    var selectedModel: LlmModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelDefaultsKey)
        }
    }
    private(set) var libraryLoadState: LibraryLoadState
    private(set) var feedCards: [HomeCard] = []
    private(set) var feedLoadState: LibraryLoadState = .loading
    private(set) var feedFooterState: FeedFooterState = .idle
    private(set) var isFeedRefreshing = false
    private(set) var feedHasMore = true
    private(set) var isSaving = false
    private(set) var saveError: String?
    /// Set when a non-taste save should already be on screen under the compose overlay.
    private(set) var saveLanding: SaveLanding?
    private(set) var saveLandingToken = 0
    /// The card whose border shines once after the save cover slides away.
    private(set) var shiningCardID: UUID?
    /// A heart, privacy flag, or delete that did not reach the server. The rollback is
    /// invisible on its own, so the root banner reads this.
    private(set) var writeError: String?

    private let reframeService: ReframeService
    private let cardsService: CardsService
    private var refineTask: Task<Void, Never>?
    private var saveTask: Task<HomeCard?, Never>?
    private var libraryTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var hasLoadedFeed = false
    private var feedGeneration = 0
    private var feedBefore: String?
    private var feedCardIDs: Set<UUID> = []
    /// Public cards inserted locally that a replacing feed page must not drop.
    private var feedAnchors: [UUID: HomeCard] = [:]
    private var hasLoadedLibrary = false
    private var favoriteTasks: [String: Task<Void, Never>] = [:]
    private var publicTasks: [UUID: Task<Void, Never>] = [:]
    private var deleteTasks: [UUID: Task<Void, Never>] = [:]
    private var boardTasks: [UUID: Task<Void, Never>] = [:]
    private var writeErrorTask: Task<Void, Never>?
    private var shineTask: Task<Void, Never>?

    private static let modelDefaultsKey = "angles.llmModel"
    private static let writeErrorDuration: Duration = .seconds(3)
    private static let initialLoadRetryDelays: [Duration] = [
        .milliseconds(400),
        .seconds(1),
        .seconds(2),
    ]

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

    static let feedPageSize = 24

    var ownedCards: [HomeCard] {
        cards.filter(\.isOwner)
    }

    var favoriteAngleCards: [HomeCard] {
        cards
            .filter(\.hasFavoriteAngle)
            .sorted { ($0.latestFavoritedAt ?? .distantPast) > ($1.latestFavoritedAt ?? .distantPast) }
    }

    var filteredProfileCards: [HomeCard] {
        profileCards(for: profileGridFilter)
    }

    func profileCards(for filter: ProfileGridFilter) -> [HomeCard] {
        switch filter {
        case .favorites:
            return favoriteAngleCards
        case .stoic, .optimistic, .humorous, .toughLove:
            guard let style = filter.matchingStyle else {
                return []
            }

            return ownedCards.filter { $0.hasStyle(style) }
        }
    }

    func homeCards(for tab: HomeFeedTab) -> [HomeCard] {
        guard let style = tab.matchingStyle else {
            return feedCards
        }

        return feedCards.filter { $0.hasStyle(style) }
    }

    func feedEmptyCopy(for tab: HomeFeedTab) -> String {
        tab.emptyCopy(appliedFilter: appliedFilter)
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

    var isCookReady: Bool {
        if case .ready = phase {
            return true
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

    func saveCook() async -> HomeCard? {
        guard case .ready(let cook) = phase, !cook.results.isEmpty, !isSaving else {
            return nil
        }

        isSaving = true
        saveError = nil
        let styles = cook.results.map(\.style)
        let spotlight = styles[cards.count % styles.count]
        let task = Task<HomeCard?, Never> { @MainActor in
            do {
                let stored = try await cardsService.create(
                    CreateCardRequest(
                        thought: cook.thought,
                        thoughtOriginal: cook.thoughtOriginal,
                        results: cook.results,
                        meta: cook.meta,
                        model: cook.model.rawValue,
                        spotlightStyle: spotlight,
                        isPublic: composeIsPublic
                    )
                )
                guard !Task.isCancelled else {
                    isSaving = false
                    return nil
                }
                guard let card = HomeCard(stored: stored) else {
                    isSaving = false
                    saveError = "Saved, but couldn't display this card."
                    return nil
                }
                cards.insert(card, at: 0)
                isSaving = false
                return card
            } catch {
                isSaving = false
                guard !Task.isCancelled, !Self.isCancellation(error) else {
                    return nil
                }
                saveError = "Couldn't save this card. Try again."
                return nil
            }
        }
        saveTask = task
        let savedCard = await task.value
        saveTask = nil
        return savedCard
    }

    /// Puts a finished non-taste save on Home or Profile before the cover slides away.
    /// Taste never calls this.
    func landSavedCard(_ card: HomeCard, animated: Bool) {
        if card.isPublic {
            if !matchesFeedFilter(card, appliedFilter) {
                clearFilterWithoutBlanking()
            }
            let animation: Animation? = animated ? .easeOut(duration: 0.32) : nil
            var transaction = Transaction(animation: animation)
            if animation == nil {
                transaction.disablesAnimations = true
            }
            withTransaction(transaction) {
                insertFeedCardAtFront(card)
            }
            homeFeedTab = .all
            saveLanding = .home
        } else {
            let filter = ProfileGridFilter(spotlight: card.spotlightStyle)
            profileGridFilter = filter
            saveLanding = .profile(filter)
        }
        saveLandingToken &+= 1
    }

    /// Clears any active highlight so setting it again restarts the animation.
    func clearShiningCard() {
        shineTask?.cancel()
        shineTask = nil
        shiningCardID = nil
    }

    /// A short colored glow on the card the save just revealed.
    func highlightSavedCard(_ id: UUID) {
        shiningCardID = id
        shineTask?.cancel()
        shineTask = Task { @MainActor in
            defer { shineTask = nil }
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled, shiningCardID == id else {
                return
            }
            shiningCardID = nil
        }
    }

    /// Returning to Profile must not re-run a cold library load.
    func loadLibraryIfNeeded() async {
        guard !hasLoadedLibrary else {
            return
        }

        for attempt in 0 ... Self.initialLoadRetryDelays.count {
            let reportsFailure = attempt == Self.initialLoadRetryDelays.count
            await loadLibrary(reportsFailure: reportsFailure)
            guard !hasLoadedLibrary, !Task.isCancelled else {
                return
            }
            guard attempt < Self.initialLoadRetryDelays.count else {
                return
            }

            libraryLoadState = .loading
            do {
                try await Task.sleep(for: Self.initialLoadRetryDelays[attempt])
            } catch {
                return
            }
        }
    }

    func loadLibrary(showsLoading: Bool = true, reportsFailure: Bool = true) async {
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
            if reportsFailure, cards.isEmpty {
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

    /// Pull-to-refresh: keep showing the current library while re-fetching.
    func refreshLibrary() async {
        libraryTask?.cancel()
        libraryTask = nil
        await loadLibrary(showsLoading: false)
    }

    /// Clears a stale failure before the root decides whether Home is ready to reveal.
    func prepareForFullAppAccess() {
        guard !hasLoadedFeed, feedCards.isEmpty else {
            return
        }
        feedLoadState = .loading
    }

    func loadFeedIfNeeded() async {
        guard !hasLoadedFeed else {
            return
        }

        for attempt in 0 ... Self.initialLoadRetryDelays.count {
            if let feedTask {
                await feedTask.value
            } else {
                if feedCards.isEmpty {
                    feedLoadState = .loading
                }
                let reportsFailure = attempt == Self.initialLoadRetryDelays.count
                startFeedTask(replacing: true, reportsFailure: reportsFailure)
                await feedTask?.value
            }

            guard !hasLoadedFeed, !Task.isCancelled else {
                return
            }
            guard attempt < Self.initialLoadRetryDelays.count else {
                return
            }

            feedLoadState = .loading
            do {
                try await Task.sleep(for: Self.initialLoadRetryDelays[attempt])
            } catch {
                return
            }
        }
    }

    func applyFeedFilter(_ filter: HomeFeedFilter) {
        guard filter != appliedFilter else {
            return
        }

        resetFeed(filter: filter)
        startFeedTask(replacing: true)
    }

    func retryLoadFeed() {
        resetFeed(filter: appliedFilter)
        startFeedTask(replacing: true)
    }

    /// Pull-to-refresh: reload page one without blanking visible cards.
    func refreshFeed() async {
        guard !isFeedRefreshing else {
            return
        }
        isFeedRefreshing = true
        defer { isFeedRefreshing = false }

        feedTask?.cancel()
        feedTask = nil
        feedGeneration &+= 1
        let generation = feedGeneration

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            feedBefore = nil
            feedHasMore = true
            feedFooterState = .idle
            feedLoadState = feedCards.isEmpty ? .loading : .loaded
        }

        await fetchFeedPage(replacing: true, generation: generation)
    }

    func loadMoreFeed() {
        guard feedHasMore,
              feedBefore != nil,
              feedFooterState == .idle,
              feedTask == nil
        else {
            return
        }

        feedFooterState = .loading
        startFeedTask(replacing: false)
    }

    func retryLoadMoreFeed() {
        guard feedFooterState == .failed, feedBefore != nil, feedTask == nil else {
            return
        }

        feedFooterState = .loading
        startFeedTask(replacing: false)
    }

    private func resetFeed(filter: HomeFeedFilter) {
        feedTask?.cancel()
        feedTask = nil
        feedGeneration &+= 1
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            appliedFilter = filter
            feedCards = []
            feedCardIDs = []
            feedBefore = nil
            feedHasMore = true
            feedFooterState = .idle
            feedLoadState = .loading
            hasLoadedFeed = false
        }
    }

    private func startFeedTask(replacing: Bool, reportsFailure: Bool = true) {
        guard feedTask == nil else {
            return
        }

        let generation = feedGeneration
        feedTask = Task { @MainActor in
            await fetchFeedPage(
                replacing: replacing,
                generation: generation,
                reportsFailure: reportsFailure
            )
            guard feedGeneration == generation else {
                return
            }
            feedTask = nil
        }
    }

    private func fetchFeedPage(
        replacing: Bool,
        generation: Int,
        reportsFailure: Bool = true
    ) async {
        let filter = appliedFilter
        let before = replacing ? nil : feedBefore

        do {
            let stored = try await cardsService.listFeed(
                limit: Self.feedPageSize,
                before: before,
                categories: filter.categories,
                emotions: filter.emotions
            )
            guard !Task.isCancelled, generation == feedGeneration else {
                return
            }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if replacing {
                    let page = mergingFeedAnchors(into: merged([], with: stored), filter: filter)
                    feedCards = page
                    feedCardIDs = Set(feedCards.map(\.id))
                } else {
                    feedCards.reserveCapacity(feedCards.count + stored.count)
                    for item in stored {
                        guard let card = HomeCard(stored: item) else {
                            continue
                        }
                        feedAnchors[card.id] = nil
                        guard feedCardIDs.insert(card.id).inserted else {
                            continue
                        }
                        feedCards.append(card)
                    }
                }

                if let last = stored.last {
                    feedBefore = "\(last.createdAt)|\(last.id.lowercased())"
                }
                feedHasMore = stored.count >= Self.feedPageSize
                feedFooterState = .idle
                feedLoadState = .loaded
                hasLoadedFeed = true
            }
        } catch {
            guard !Task.isCancelled, generation == feedGeneration, !Self.isCancellation(error) else {
                return
            }

            if reportsFailure, replacing, feedCards.isEmpty {
                feedLoadState = .failed("Couldn't load Home.")
            } else if reportsFailure {
                feedFooterState = .failed
            }
        }
    }

    /// Updates cards in place so per-card style selection remains stable across writes.
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

    private func matchesFeedFilter(_ card: HomeCard, _ filter: HomeFeedFilter) -> Bool {
        if !filter.categories.isEmpty {
            guard let category = card.meta?.category, filter.categories.contains(category) else {
                return false
            }
        }
        if !filter.emotions.isEmpty {
            let emotions = Set(card.meta?.emotions ?? [])
            guard !emotions.isDisjoint(with: filter.emotions) else {
                return false
            }
        }
        return true
    }

    private func clearFilterWithoutBlanking() {
        guard appliedFilter.appliedCount > 0 else {
            return
        }

        feedTask?.cancel()
        feedTask = nil
        feedGeneration &+= 1
        appliedFilter = HomeFeedFilter()
        feedBefore = nil
        feedHasMore = true
    }

    private func insertFeedCardAtFront(_ card: HomeCard) {
        if let index = feedCards.firstIndex(where: { $0.id == card.id }) {
            feedCards.remove(at: index)
        }
        feedCards.insert(card, at: 0)
        feedCardIDs.insert(card.id)
        feedAnchors[card.id] = card
        if feedLoadState != .loaded {
            feedLoadState = .loaded
        }
    }

    /// Newest-first position inside the cards already on screen.
    private func insertPublicCardIntoLoadedFeed(_ card: HomeCard) {
        guard card.isPublic, hasLoadedFeed, matchesFeedFilter(card, appliedFilter) else {
            return
        }
        if let index = feedCards.firstIndex(where: { $0.id == card.id }) {
            feedCards[index].isPublic = true
            return
        }
        if feedHasMore, let last = feedCards.last, !feedSortIsBefore(card, last) {
            return
        }
        let index = feedCards.firstIndex { feedSortIsBefore(card, $0) } ?? feedCards.endIndex
        feedCards.insert(card, at: index)
        feedCardIDs.insert(card.id)
        feedAnchors[card.id] = card
    }

    private func removeFromFeed(_ id: UUID) {
        feedAnchors[id] = nil
        feedCardIDs.remove(id)
        feedCards.removeAll { $0.id == id }
    }

    private func mergingFeedAnchors(into page: [HomeCard], filter: HomeFeedFilter) -> [HomeCard] {
        var next = page
        let returned = Set(next.map(\.id))
        for id in returned where feedAnchors[id] != nil {
            feedAnchors[id] = nil
        }

        let missing = feedAnchors.values
            .filter { $0.isPublic && matchesFeedFilter($0, filter) && !returned.contains($0.id) }
            .sorted { feedSortIsBefore($0, $1) }
        let pageIsFull = page.count >= Self.feedPageSize
        for anchor in missing {
            if pageIsFull, let last = next.last, !feedSortIsBefore(anchor, last) {
                continue
            }
            let index = next.firstIndex { feedSortIsBefore(anchor, $0) } ?? next.endIndex
            next.insert(anchor, at: index)
        }
        return next
    }

    /// True when `card` belongs above `other` in the newest-first feed.
    private func feedSortIsBefore(_ card: HomeCard, _ other: HomeCard) -> Bool {
        if card.createdAt != other.createdAt {
            return card.createdAt > other.createdAt
        }
        return card.id.uuidString.lowercased() > other.id.uuidString.lowercased()
    }

    private func ownerCard(id: UUID) -> HomeCard? {
        if let match = cards.first(where: { $0.id == id }), match.isOwner {
            return match
        }
        if let match = feedCards.first(where: { $0.id == id }), match.isOwner {
            return match
        }
        return nil
    }

    private func ensureOwnerInLibrary(_ card: HomeCard) {
        guard card.isOwner else {
            return
        }
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        } else {
            cards.insert(card, at: 0)
        }
    }

    func deleteCard(_ id: UUID) {
        guard let snapshot = ownerCard(id: id) else {
            return
        }

        let libraryIndex = cards.firstIndex(where: { $0.id == id })
        let feedIndex = feedCards.firstIndex(where: { $0.id == id })
        if libraryIndex != nil {
            cards.removeAll { $0.id == id }
        }
        removeFromFeed(id)

        deleteTasks[id]?.cancel()
        deleteTasks[id] = Task { @MainActor in
            defer { deleteTasks[id] = nil }
            do {
                try await cardsService.delete(id: id.uuidString.lowercased())
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                if let libraryIndex, !cards.contains(where: { $0.id == id }) {
                    cards.insert(snapshot, at: min(libraryIndex, cards.count))
                }
                if let feedIndex, !feedCards.contains(where: { $0.id == id }) {
                    feedCards.insert(snapshot, at: min(feedIndex, feedCards.count))
                    feedCardIDs.insert(id)
                }
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
        guard var snapshot = ownerCard(id: id) else {
            return
        }
        let previousPublic = snapshot.isPublic
        guard previousPublic != isPublic else {
            return
        }

        ensureOwnerInLibrary(snapshot)
        let previousFeedIndex = feedCards.firstIndex(where: { $0.id == id })
        applyLocal(id: id) { card in
            card.isPublic = isPublic
        }
        if isPublic {
            snapshot.isPublic = true
            insertPublicCardIntoLoadedFeed(snapshot)
        } else {
            removeFromFeed(id)
        }

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
                if let current = feedCards.firstIndex(where: { $0.id == id }) {
                    feedCards[current].apply(stored)
                }
                if stored.isPublic, let card = ownerCard(id: id) {
                    insertPublicCardIntoLoadedFeed(card)
                } else {
                    removeFromFeed(id)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                applyLocal(id: id) { card in
                    card.isPublic = previousPublic
                }
                if let previousFeedIndex {
                    if feedCards.firstIndex(where: { $0.id == id }) == nil {
                        var restored = snapshot
                        restored.isPublic = previousPublic
                        feedCards.insert(restored, at: min(previousFeedIndex, feedCards.count))
                        feedCardIDs.insert(id)
                    }
                } else {
                    removeFromFeed(id)
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
        return nil
    }

    private func applyLocal(id: UUID, _ body: (inout HomeCard) -> Void) {
        if let index = feedCards.firstIndex(where: { $0.id == id }) {
            body(&feedCards[index])
        }
        if let index = cards.firstIndex(where: { $0.id == id }) {
            body(&cards[index])
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
        composeIsPublic = true
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
