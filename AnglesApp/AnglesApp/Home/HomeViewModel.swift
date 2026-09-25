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
    /// Stable author id. Nil when the payload has no UUID, so the avatar does not navigate.
    var authorId: UUID?
    var authorInitials: String
    /// `/avatars/{id}?v=` when this author has a photo. Nil means initials.
    var authorAvatarPath: String?
    /// Viewer follows this author. Always false on your own cards.
    var authorFollowing: Bool
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
        authorId: UUID? = nil,
        authorInitials: String = UserInitials.letters,
        authorAvatarPath: String? = nil,
        authorFollowing: Bool = false,
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
        self.authorId = authorId
        self.authorInitials = authorInitials
        self.authorAvatarPath = authorAvatarPath
        self.authorFollowing = authorFollowing
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
            authorId: UUID(uuidString: stored.author.id),
            authorInitials: stored.author.initials,
            authorAvatarPath: stored.author.avatarUrl,
            authorFollowing: stored.isOwner ? false : stored.author.following,
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
        if let authorId = UUID(uuidString: stored.author.id) {
            self.authorId = authorId
        }
        authorInitials = stored.author.initials
        authorAvatarPath = stored.author.avatarUrl
        authorFollowing = stored.isOwner ? false : stored.author.following
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
    var results: [SignedReframeResult]
    var meta: ReframeMeta
    /// Server signature over `thought`, `thoughtOriginal`, and `meta`; Save sends it back.
    var signature: String
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

struct AuthorHeader: Equatable {
    var initials: String
    var avatarPath: String?
    var isSelf: Bool
    var following: Bool
}

private struct AuthorFeed {
    var initials: String
    var avatarPath: String?
    var isSelf: Bool
    var following: Bool = false
    var cards: [HomeCard] = []
    var cardIDs: Set<UUID> = []
    var loadState: LibraryLoadState = .loading
    var footerState: FeedFooterState = .idle
    var before: String?
    var hasMore = true
    var hasLoaded = false
    var generation = 0
    var task: Task<Void, Never>?
    var isRefreshing = false
}

private struct ModelFeed {
    var cards: [HomeCard] = []
    var cardIDs: Set<UUID> = []
    var loadState: LibraryLoadState = .loading
    var footerState: FeedFooterState = .idle
    var before: String?
    var hasMore = true
    var hasLoaded = false
    var generation = 0
    var task: Task<Void, Never>?
    var isRefreshing = false
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
    var profileGridFilter: ProfileGridFilter = .favorites {
        didSet {
            if profileGridFilter != oldValue {
                ensureProfileTabFilled()
            }
        }
    }
    var homeFeedTab: HomeFeedTab = .all {
        didSet {
            if homeFeedTab != oldValue {
                ensureCurrentTabFilled()
            }
        }
    }
    private(set) var appliedFilter = HomeFeedFilter()
    var selectedModel: LlmModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelDefaultsKey)
        }
    }
    private(set) var libraryLoadState: LibraryLoadState
    private(set) var libraryFooterState: FeedFooterState = .idle
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
    private(set) var followedPeople: [FollowedPerson] = []
    private(set) var followingLoadState: LibraryLoadState = .loading

    private let reframeService: ReframeService
    private let cardsService: CardsService
    private let profileService: ProfileService
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
    private var libraryPageTask: Task<Void, Never>?
    private var libraryBefore: String?
    private var libraryHasMore = false
    private var isLibraryRefreshing = false
    private var favoriteTasks: [String: Task<Void, Never>] = [:]
    private var followTasks: [UUID: Task<Void, Never>] = [:]
    private var followGeneration: [UUID: Int] = [:]
    private var publicTasks: [UUID: Task<Void, Never>] = [:]
    private var deleteTasks: [UUID: Task<Void, Never>] = [:]
    private var boardTasks: [UUID: Task<Void, Never>] = [:]
    private var authorFeeds: [UUID: AuthorFeed] = [:]
    private var modelFeeds: [LlmModel: ModelFeed] = [:]
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
        profileService: ProfileService = ProfileService(),
        libraryLoadState: LibraryLoadState = .loading
    ) {
        self.cards = cards
        self.reframeService = reframeService
        self.cardsService = cardsService
        self.profileService = profileService
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
    static let libraryPageSize = 200
    /// Cards a style tab should show before it stops pulling more pages on its own.
    private static let tabFillMinimum = 6

    var ownedCards: [HomeCard] {
        cards.filter(\.isOwner)
    }

    func applyOwnerIdentity(initials: String, avatarPath: String?) {
        for index in cards.indices where cards[index].isOwner {
            cards[index].authorInitials = initials
            cards[index].authorAvatarPath = avatarPath
        }
        for index in feedCards.indices where feedCards[index].isOwner {
            feedCards[index].authorInitials = initials
            feedCards[index].authorAvatarPath = avatarPath
        }
        for authorId in Array(authorFeeds.keys) {
            mutateAuthor(authorId) { feed in
                if feed.isSelf {
                    feed.initials = initials
                    feed.avatarPath = avatarPath
                }
                for index in feed.cards.indices where feed.cards[index].isOwner {
                    feed.cards[index].authorInitials = initials
                    feed.cards[index].authorAvatarPath = avatarPath
                }
            }
        }
        for model in Array(modelFeeds.keys) {
            mutateModel(model) { feed in
                for index in feed.cards.indices where feed.cards[index].isOwner {
                    feed.cards[index].authorInitials = initials
                    feed.cards[index].authorAvatarPath = avatarPath
                }
            }
        }
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
                        signature: cook.signature,
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
                insertPublicCardIntoLoadedAuthorFeed(card)
                insertPublicCardIntoLoadedModelFeed(card)
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
            try? await Task.sleep(for: .milliseconds(2000))
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
            let response = try await cardsService.list(limit: Self.libraryPageSize)
            guard !Task.isCancelled else {
                return
            }
            cards = merged(cards, with: response.cards)
            libraryBefore = response.page.nextCursor
            libraryHasMore = response.page.hasMore(pageSize: Self.libraryPageSize)
            libraryFooterState = .idle
            hasLoadedLibrary = true
            libraryLoadState = .loaded
            ensureProfileTabFilled()
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
        libraryPageTask?.cancel()
        libraryPageTask = nil
        if libraryFooterState == .loading {
            libraryFooterState = .idle
        }
        isLibraryRefreshing = true
        await loadLibrary(showsLoading: false)
        isLibraryRefreshing = false
    }

    func loadMoreLibrary() {
        guard hasLoadedLibrary,
              libraryHasMore,
              let before = libraryBefore,
              libraryFooterState == .idle,
              libraryPageTask == nil,
              !isLibraryRefreshing
        else {
            return
        }

        libraryFooterState = .loading
        libraryPageTask = Task { @MainActor in
            do {
                let response = try await cardsService.list(limit: Self.libraryPageSize, before: before)
                guard !Task.isCancelled else {
                    return
                }
                let known = Set(cards.map(\.id))
                cards.append(contentsOf: response.cards.compactMap(HomeCard.init(stored:)).filter {
                    !known.contains($0.id)
                })
                libraryBefore = response.page.nextCursor ?? libraryBefore
                libraryHasMore = response.page.hasMore(pageSize: Self.libraryPageSize)
                libraryFooterState = .idle
                libraryPageTask = nil
                ensureProfileTabFilled()
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else {
                    return
                }
                libraryFooterState = .failed
                libraryPageTask = nil
            }
        }
    }

    func retryLoadMoreLibrary() {
        guard libraryFooterState == .failed else {
            return
        }
        libraryFooterState = .idle
        loadMoreLibrary()
    }

    private func ensureProfileTabFilled() {
        guard hasLoadedLibrary,
              libraryHasMore,
              profileCards(for: profileGridFilter).count < Self.tabFillMinimum
        else {
            return
        }
        loadMoreLibrary()
    }

    /// Log out starts over on this iPhone: nothing the last session loaded stays in memory, and
    /// the next unlock loads Home and the library from scratch.
    func resetForSignOut() {
        feedTask?.cancel()
        feedTask = nil
        libraryTask?.cancel()
        libraryTask = nil
        libraryPageTask?.cancel()
        libraryPageTask = nil
        for task in favoriteTasks.values { task.cancel() }
        for task in followTasks.values { task.cancel() }
        for task in publicTasks.values { task.cancel() }
        for task in deleteTasks.values { task.cancel() }
        for task in boardTasks.values { task.cancel() }
        for feed in authorFeeds.values { feed.task?.cancel() }
        for feed in modelFeeds.values { feed.task?.cancel() }
        favoriteTasks = [:]
        followTasks = [:]
        followGeneration = [:]
        publicTasks = [:]
        deleteTasks = [:]
        boardTasks = [:]
        authorFeeds = [:]
        modelFeeds = [:]

        feedGeneration &+= 1
        feedCards = []
        feedCardIDs = []
        feedAnchors = [:]
        feedBefore = nil
        feedHasMore = true
        feedFooterState = .idle
        feedLoadState = .loading
        hasLoadedFeed = false
        appliedFilter = HomeFeedFilter()
        homeFeedTab = .all

        cards = []
        libraryLoadState = .loading
        libraryFooterState = .idle
        libraryBefore = nil
        libraryHasMore = false
        hasLoadedLibrary = false
        profileGridFilter = .favorites

        followedPeople = []
        followingLoadState = .loading
        saveLanding = nil
        dismissWriteError()
        clearShiningCard()
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

        // The cursor stays until page one lands, so a failed or cancelled refresh can still page.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            feedFooterState = .idle
            feedLoadState = feedCards.isEmpty ? .loading : .loaded
        }

        await fetchFeedPage(replacing: true, generation: generation)
        isFeedRefreshing = false
        if generation == feedGeneration {
            ensureCurrentTabFilled()
        }
    }

    func loadMoreFeed() {
        guard feedHasMore,
              feedBefore != nil,
              feedFooterState == .idle,
              feedTask == nil,
              !isFeedRefreshing
        else {
            return
        }

        feedFooterState = .loading
        startFeedTask(replacing: false)
    }

    func retryLoadMoreFeed() {
        guard feedFooterState == .failed, feedTask == nil, !isFeedRefreshing else {
            return
        }

        feedFooterState = .loading
        startFeedTask(replacing: feedBefore == nil)
    }

    /// A style tab only shows the loaded cards that carry its angle, so a thin tab keeps paging
    /// until it has a screenful or the feed runs out.
    private func ensureCurrentTabFilled() {
        guard let style = homeFeedTab.matchingStyle,
              feedLoadState == .loaded,
              feedHasMore,
              feedCards.lazy.filter({ $0.hasStyle(style) }).count < Self.tabFillMinimum
        else {
            return
        }
        loadMoreFeed()
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
            ensureCurrentTabFilled()
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
            let response = try await cardsService.listFeed(
                limit: Self.feedPageSize,
                before: before,
                categories: filter.categories,
                emotions: filter.emotions
            )
            let stored = response.cards
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

                if let cursor = response.page.nextCursor {
                    feedBefore = cursor
                } else if replacing {
                    feedBefore = nil
                }
                feedHasMore = response.page.hasMore(pageSize: Self.feedPageSize)
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
                let authorId = existing.authorId
                let keepFollow = authorId.map { followTasks[$0] != nil } ?? false
                let previousFollow = existing.authorFollowing
                existing.apply(item)
                if keepFollow, !existing.isOwner {
                    existing.authorFollowing = previousFollow
                }
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
        // The visible cards were the filtered subset; page one of the unfiltered feed replaces
        // them in place, and `feedAnchors` keeps the card that was just posted.
        feedBefore = nil
        feedHasMore = true
        feedFooterState = .idle
        startFeedTask(replacing: true, reportsFailure: true)
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

    /// Keeps a loaded author page in step with a public card that just appeared.
    private func insertPublicCardIntoLoadedAuthorFeed(_ card: HomeCard) {
        guard card.isPublic, let authorId = card.authorId, var feed = authorFeeds[authorId], feed.hasLoaded else {
            return
        }
        if let index = feed.cards.firstIndex(where: { $0.id == card.id }) {
            feed.cards[index].isPublic = true
            authorFeeds[authorId] = feed
            return
        }
        if feed.hasMore, let last = feed.cards.last, !feedSortIsBefore(card, last) {
            return
        }
        let index = feed.cards.firstIndex { feedSortIsBefore(card, $0) } ?? feed.cards.endIndex
        feed.cards.insert(card, at: index)
        feed.cardIDs.insert(card.id)
        authorFeeds[authorId] = feed
    }

    /// Keeps a loaded model page in step with a public card cooked by that model.
    private func insertPublicCardIntoLoadedModelFeed(_ card: HomeCard) {
        guard card.isPublic, let model = card.model, var feed = modelFeeds[model], feed.hasLoaded else {
            return
        }
        if let index = feed.cards.firstIndex(where: { $0.id == card.id }) {
            feed.cards[index].isPublic = true
            modelFeeds[model] = feed
            return
        }
        if feed.hasMore, let last = feed.cards.last, !feedSortIsBefore(card, last) {
            return
        }
        let index = feed.cards.firstIndex { feedSortIsBefore(card, $0) } ?? feed.cards.endIndex
        feed.cards.insert(card, at: index)
        feed.cardIDs.insert(card.id)
        modelFeeds[model] = feed
    }

    private func removeFromAuthorFeeds(_ id: UUID) {
        for authorId in Array(authorFeeds.keys) {
            mutateAuthor(authorId) { feed in
                guard feed.cardIDs.remove(id) != nil || feed.cards.contains(where: { $0.id == id }) else {
                    return
                }
                feed.cards.removeAll { $0.id == id }
            }
        }
    }

    private func removeFromModelFeeds(_ id: UUID) {
        for model in Array(modelFeeds.keys) {
            mutateModel(model) { feed in
                guard feed.cardIDs.remove(id) != nil || feed.cards.contains(where: { $0.id == id }) else {
                    return
                }
                feed.cards.removeAll { $0.id == id }
            }
        }
    }

    private func authorCardIndexes(_ id: UUID) -> [UUID: Int] {
        var indexes: [UUID: Int] = [:]
        for (authorId, feed) in authorFeeds {
            if let index = feed.cards.firstIndex(where: { $0.id == id }) {
                indexes[authorId] = index
            }
        }
        return indexes
    }

    private func modelCardIndexes(_ id: UUID) -> [LlmModel: Int] {
        var indexes: [LlmModel: Int] = [:]
        for (model, feed) in modelFeeds {
            if let index = feed.cards.firstIndex(where: { $0.id == id }) {
                indexes[model] = index
            }
        }
        return indexes
    }

    private func restoreAuthorCards(_ card: HomeCard, at indexes: [UUID: Int]) {
        for (authorId, index) in indexes {
            mutateAuthor(authorId) { feed in
                guard !feed.cards.contains(where: { $0.id == card.id }) else {
                    return
                }
                feed.cards.insert(card, at: min(index, feed.cards.count))
                feed.cardIDs.insert(card.id)
            }
        }
    }

    private func restoreModelCards(_ card: HomeCard, at indexes: [LlmModel: Int]) {
        for (model, index) in indexes {
            mutateModel(model) { feed in
                guard !feed.cards.contains(where: { $0.id == card.id }) else {
                    return
                }
                feed.cards.insert(card, at: min(index, feed.cards.count))
                feed.cardIDs.insert(card.id)
            }
        }
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
        for feed in authorFeeds.values {
            if let match = feed.cards.first(where: { $0.id == id }), match.isOwner {
                return match
            }
        }
        for feed in modelFeeds.values {
            if let match = feed.cards.first(where: { $0.id == id }), match.isOwner {
                return match
            }
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
        let previousAuthorIndexes = authorCardIndexes(id)
        let previousModelIndexes = modelCardIndexes(id)
        if libraryIndex != nil {
            cards.removeAll { $0.id == id }
        }
        removeFromFeed(id)
        removeFromAuthorFeeds(id)
        removeFromModelFeeds(id)

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
                restoreAuthorCards(snapshot, at: previousAuthorIndexes)
                restoreModelCards(snapshot, at: previousModelIndexes)
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
                if Self.isNotFound(error) {
                    dropUnavailableCard(id)
                    reportWriteFailure(error, Self.unavailableCardMessage)
                    return
                }
                replaceCard(snapshot)
                syncSavedOtherIntoLibrary(snapshot)
                reportWriteFailure(error, "Couldn't remove that card. Check your connection.")
            }
        }
    }

    private static let unavailableCardMessage = "That card isn't available anymore."

    private static func isNotFound(_ error: Error) -> Bool {
        if case APIError.httpStatus(404, _) = error {
            return true
        }
        return false
    }

    /// Someone else's card that was deleted or made private leaves every list at once.
    private func dropUnavailableCard(_ id: UUID) {
        guard card(id: id)?.isOwner != true else {
            return
        }
        cards.removeAll { $0.id == id }
        removeFromFeed(id)
        removeFromAuthorFeeds(id)
        removeFromModelFeeds(id)
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
                if !snapshot.isOwner, Self.isNotFound(error) {
                    dropUnavailableCard(id)
                    reportWriteFailure(error, Self.unavailableCardMessage)
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

    func loadFollowing() async {
        if followedPeople.isEmpty {
            followingLoadState = .loading
        }
        do {
            let response = try await profileService.following()
            followedPeople = response.users.compactMap(FollowedPerson.init)
            followingLoadState = .loaded
        } catch {
            guard !Self.isCancellation(error) else {
                return
            }
            if followedPeople.isEmpty {
                followingLoadState = .failed("Couldn't load who you follow.")
            }
        }
    }

    func unfollow(_ person: FollowedPerson) {
        guard !isOwnAuthor(person.id) else {
            return
        }
        let index = followedPeople.firstIndex { $0.id == person.id } ?? 0
        followedPeople.removeAll { $0.id == person.id }
        commitFollow(person.id, following: false) {
            guard !self.followedPeople.contains(where: { $0.id == person.id }) else {
                return
            }
            self.followedPeople.insert(person, at: min(index, self.followedPeople.count))
        }
    }

    func toggleFollow(_ authorId: UUID) {
        guard !isOwnAuthor(authorId) else {
            return
        }
        commitFollow(authorId, following: !isFollowing(authorId))
    }

    private func commitFollow(
        _ authorId: UUID,
        following next: Bool,
        onRollback: (() -> Void)? = nil
    ) {
        setFollowing(authorId, following: next)
        let generation = (followGeneration[authorId] ?? 0) + 1
        followGeneration[authorId] = generation
        followTasks[authorId]?.cancel()
        followTasks[authorId] = Task { @MainActor in
            defer {
                if self.followGeneration[authorId] == generation {
                    self.followTasks[authorId] = nil
                }
            }
            do {
                let state =
                    next
                    ? try await cardsService.follow(id: authorId.uuidString.lowercased())
                    : try await cardsService.unfollow(id: authorId.uuidString.lowercased())
                guard !Task.isCancelled, self.followGeneration[authorId] == generation else {
                    return
                }
                setFollowing(authorId, following: state.following)
            } catch {
                guard !Task.isCancelled, self.followGeneration[authorId] == generation else {
                    return
                }
                setFollowing(authorId, following: !next)
                onRollback?()
                reportWriteFailure(error, "Couldn't update that follow. Check your connection.")
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
        let previousAuthorIndexes = authorCardIndexes(id)
        let previousModelIndexes = modelCardIndexes(id)
        applyLocal(id: id) { card in
            card.isPublic = isPublic
        }
        if isPublic {
            snapshot.isPublic = true
            insertPublicCardIntoLoadedFeed(snapshot)
            insertPublicCardIntoLoadedAuthorFeed(snapshot)
            insertPublicCardIntoLoadedModelFeed(snapshot)
        } else {
            removeFromFeed(id)
            removeFromAuthorFeeds(id)
            removeFromModelFeeds(id)
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
                if let cardId = UUID(uuidString: stored.id) {
                    for authorId in Array(authorFeeds.keys) {
                        mutateAuthor(authorId) { feed in
                            if let index = feed.cards.firstIndex(where: { $0.id == cardId }) {
                                feed.cards[index].apply(stored)
                            }
                        }
                    }
                    for model in Array(modelFeeds.keys) {
                        mutateModel(model) { feed in
                            if let index = feed.cards.firstIndex(where: { $0.id == cardId }) {
                                feed.cards[index].apply(stored)
                            }
                        }
                    }
                }
                if stored.isPublic, let card = ownerCard(id: id) {
                    insertPublicCardIntoLoadedFeed(card)
                    insertPublicCardIntoLoadedAuthorFeed(card)
                    insertPublicCardIntoLoadedModelFeed(card)
                } else {
                    removeFromFeed(id)
                    removeFromAuthorFeeds(id)
                    removeFromModelFeeds(id)
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
                if previousPublic {
                    var restored = snapshot
                    restored.isPublic = previousPublic
                    restoreAuthorCards(restored, at: previousAuthorIndexes)
                    restoreModelCards(restored, at: previousModelIndexes)
                } else {
                    removeFromAuthorFeeds(id)
                    removeFromModelFeeds(id)
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

    func showWriteError(_ message: String) {
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
        for feed in authorFeeds.values {
            if let match = feed.cards.first(where: { $0.id == id }) {
                return match
            }
        }
        for feed in modelFeeds.values {
            if let match = feed.cards.first(where: { $0.id == id }) {
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
        for authorId in Array(authorFeeds.keys) {
            mutateAuthor(authorId) { feed in
                if let index = feed.cards.firstIndex(where: { $0.id == id }) {
                    body(&feed.cards[index])
                }
            }
        }
        for model in Array(modelFeeds.keys) {
            mutateModel(model) { feed in
                if let index = feed.cards.firstIndex(where: { $0.id == id }) {
                    body(&feed.cards[index])
                }
            }
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
        for authorId in Array(authorFeeds.keys) {
            mutateAuthor(authorId) { feed in
                if let index = feed.cards.firstIndex(where: { $0.id == card.id }) {
                    feed.cards[index] = card
                }
            }
        }
        for model in Array(modelFeeds.keys) {
            mutateModel(model) { feed in
                if let index = feed.cards.firstIndex(where: { $0.id == card.id }) {
                    feed.cards[index] = card
                }
            }
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
                case .ready(_, _, let incoming, _, _):
                    guard let replacement = incoming.first(where: { $0.style == style }),
                          case .ready(var current) = phase,
                          let index = current.results.firstIndex(where: { $0.style == style })
                    else {
                        return
                    }

                    current.results[index] = replacement
                    phase = .ready(current)
                    cookHaptic += 1
                }
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else {
                    return
                }
                recookNotice = "Couldn't get a new take. Try again."
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
                case .ready(let thought, let thoughtOriginal, let results, let meta, let signature):
                    phase = .ready(
                        ReadyCook(
                            thought: thought,
                            thoughtOriginal: thoughtOriginal,
                            results: results,
                            meta: meta,
                            signature: signature,
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

        let formatter = calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? Self.monthDayFormatter
            : Self.monthDayYearFormatter
        return formatter.string(from: date)
    }

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter
    }()

    func authorHeader(for authorId: UUID) -> AuthorHeader? {
        guard let feed = authorFeeds[authorId] else {
            return nil
        }
        return AuthorHeader(
            initials: feed.initials,
            avatarPath: feed.avatarPath,
            isSelf: feed.isSelf,
            following: feed.isSelf ? false : feed.following
        )
    }

    func authorCards(for authorId: UUID, tab: HomeFeedTab) -> [HomeCard] {
        guard let feed = authorFeeds[authorId] else {
            return []
        }
        guard let style = tab.matchingStyle else {
            return feed.cards
        }
        return feed.cards.filter { $0.hasStyle(style) }
    }

    func authorLoadState(for authorId: UUID) -> LibraryLoadState {
        authorFeeds[authorId]?.loadState ?? .loading
    }

    func authorFooterState(for authorId: UUID) -> FeedFooterState {
        authorFeeds[authorId]?.footerState ?? .idle
    }

    func loadAuthorIfNeeded(_ route: AuthorRoute) async {
        if authorFeeds[route.id] == nil {
            authorFeeds[route.id] = AuthorFeed(
                initials: route.initials,
                avatarPath: route.avatarPath,
                isSelf: route.isSelf,
                following: route.isSelf ? false : isFollowing(route.id)
            )
        }
        guard authorFeeds[route.id]?.hasLoaded != true else {
            return
        }
        if let task = authorFeeds[route.id]?.task {
            await task.value
            return
        }
        startAuthorTask(route.id, replacing: true)
        await authorFeeds[route.id]?.task?.value
    }

    func refreshAuthor(_ id: UUID) async {
        guard authorFeeds[id] != nil, authorFeeds[id]?.isRefreshing != true else {
            return
        }
        // Like Home, the cursor survives until page one lands.
        mutateAuthor(id) { feed in
            feed.isRefreshing = true
            feed.task?.cancel()
            feed.task = nil
            feed.generation &+= 1
            feed.footerState = .idle
            if feed.cards.isEmpty {
                feed.loadState = .loading
            }
        }
        let generation = authorFeeds[id]?.generation ?? 0
        await fetchAuthorPage(id: id, replacing: true, generation: generation)
        mutateAuthor(id) { $0.isRefreshing = false }
    }

    func retryLoadAuthor(_ id: UUID) {
        guard authorFeeds[id] != nil else {
            return
        }
        mutateAuthor(id) { feed in
            feed.task?.cancel()
            feed.task = nil
            feed.generation &+= 1
            feed.before = nil
            feed.hasMore = true
            feed.footerState = .idle
            feed.hasLoaded = false
            if feed.cards.isEmpty {
                feed.loadState = .loading
            }
        }
        startAuthorTask(id, replacing: true)
    }

    func loadMoreAuthor(_ id: UUID) {
        guard let feed = authorFeeds[id],
              feed.hasLoaded,
              feed.hasMore,
              feed.before != nil,
              feed.footerState == .idle,
              feed.task == nil,
              !feed.isRefreshing
        else {
            return
        }
        mutateAuthor(id) { $0.footerState = .loading }
        startAuthorTask(id, replacing: false)
    }

    func retryLoadMoreAuthor(_ id: UUID) {
        guard let feed = authorFeeds[id],
              feed.footerState == .failed,
              feed.task == nil,
              !feed.isRefreshing
        else {
            return
        }
        mutateAuthor(id) { $0.footerState = .loading }
        startAuthorTask(id, replacing: feed.before == nil)
    }

    private func startAuthorTask(_ id: UUID, replacing: Bool) {
        guard var feed = authorFeeds[id], feed.task == nil else {
            return
        }
        let generation = feed.generation
        let task = Task { @MainActor in
            await self.fetchAuthorPage(id: id, replacing: replacing, generation: generation)
            guard self.authorFeeds[id]?.generation == generation else {
                return
            }
            self.mutateAuthor(id) { $0.task = nil }
        }
        feed.task = task
        authorFeeds[id] = feed
    }

    private func fetchAuthorPage(id: UUID, replacing: Bool, generation: Int) async {
        let before = replacing ? nil : authorFeeds[id]?.before
        do {
            let response = try await cardsService.listAuthorCards(
                id: id.uuidString.lowercased(),
                limit: Self.feedPageSize,
                before: before
            )
            guard !Task.isCancelled, authorFeeds[id]?.generation == generation else {
                return
            }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mutateAuthor(id) { feed in
                    let preserveFollow = self.followTasks[id] != nil
                    let preservedFollow = feed.following
                    feed.initials = response.user.initials
                    feed.avatarPath = response.user.avatarUrl
                    if response.cards.contains(where: \.isOwner) {
                        feed.isSelf = true
                    }
                    if replacing {
                        feed.cards = merged(feed.cards, with: response.cards)
                        feed.cardIDs = Set(feed.cards.map(\.id))
                    } else {
                        feed.cards.reserveCapacity(feed.cards.count + response.cards.count)
                        for item in response.cards {
                            guard let card = HomeCard(stored: item) else {
                                continue
                            }
                            guard feed.cardIDs.insert(card.id).inserted else {
                                continue
                            }
                            feed.cards.append(card)
                        }
                    }
                    if let cursor = response.page.nextCursor {
                        feed.before = cursor
                    } else if replacing {
                        feed.before = nil
                    }
                    feed.hasMore = response.page.hasMore(pageSize: Self.feedPageSize)
                    feed.footerState = .idle
                    feed.loadState = .loaded
                    feed.hasLoaded = true
                    if feed.isSelf {
                        feed.following = false
                    } else if preserveFollow {
                        feed.following = preservedFollow
                        for index in feed.cards.indices where feed.cards[index].authorId == id {
                            feed.cards[index].authorFollowing = preservedFollow
                        }
                    } else {
                        feed.following = response.user.following
                    }
                }
            }
        } catch {
            guard !Task.isCancelled, authorFeeds[id]?.generation == generation, !Self.isCancellation(error) else {
                return
            }
            mutateAuthor(id) { feed in
                if case APIError.httpStatus(let status, _) = error, status == 404 {
                    feed.loadState = .failed("That profile isn't available.")
                    feed.footerState = .idle
                    feed.hasMore = false
                } else if replacing, feed.cards.isEmpty {
                    feed.loadState = .failed("Couldn't load these posts.")
                    feed.footerState = .idle
                } else {
                    feed.footerState = .failed
                }
            }
        }
    }

    private func isOwnAuthor(_ authorId: UUID) -> Bool {
        if authorFeeds[authorId]?.isSelf == true {
            return true
        }
        if feedCards.contains(where: { $0.authorId == authorId && $0.isOwner }) {
            return true
        }
        if cards.contains(where: { $0.authorId == authorId && $0.isOwner }) {
            return true
        }
        if authorFeeds.values.contains(where: { feed in
            feed.cards.contains { $0.authorId == authorId && $0.isOwner }
        }) {
            return true
        }
        return modelFeeds.values.contains { feed in
            feed.cards.contains { $0.authorId == authorId && $0.isOwner }
        }
    }

    private func isFollowing(_ authorId: UUID) -> Bool {
        if let feed = authorFeeds[authorId], !feed.isSelf {
            return feed.following
        }
        if let card = feedCards.first(where: { $0.authorId == authorId && !$0.isOwner }) {
            return card.authorFollowing
        }
        if let card = cards.first(where: { $0.authorId == authorId && !$0.isOwner }) {
            return card.authorFollowing
        }
        for feed in authorFeeds.values {
            if let card = feed.cards.first(where: { $0.authorId == authorId && !$0.isOwner }) {
                return card.authorFollowing
            }
        }
        for feed in modelFeeds.values {
            if let card = feed.cards.first(where: { $0.authorId == authorId && !$0.isOwner }) {
                return card.authorFollowing
            }
        }
        return false
    }

    private func setFollowing(_ authorId: UUID, following: Bool) {
        for index in feedCards.indices where feedCards[index].authorId == authorId && !feedCards[index].isOwner {
            feedCards[index].authorFollowing = following
        }
        for index in cards.indices where cards[index].authorId == authorId && !cards[index].isOwner {
            cards[index].authorFollowing = following
        }
        for id in Array(authorFeeds.keys) {
            mutateAuthor(id) { feed in
                if id == authorId, !feed.isSelf {
                    feed.following = following
                }
                for index in feed.cards.indices
                where feed.cards[index].authorId == authorId && !feed.cards[index].isOwner {
                    feed.cards[index].authorFollowing = following
                }
            }
        }
        for model in Array(modelFeeds.keys) {
            mutateModel(model) { feed in
                for index in feed.cards.indices
                where feed.cards[index].authorId == authorId && !feed.cards[index].isOwner {
                    feed.cards[index].authorFollowing = following
                }
            }
        }
    }

    private func mutateAuthor(_ id: UUID, _ body: (inout AuthorFeed) -> Void) {
        guard var feed = authorFeeds[id] else {
            return
        }
        body(&feed)
        authorFeeds[id] = feed
    }

    func modelCards(for model: LlmModel, tab: HomeFeedTab) -> [HomeCard] {
        guard let feed = modelFeeds[model] else {
            return []
        }
        guard let style = tab.matchingStyle else {
            return feed.cards
        }
        return feed.cards.filter { $0.hasStyle(style) }
    }

    func modelLoadState(for model: LlmModel) -> LibraryLoadState {
        modelFeeds[model]?.loadState ?? .loading
    }

    func modelFooterState(for model: LlmModel) -> FeedFooterState {
        modelFeeds[model]?.footerState ?? .idle
    }

    func loadModelIfNeeded(_ model: LlmModel) async {
        if modelFeeds[model] == nil {
            modelFeeds[model] = ModelFeed()
        }
        guard modelFeeds[model]?.hasLoaded != true else {
            return
        }
        if let task = modelFeeds[model]?.task {
            await task.value
            return
        }
        startModelTask(model, replacing: true)
        await modelFeeds[model]?.task?.value
    }

    func refreshModel(_ model: LlmModel) async {
        guard modelFeeds[model] != nil, modelFeeds[model]?.isRefreshing != true else {
            return
        }
        mutateModel(model) { feed in
            feed.isRefreshing = true
            feed.task?.cancel()
            feed.task = nil
            feed.generation &+= 1
            feed.footerState = .idle
            if feed.cards.isEmpty {
                feed.loadState = .loading
            }
        }
        let generation = modelFeeds[model]?.generation ?? 0
        await fetchModelPage(model: model, replacing: true, generation: generation)
        mutateModel(model) { $0.isRefreshing = false }
    }

    func retryLoadModel(_ model: LlmModel) {
        guard modelFeeds[model] != nil else {
            return
        }
        mutateModel(model) { feed in
            feed.task?.cancel()
            feed.task = nil
            feed.generation &+= 1
            feed.before = nil
            feed.hasMore = true
            feed.footerState = .idle
            feed.hasLoaded = false
            if feed.cards.isEmpty {
                feed.loadState = .loading
            }
        }
        startModelTask(model, replacing: true)
    }

    func loadMoreModel(_ model: LlmModel) {
        guard let feed = modelFeeds[model],
              feed.hasLoaded,
              feed.hasMore,
              feed.before != nil,
              feed.footerState == .idle,
              feed.task == nil,
              !feed.isRefreshing
        else {
            return
        }
        mutateModel(model) { $0.footerState = .loading }
        startModelTask(model, replacing: false)
    }

    func retryLoadMoreModel(_ model: LlmModel) {
        guard let feed = modelFeeds[model],
              feed.footerState == .failed,
              feed.task == nil,
              !feed.isRefreshing
        else {
            return
        }
        mutateModel(model) { $0.footerState = .loading }
        startModelTask(model, replacing: feed.before == nil)
    }

    private func startModelTask(_ model: LlmModel, replacing: Bool) {
        guard var feed = modelFeeds[model], feed.task == nil else {
            return
        }
        let generation = feed.generation
        let task = Task { @MainActor in
            await self.fetchModelPage(model: model, replacing: replacing, generation: generation)
            guard self.modelFeeds[model]?.generation == generation else {
                return
            }
            self.mutateModel(model) { $0.task = nil }
        }
        feed.task = task
        modelFeeds[model] = feed
    }

    private func fetchModelPage(model: LlmModel, replacing: Bool, generation: Int) async {
        let before = replacing ? nil : modelFeeds[model]?.before
        do {
            let response = try await cardsService.listModelCards(
                id: model.rawValue,
                limit: Self.feedPageSize,
                before: before
            )
            guard !Task.isCancelled, modelFeeds[model]?.generation == generation else {
                return
            }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mutateModel(model) { feed in
                    if replacing {
                        feed.cards = merged(feed.cards, with: response.cards)
                        feed.cardIDs = Set(feed.cards.map(\.id))
                    } else {
                        feed.cards.reserveCapacity(feed.cards.count + response.cards.count)
                        for item in response.cards {
                            guard let card = HomeCard(stored: item) else {
                                continue
                            }
                            guard feed.cardIDs.insert(card.id).inserted else {
                                continue
                            }
                            feed.cards.append(card)
                        }
                    }
                    if let cursor = response.page.nextCursor {
                        feed.before = cursor
                    } else if replacing {
                        feed.before = nil
                    }
                    feed.hasMore = response.page.hasMore(pageSize: Self.feedPageSize)
                    feed.footerState = .idle
                    feed.loadState = .loaded
                    feed.hasLoaded = true
                }
            }
        } catch {
            guard !Task.isCancelled, modelFeeds[model]?.generation == generation, !Self.isCancellation(error) else {
                return
            }
            mutateModel(model) { feed in
                if replacing, feed.cards.isEmpty {
                    feed.loadState = .failed("Couldn't load these posts.")
                    feed.footerState = .idle
                } else {
                    feed.footerState = .failed
                }
            }
        }
    }

    private func mutateModel(_ model: LlmModel, _ body: (inout ModelFeed) -> Void) {
        guard var feed = modelFeeds[model] else {
            return
        }
        body(&feed)
        modelFeeds[model] = feed
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
