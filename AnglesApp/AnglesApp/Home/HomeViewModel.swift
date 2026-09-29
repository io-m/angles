import Foundation
import Observation
import SwiftUI

struct HomeCardSlide: Identifiable, Equatable {
    let id: UUID
    let thought: String
    var result: ReframeResult
    var isFavorite: Bool
    var favoritedAt: Date?
    /// Strangers who hearted this angle. Only your own public cards carry it.
    var heartCount: Int?
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
                favoritedAt: result.favoritedAt.flatMap { ISO8601Dates.date(from: $0) },
                heartCount: result.heartCount
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

    /// Other people who hearted this angle. Only your own public cards carry a number,
    /// and never a zero, so nil means there is nothing to show.
    func strangerHearts(for style: Style) -> Int? {
        slides.first(where: { $0.result.style == style })?.heartCount
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
            slides[index].heartCount = match.heartCount
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

private struct BlockAuthorSnapshot {
    let libraryEntries: [(index: Int, card: HomeCard)]
    let shelfEntries: [(placement: HomeFeedPlacement, card: HomeCard)]
    let feedAnchors: [UUID: HomeCard]
    let followedEntry: (index: Int, person: FollowedPerson)?
    let blockedEntry: (index: Int, person: BlockedPerson)?
    let authorFeeds: [UUID: AuthorFeed]
    let modelFeeds: [LlmModel: ModelFeed]
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var cards: [HomeCard]

    /// Outcome of the last pull-to-refresh, with a token so the banner can
    /// re-announce an identical outcome on a second pull.
    private(set) var libraryRefreshOutcome: FeedRefreshOutcome?
    private(set) var libraryRefreshToken = 0

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
    private(set) var usageSummary: UsageSummary?
    private(set) var usageBanner: String?
    private(set) var usageFeedback: String?
    private(set) var composeErrorAllowsRetry = true
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
                loadShelfIfNeeded(homeFeedTab)
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
    private(set) var feedBoard = HomeFeedBoard()
    /// All's first load. Style shelves stay unloaded until their tab is opened.
    var feedLoadState: LibraryLoadState { feedBoard.shelf(.all).loadState }
    /// The banner for the shelf that was just pulled. Switching tabs must not replay it.
    private(set) var feedRefreshOutcome: FeedRefreshOutcome?
    private(set) var feedRefreshToken = 0
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
    private(set) var blockedPeople: [BlockedPerson] = []
    private(set) var blocksLoadState: LibraryLoadState = .loading

    private let reframeService: ReframeService
    private let cardsService: CardsService
    private let profileService: ProfileService
    private var refineTask: Task<Void, Never>?
    private var saveTask: Task<HomeCard?, Never>?
    private var libraryTask: Task<Void, Never>?
    private var feedTasks: [HomeFeedTab: Task<Void, Never>] = [:]
    private var hasLoadedLibrary = false
    private var libraryPageTask: Task<Void, Never>?
    private var libraryBefore: String?
    private var libraryHasMore = false
    private var isLibraryRefreshing = false
    private var favoriteTasks: [String: Task<Void, Never>] = [:]
    private var favoriteGeneration: [String: Int] = [:]
    private var followTasks: [UUID: Task<Void, Never>] = [:]
    private var followGeneration: [UUID: Int] = [:]
    private var publicTasks: [UUID: Task<Void, Never>] = [:]
    private var publicGeneration: [UUID: Int] = [:]
    private var deleteTasks: [UUID: Task<Void, Never>] = [:]
    private var deleteGeneration: [UUID: Int] = [:]
    private var boardTasks: [UUID: Task<Void, Never>] = [:]
    private var boardGeneration: [UUID: Int] = [:]
    private var reportTasks: [UUID: Task<Void, Never>] = [:]
    private var reportGeneration: [UUID: Int] = [:]
    private var blockTasks: [UUID: Task<Void, Never>] = [:]
    private var blockGeneration: [UUID: Int] = [:]
    private var blocksGeneration = 0
    private var writeSessionGeneration = 0
    private var authorFeeds: [UUID: AuthorFeed] = [:]
    private var modelFeeds: [LlmModel: ModelFeed] = [:]
    private var writeErrorTask: Task<Void, Never>?
    private var shineTask: Task<Void, Never>?
    private var usageBannerTask: Task<Void, Never>?
    private var isLoadingUsage = false
    private var hasLoadedUsage = false
    private var usageAccountID: String?
    private var usageGeneration = 0
    private var refineGeneration = 0
    private var pendingRefineRequestID: UUID?
    private var pendingRecookRequestID: UUID?
    private var pendingRecookStyle: Style?

    private static let modelDefaultsKey = "angles.llmModel"
    private static let lowWarningPeriodKeyPrefix = "angles.lowCreditWarningPeriod"
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

    func isModelAvailable(_ model: LlmModel) -> Bool {
        guard let usageSummary else {
            // Local development may run against a backend without `/profile/usage`.
            return true
        }
        return usageSummary.allowedModels.contains(model.rawValue)
    }

    func creditCost(for model: LlmModel) -> Int {
        usageSummary?.creditCost[model.rawValue] ?? model.creditCost
    }

    var usagePickerStatus: String? {
        guard let usageSummary else {
            return nil
        }
        switch usageSummary.warning {
        case .empty:
            if let resetDate = usageSummary.resetDate {
                return "You’re out of credits until \(resetDate.formatted(date: .abbreviated, time: .omitted))."
            }
            return "You’re out of credits."
        case .critical:
            return "\(usageSummary.creditsRemaining) credits remaining · Almost out."
        case .normal, .low:
            return "\(usageSummary.creditsRemaining) credits remaining"
        }
    }

    static let feedPageSize = 24
    /// A refresh only asks the head for arrivals, which are rare. A full page there
    /// would be wasted bytes on every pull.
    static let feedHeadLimit = 8
    static let libraryPageSize = 200
    /// Profile keeps paging a thin style tab until it has something to show.
    private static let tabFillMinimum = 6

    var ownedCards: [HomeCard] {
        cards.filter(\.isOwner)
    }

    func applyOwnerIdentity(initials: String, avatarPath: String?) {
        for index in cards.indices where cards[index].isOwner {
            cards[index].authorInitials = initials
            cards[index].authorAvatarPath = avatarPath
        }
        feedBoard.updateOwners(initials: initials, avatarPath: avatarPath)
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
        feedBoard.cards(on: tab)
    }

    func feedLoadState(for tab: HomeFeedTab) -> LibraryLoadState {
        feedBoard.shelf(tab).loadState
    }

    func feedFooterState(for tab: HomeFeedTab) -> FeedFooterState {
        feedBoard.shelf(tab).footerState
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
            && isModelAvailable(selectedModel)
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

        let requestID = UUID()
        pendingRefineRequestID = requestID
        startRefine(requestID: requestID)
    }

    func retryRefine() {
        guard case .error = phase, !statement.isEmpty, composeErrorAllowsRetry else {
            return
        }

        let requestID = pendingRefineRequestID ?? UUID()
        pendingRefineRequestID = requestID
        startRefine(requestID: requestID)
    }

    /// `forcePrivate` is the onboarding taste: that save is private whatever the toggle says.
    func saveCook(forcePrivate: Bool = false) async -> HomeCard? {
        guard case .ready(let cook) = phase, !cook.results.isEmpty, !isSaving else {
            return nil
        }

        isSaving = true
        saveError = nil
        let styles = cook.results.map(\.style)
        let spotlight = styles[cards.count % styles.count]
        let isPublic = forcePrivate ? false : composeIsPublic
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
                        isPublic: isPublic
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
                saveError = Self.publicModerationMessage(for: error)
                    ?? "Couldn't save this card. Try again."
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

    /// One account-scoped summary is shared by Home, Profile, and compose.
    func configureUsageAccount(userID: String?) {
        guard usageAccountID != userID else {
            return
        }
        usageGeneration &+= 1
        usageAccountID = userID
        usageSummary = nil
        usageFeedback = nil
        dismissUsageBanner()
        isLoadingUsage = false
        hasLoadedUsage = false
    }

    func loadUsageIfNeeded() async {
        guard usageAccountID != nil, !hasLoadedUsage, !isLoadingUsage else {
            return
        }
        let generation = usageGeneration
        isLoadingUsage = true
        defer {
            if generation == usageGeneration {
                isLoadingUsage = false
            }
        }

        do {
            let summary = try await profileService.usage()
            guard !Task.isCancelled, generation == usageGeneration else {
                return
            }
            hasLoadedUsage = true
            if usageSummary == nil {
                applyUsage(summary)
            }
        } catch {
            // Older/local backends may not expose usage yet. `nil` deliberately leaves every
            // picker row enabled until an authoritative summary or reframe response arrives.
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

    @discardableResult
    func loadLibrary(showsLoading: Bool = true, reportsFailure: Bool = true) async -> PageFetchResult {
        if showsLoading, cards.isEmpty {
            libraryLoadState = .loading
        }
        do {
            let response = try await cardsService.list(limit: Self.libraryPageSize)
            guard !Task.isCancelled else {
                return .discarded
            }
            cards = merged(cards, with: response.cards)
            libraryBefore = response.page.nextCursor
            libraryHasMore = response.page.hasMore(pageSize: Self.libraryPageSize)
            libraryFooterState = .idle
            hasLoadedLibrary = true
            libraryLoadState = .loaded
            ensureProfileTabFilled()
            return .success
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else {
                return .discarded
            }
            if reportsFailure, cards.isEmpty {
                libraryLoadState = .failed("Couldn't load your cards.")
            }
            return .failure
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
        // Cleared on every exit: a stuck flag would silently block paging.
        defer { isLibraryRefreshing = false }

        let known = Set(cards.map(\.id))
        let result = await loadLibrary(showsLoading: false)
        let added = cards.filter { !known.contains($0.id) }.count
        switch result {
        case .success:
            libraryRefreshOutcome = added > 0 ? .newItems(added) : .upToDate
            libraryRefreshToken &+= 1
        case .failure:
            libraryRefreshOutcome = .failed
            libraryRefreshToken &+= 1
        case .discarded:
            break
        }
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
                    !known.contains($0.id) && !isLocallyBlocked($0)
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
        writeSessionGeneration &+= 1
        refineGeneration &+= 1
        libraryTask?.cancel()
        libraryTask = nil
        libraryPageTask?.cancel()
        libraryPageTask = nil
        for task in favoriteTasks.values { task.cancel() }
        for task in followTasks.values { task.cancel() }
        for task in publicTasks.values { task.cancel() }
        for task in deleteTasks.values { task.cancel() }
        for task in boardTasks.values { task.cancel() }
        for task in reportTasks.values { task.cancel() }
        for task in blockTasks.values { task.cancel() }
        for task in feedTasks.values { task.cancel() }
        for feed in authorFeeds.values { feed.task?.cancel() }
        for feed in modelFeeds.values { feed.task?.cancel() }
        favoriteTasks = [:]
        favoriteGeneration = [:]
        followTasks = [:]
        followGeneration = [:]
        publicTasks = [:]
        publicGeneration = [:]
        deleteTasks = [:]
        deleteGeneration = [:]
        boardTasks = [:]
        boardGeneration = [:]
        reportTasks = [:]
        reportGeneration = [:]
        blockTasks = [:]
        blockGeneration = [:]
        authorFeeds = [:]
        modelFeeds = [:]

        feedTasks = [:]
        feedBoard.reset()
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
        blockedPeople = []
        blocksLoadState = .loading
        blocksGeneration &+= 1
        configureUsageAccount(userID: nil)
        saveLanding = nil
        dismissWriteError()
        clearShiningCard()
    }

    /// Clears a stale failure before the root decides whether Home is ready to reveal.
    /// Clears a stale failure before the root decides whether Home is ready to reveal.
    func prepareForFullAppAccess() {
        let shelf = feedBoard.shelf(.all)
        guard !shelf.hasLoaded, shelf.order.isEmpty else {
            return
        }
        feedBoard.markLoading(on: .all, replacing: true)
    }

    func loadFeedIfNeeded() async {
        let initial = feedBoard.shelf(.all)
        guard !initial.hasLoaded else {
            return
        }

        let generation = initial.generation
        defer {
            let shelf = feedBoard.shelf(.all)
            // A cancelled first load must not strand the arrival on Loading with nothing running.
            if Task.isCancelled, shelf.generation == generation, !shelf.hasLoaded,
               feedTasks[.all] == nil, shelf.order.isEmpty, shelf.loadState == .loading {
                _ = feedBoard.fail(
                    on: .all,
                    generation: generation,
                    replacing: true,
                    message: "Couldn't load Home."
                )
            }
        }

        for attempt in 0 ... Self.initialLoadRetryDelays.count {
            if let task = feedTasks[.all] {
                await task.value
            } else {
                let reportsFailure = attempt == Self.initialLoadRetryDelays.count
                startFeedTask(on: .all, replacing: true, reportsFailure: reportsFailure)
                await feedTasks[.all]?.value
            }

            guard !feedBoard.shelf(.all).hasLoaded, !Task.isCancelled else {
                return
            }
            guard attempt < Self.initialLoadRetryDelays.count else {
                return
            }

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

        appliedFilter = filter
        cancelFeedTasks()
        feedBoard.invalidate(blank: true)
        startFeedTask(on: homeFeedTab, replacing: true)
    }

    func retryLoadFeed(_ tab: HomeFeedTab = .all) {
        cancelFeedTask(tab)
        feedBoard.stopRefresh(on: tab)
        _ = feedBoard.bump(tab)
        feedBoard.markLoading(on: tab, replacing: true)
        startFeedTask(on: tab, replacing: true)
    }

    /// Pull-to-refresh for the shelf that was pulled. Each tab keeps its own cursor,
    /// so a Stoic pull cannot rotate All, and the other way around.
    func refreshFeed(_ tab: HomeFeedTab = .all) async {
        guard let generation = feedBoard.beginRefresh(on: tab) else {
            return
        }
        cancelFeedTask(tab)
        defer { feedBoard.endRefresh(on: tab, generation: generation) }

        let filter = appliedFilter
        let shelf = feedBoard.shelf(tab)

        // `after` makes the head strictly arrivals. Without it the server would answer
        // with the top of the feed, which under ranking need not contain the newest posts.
        async let headFetch = fetchFeedCards(
            on: tab,
            limit: Self.feedHeadLimit,
            after: shelf.highWater?.cursor,
            filter: filter,
            generation: generation
        )
        async let tailFetch = fetchFeedTail(on: tab, filter: filter, generation: generation)
        let head = await headFetch
        let tail = await tailFetch

        guard feedBoard.shelf(tab).generation == generation else {
            return
        }
        if case .discarded = head {
            return
        }
        if case .discarded = tail {
            return
        }

        await applyRefresh(head: head, tail: tail, filter: filter, tab: tab, generation: generation)
    }

    private func fetchFeedTail(
        on tab: HomeFeedTab,
        filter: HomeFeedFilter,
        generation: Int
    ) async -> FeedPageOutcome {
        let shelf = feedBoard.shelf(tab)
        guard shelf.hasMore, let before = shelf.before else {
            return .exhausted
        }
        return await fetchFeedCards(
            on: tab,
            limit: Self.feedPageSize,
            before: before,
            filter: filter,
            generation: generation
        )
    }

    private func applyRefresh(
        head: FeedPageOutcome,
        tail: FeedPageOutcome,
        filter: HomeFeedFilter,
        tab: HomeFeedTab,
        generation: Int
    ) async {
        if case .failed = head, case .failed = tail {
            publishFeedRefresh(.failed, on: tab, generation: generation)
            return
        }

        let current = feedBoard.cards(on: tab)
        let headCards = head.stored.map { merged(current, with: $0) }
        let plan = FeedRefreshPlanner.plan(
            head: headCards,
            headLimit: Self.feedHeadLimit,
            tail: tail.stored.map { merged(current, with: $0) } ?? [],
            highWater: feedBoard.shelf(tab).highWater,
            seenIDs: feedBoard.shelf(tab).seenIDs,
            pageSize: Self.feedPageSize,
            isRotated: feedBoard.shelf(tab).isRotated
        )

        switch plan {
        case let .prepend(arrivals):
            prependFeedCards(arrivals, on: tab, generation: generation)
            publishFeedRefresh(.newItems(arrivals.count), on: tab, generation: generation)
        case let .catchUp(newCount):
            await reloadNewestFeedPage(on: tab, generation: generation)
            publishFeedRefresh(.newItems(newCount), on: tab, generation: generation)
        case let .rotate(rotation):
            _ = feedBoard.rotate(
                rotation.page,
                on: tab,
                before: tail.serverCursor ?? rotation.nextBefore,
                hasMore: rotation.consumedWholeTail ? tail.hasMore : true,
                generation: generation,
                filter: { matchesFeedFilter($0, filter) },
                pageSize: Self.feedPageSize
            )
            publishFeedRefresh(.rotated, on: tab, generation: generation)
        case .restart:
            await reloadNewestFeedPage(on: tab, generation: generation)
            publishFeedRefresh(.restarted, on: tab, generation: generation)
        case .unchanged:
            publishFeedRefresh(tail.didFail ? .failed : .upToDate, on: tab, generation: generation)
        }
    }

    private func publishFeedRefresh(
        _ outcome: FeedRefreshOutcome,
        on tab: HomeFeedTab,
        generation: Int
    ) {
        guard feedBoard.publish(outcome, on: tab, generation: generation) == .applied else {
            return
        }
        guard tab == homeFeedTab else {
            return
        }
        feedRefreshOutcome = outcome
        feedRefreshToken &+= 1
    }

    private func prependFeedCards(_ arrivals: [HomeCard], on tab: HomeFeedTab, generation: Int) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            _ = feedBoard.prepend(arrivals, on: tab, generation: generation)
        }
    }

    /// Back to the top of this shelf's rotation: the newest page, with its visit history cleared.
    private func reloadNewestFeedPage(on tab: HomeFeedTab, generation: Int) async {
        guard feedBoard.clearVisitHistory(on: tab, generation: generation) == .applied else {
            return
        }
        await fetchFeedPage(on: tab, replacing: true, generation: generation)
    }

    func loadMoreFeed(_ tab: HomeFeedTab = .all) {
        let shelf = feedBoard.shelf(tab)
        guard shelf.hasMore,
              shelf.before != nil,
              shelf.footerState == .idle,
              feedTasks[tab] == nil,
              !shelf.isRefreshing
        else {
            return
        }

        feedBoard.setFooter(.loading, on: tab)
        startFeedTask(on: tab, replacing: false)
    }

    func retryLoadMoreFeed(_ tab: HomeFeedTab = .all) {
        let shelf = feedBoard.shelf(tab)
        guard shelf.footerState == .failed, feedTasks[tab] == nil, !shelf.isRefreshing else {
            return
        }

        feedBoard.setFooter(.loading, on: tab)
        startFeedTask(on: tab, replacing: shelf.before == nil)
    }

    private func loadShelfIfNeeded(_ tab: HomeFeedTab) {
        let shelf = feedBoard.shelf(tab)
        guard !shelf.hasLoaded, feedTasks[tab] == nil else {
            return
        }
        startFeedTask(on: tab, replacing: true)
    }

    private func startFeedTask(on tab: HomeFeedTab, replacing: Bool, reportsFailure: Bool = true) {
        guard feedTasks[tab] == nil else {
            return
        }

        let generation = feedBoard.shelf(tab).generation
        feedTasks[tab] = Task { @MainActor in
            await fetchFeedPage(
                on: tab,
                replacing: replacing,
                generation: generation,
                reportsFailure: reportsFailure
            )
            guard feedBoard.shelf(tab).generation == generation else {
                return
            }
            feedTasks[tab] = nil
        }
    }

    private func cancelFeedTask(_ tab: HomeFeedTab) {
        feedTasks[tab]?.cancel()
        feedTasks[tab] = nil
    }

    private func cancelFeedTasks() {
        for tab in HomeFeedTab.allCases {
            cancelFeedTask(tab)
        }
    }

    @discardableResult
    private func fetchFeedPage(
        on tab: HomeFeedTab,
        replacing: Bool,
        generation: Int,
        reportsFailure: Bool = true
    ) async -> PageFetchResult {
        let filter = appliedFilter
        let before = replacing ? nil : feedBoard.shelf(tab).before

        do {
            let response = try await cardsService.listFeed(
                limit: Self.feedPageSize,
                before: before,
                categories: filter.categories,
                emotions: filter.emotions,
                style: tab.matchingStyle
            )
            guard !Task.isCancelled, feedBoard.shelf(tab).generation == generation else {
                return .discarded
            }

            let stored = mergeFeed(response.cards)
            var commit = HomeFeedBoard.Commit.stale
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if replacing {
                    commit = feedBoard.replace(
                        stored,
                        on: tab,
                        before: response.page.nextCursor,
                        hasMore: response.page.hasMore(pageSize: Self.feedPageSize),
                        generation: generation,
                        filter: { matchesFeedFilter($0, filter) },
                        pageSize: Self.feedPageSize
                    )
                } else {
                    commit = feedBoard.append(
                        stored,
                        on: tab,
                        before: response.page.nextCursor,
                        hasMore: response.page.hasMore(pageSize: Self.feedPageSize),
                        generation: generation
                    )
                }
            }
            return commit == .stale ? .discarded : .success
        } catch {
            guard !Task.isCancelled, feedBoard.shelf(tab).generation == generation, !Self.isCancellation(error) else {
                return .discarded
            }

            if reportsFailure {
                _ = feedBoard.fail(
                    on: tab,
                    generation: generation,
                    replacing: replacing,
                    message: "Couldn't load Home."
                )
            }
            return .failure
        }
    }

    /// Why a page fetch ended. `discarded` means it was cancelled or
    /// superseded, so it must not report an outcome either way.
    enum PageFetchResult {
        case success
        case failure
        case discarded
    }

    /// One read-only `GET /feed` page. A refresh fetches two of these and decides what
    /// to do with them before any state moves, so a half-failed pull stays coherent.
    enum FeedPageOutcome {
        case loaded(cards: [StoredCard], hasMore: Bool, serverCursor: String?)
        /// Nothing older to ask for, so the tail was never requested.
        case exhausted
        case failed
        case discarded

        var stored: [StoredCard]? {
            if case let .loaded(cards, _, _) = self {
                return cards
            }
            return nil
        }

        var hasMore: Bool {
            if case let .loaded(_, hasMore, _) = self {
                return hasMore
            }
            return false
        }

        /// Present only when the server pages this feed itself, as a ranked order does.
        var serverCursor: String? {
            if case let .loaded(_, _, cursor) = self {
                return cursor
            }
            return nil
        }

        var didFail: Bool {
            if case .failed = self {
                return true
            }
            return false
        }
    }

    /// Fetches a feed page without touching state, so the refresh planner sees both
    /// halves of a pull before either is applied.
    private func fetchFeedCards(
        on tab: HomeFeedTab,
        limit: Int,
        before: String? = nil,
        after: String? = nil,
        filter: HomeFeedFilter,
        generation: Int
    ) async -> FeedPageOutcome {
        do {
            let response = try await cardsService.listFeed(
                limit: limit,
                before: before,
                after: after,
                categories: filter.categories,
                emotions: filter.emotions,
                style: tab.matchingStyle
            )
            guard !Task.isCancelled, feedBoard.shelf(tab).generation == generation else {
                return .discarded
            }
            return .loaded(
                cards: response.cards,
                hasMore: response.page.hasMore(pageSize: limit),
                serverCursor: response.page.serverCursor
            )
        } catch {
            guard !Task.isCancelled, feedBoard.shelf(tab).generation == generation, !Self.isCancellation(error) else {
                return .discarded
            }
            return .failed
        }
    }

    private func mergeFeed(_ stored: [StoredCard]) -> [HomeCard] {
        merged(Array(feedBoard.records.values), with: stored)
    }

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
            if !item.isOwner,
               let authorId = UUID(uuidString: item.author.id),
               blockedPeople.contains(where: { $0.id == authorId }) {
                continue
            }
            if var existing = pool[id] {
                let authorId = existing.authorId
                let keepFollow = authorId.map { followTasks[$0] != nil } ?? false
                let previousFollow = existing.authorFollowing
                let previousSlides = existing.slides
                existing.apply(item)
                if keepFollow, !existing.isOwner {
                    existing.authorFollowing = previousFollow
                }
                // A shelf page must not snap a heart back while that write is still in flight.
                for index in existing.slides.indices {
                    let style = existing.slides[index].result.style
                    guard favoriteTasks[Self.favoriteTaskKey(id: id, style: style)] != nil,
                          let previous = previousSlides.first(where: { $0.result.style == style })
                    else {
                        continue
                    }
                    existing.slides[index].isFavorite = previous.isFavorite
                    existing.slides[index].favoritedAt = previous.favoritedAt
                }
                next.append(existing)
            } else if let created = HomeCard(stored: item) {
                next.append(created)
            }
        }

        return next
    }

    private func isLocallyBlocked(_ card: HomeCard) -> Bool {
        guard !card.isOwner, let authorId = card.authorId else {
            return false
        }
        return blockedPeople.contains { $0.id == authorId }
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

        cancelFeedTasks()
        appliedFilter = HomeFeedFilter()
        // All stays on screen until the unfiltered page arrives. The shelf you are
        // looking at reloads now; the others reload on their next visit.
        feedBoard.invalidate(blank: false)
        startFeedTask(on: homeFeedTab, replacing: true, reportsFailure: true)
        if homeFeedTab != .all {
            startFeedTask(on: .all, replacing: true, reportsFailure: true)
        }
    }

    private func insertFeedCardAtFront(_ card: HomeCard) {
        // Your own fresh post must not come back as an arrival on the next pull.
        feedBoard.insertPublishedAtFront(card)
    }

    /// Newest-first position on every loaded shelf that should show this card.
    private func insertPublicCardIntoLoadedFeed(_ card: HomeCard) {
        guard card.isPublic, feedBoard.shelf(.all).hasLoaded, matchesFeedFilter(card, appliedFilter) else {
            return
        }
        feedBoard.insertPublishedInOrder(card)
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
        feedBoard.remove(id)
    }

    /// True when `card` belongs above `other` in the newest-first feed.
    private func feedSortIsBefore(_ card: HomeCard, _ other: HomeCard) -> Bool {
        FeedOrder.isBefore(card, other)
    }

    private func ownerCard(id: UUID) -> HomeCard? {
        if let match = cards.first(where: { $0.id == id }), match.isOwner {
            return match
        }
        if let match = feedBoard.record(id), match.isOwner {
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
        let placements = feedBoard.placements(of: id)
        let previousAuthorIndexes = authorCardIndexes(id)
        let previousModelIndexes = modelCardIndexes(id)
        if libraryIndex != nil {
            cards.removeAll { $0.id == id }
        }
        removeFromFeed(id)
        removeFromAuthorFeeds(id)
        removeFromModelFeeds(id)

        deleteTasks[id]?.cancel()
        let generation = (deleteGeneration[id] ?? 0) + 1
        deleteGeneration[id] = generation
        let sessionGeneration = writeSessionGeneration
        deleteTasks[id] = Task { @MainActor in
            defer {
                if deleteGeneration[id] == generation,
                   writeSessionGeneration == sessionGeneration {
                    deleteTasks[id] = nil
                }
            }
            do {
                try await cardsService.delete(id: id.uuidString.lowercased())
            } catch {
                guard !Task.isCancelled,
                      deleteGeneration[id] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                if let libraryIndex, !cards.contains(where: { $0.id == id }) {
                    cards.insert(snapshot, at: min(libraryIndex, cards.count))
                }
                for placement in placements where feedBoard.record(id) == nil || !feedBoard.placements(of: id).contains(placement) {
                    feedBoard.restore(snapshot, at: placement)
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
        let generation = (boardGeneration[id] ?? 0) + 1
        boardGeneration[id] = generation
        let sessionGeneration = writeSessionGeneration
        boardTasks[id] = Task { @MainActor in
            defer {
                if boardGeneration[id] == generation,
                   writeSessionGeneration == sessionGeneration {
                    boardTasks[id] = nil
                }
            }
            do {
                try await cardsService.removeFromBoard(id: id.uuidString.lowercased())
                guard !Task.isCancelled,
                      boardGeneration[id] == generation,
                      writeSessionGeneration == sessionGeneration else {
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
                guard !Task.isCancelled,
                      boardGeneration[id] == generation,
                      writeSessionGeneration == sessionGeneration else {
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
        if case APIError.httpStatus(404, _, _) = error {
            return true
        }
        return false
    }

    private static func publicModerationMessage(for error: Error) -> String? {
        guard let apiError = error as? APIError else {
            return nil
        }
        switch apiError.serverCode {
        case "PUBLIC_CONTENT_NOT_ALLOWED":
            return "This card can't be posted publicly. Save it privately instead."
        case "PUBLIC_MODERATION_UNAVAILABLE":
            return "Posting is temporarily unavailable. Save privately or try again."
        default:
            return nil
        }
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

    private func blockAuthorSnapshot(_ authorId: UUID) -> BlockAuthorSnapshot {
        let libraryEntries = cards.enumerated().compactMap { index, card in
            card.authorId == authorId && !card.isOwner
                ? (index: index, card: card)
                : nil
        }
        let shelfEntries = feedBoard.placements { card in
            card.authorId == authorId && !card.isOwner
        }
        let affectedIDs = Set(libraryEntries.map(\.card.id) + shelfEntries.map(\.card.id))
        let anchors = feedBoard.anchors.filter { affectedIDs.contains($0.key) }
        let followedEntry = followedPeople.firstIndex(where: { $0.id == authorId }).map {
            (index: $0, person: followedPeople[$0])
        }
        let blockedEntry = blockedPeople.firstIndex(where: { $0.id == authorId }).map {
            (index: $0, person: blockedPeople[$0])
        }
        let affectedAuthorFeeds = authorFeeds.filter { id, feed in
            id == authorId || feed.cards.contains { $0.authorId == authorId && !$0.isOwner }
        }
        let affectedModelFeeds = modelFeeds.filter { _, feed in
            feed.cards.contains { $0.authorId == authorId && !$0.isOwner }
        }

        return BlockAuthorSnapshot(
            libraryEntries: libraryEntries,
            shelfEntries: shelfEntries,
            feedAnchors: anchors,
            followedEntry: followedEntry,
            blockedEntry: blockedEntry,
            authorFeeds: affectedAuthorFeeds,
            modelFeeds: affectedModelFeeds
        )
    }

    private func restoreBlockedAuthor(_ snapshot: BlockAuthorSnapshot, authorId: UUID) {
        for entry in snapshot.libraryEntries.sorted(by: { $0.index < $1.index })
        where !cards.contains(where: { $0.id == entry.card.id }) {
            cards.insert(entry.card, at: min(entry.index, cards.count))
        }
        for entry in snapshot.shelfEntries.sorted(by: { $0.placement.index < $1.placement.index }) {
            feedBoard.restore(entry.card, at: entry.placement)
        }
        for (_, anchor) in snapshot.feedAnchors {
            feedBoard.restoreAnchor(anchor)
        }
        if let entry = snapshot.followedEntry,
           !followedPeople.contains(where: { $0.id == authorId }) {
            followedPeople.insert(entry.person, at: min(entry.index, followedPeople.count))
        }
        blockedPeople.removeAll { $0.id == authorId }
        if let entry = snapshot.blockedEntry {
            blockedPeople.insert(entry.person, at: min(entry.index, blockedPeople.count))
        }

        for (id, var feed) in snapshot.authorFeeds {
            feed.task = nil
            if feed.footerState == .loading {
                feed.footerState = .idle
            }
            feed.isRefreshing = false
            authorFeeds[id] = feed
        }
        for (model, var feed) in snapshot.modelFeeds {
            feed.task = nil
            if feed.footerState == .loading {
                feed.footerState = .idle
            }
            feed.isRefreshing = false
            modelFeeds[model] = feed
        }
    }

    private func removeAuthorLocally(_ authorId: UUID) {
        cards.removeAll { $0.authorId == authorId && !$0.isOwner }
        feedBoard.remove { $0.authorId == authorId && !$0.isOwner }
        followedPeople.removeAll { $0.id == authorId }

        for id in Array(authorFeeds.keys)
        where id == authorId
            || authorFeeds[id]?.cards.contains(where: { $0.authorId == authorId && !$0.isOwner }) == true {
            mutateAuthor(id) { feed in
                feed.task?.cancel()
                feed.task = nil
                feed.generation &+= 1
                feed.cards.removeAll { $0.authorId == authorId && !$0.isOwner }
                feed.cardIDs = Set(feed.cards.map(\.id))
                feed.footerState = .idle
                feed.isRefreshing = false
                if id == authorId {
                    feed.following = false
                    feed.hasMore = false
                    feed.before = nil
                    feed.hasLoaded = true
                    feed.loadState = .loaded
                }
            }
        }
        for model in Array(modelFeeds.keys)
        where modelFeeds[model]?.cards.contains(where: { $0.authorId == authorId && !$0.isOwner }) == true {
            mutateModel(model) { feed in
                feed.task?.cancel()
                feed.task = nil
                feed.generation &+= 1
                feed.cards.removeAll { $0.authorId == authorId && !$0.isOwner }
                feed.cardIDs = Set(feed.cards.map(\.id))
                feed.footerState = .idle
                feed.isRefreshing = false
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
        let previousTask = favoriteTasks[key]
        let generation = (favoriteGeneration[key] ?? 0) + 1
        favoriteGeneration[key] = generation
        let sessionGeneration = writeSessionGeneration
        favoriteTasks[key] = Task { @MainActor in
            // Preserve request order. Cancelling an in-flight URL request cannot prove the
            // server did not commit it, so a later tap waits for its response before writing.
            await previousTask?.value
            guard !Task.isCancelled,
                  favoriteGeneration[key] == generation,
                  writeSessionGeneration == sessionGeneration else {
                return
            }
            defer {
                if favoriteGeneration[key] == generation,
                   writeSessionGeneration == sessionGeneration {
                    favoriteTasks[key] = nil
                }
            }
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
                guard !Task.isCancelled,
                      favoriteGeneration[key] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                applyStored(stored)
            } catch {
                guard !Task.isCancelled,
                      favoriteGeneration[key] == generation,
                      writeSessionGeneration == sessionGeneration else {
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

    func loadBlocks() async {
        blocksGeneration &+= 1
        let generation = blocksGeneration
        if blockedPeople.isEmpty {
            blocksLoadState = .loading
        }
        do {
            let response = try await profileService.blocks()
            guard !Task.isCancelled, generation == blocksGeneration else {
                return
            }
            blockedPeople = response.users.compactMap(BlockedPerson.init)
            blocksLoadState = .loaded
        } catch {
            guard generation == blocksGeneration, !Self.isCancellation(error) else {
                return
            }
            if blockedPeople.isEmpty {
                blocksLoadState = .failed("Couldn't load blocked people.")
            }
        }
    }

    func reportCard(_ id: UUID, reason: ReportReason) {
        guard reportTasks[id] == nil,
              let target = card(id: id),
              !target.isOwner
        else {
            return
        }

        let libraryIndex = cards.firstIndex { $0.id == id }
        let placements = feedBoard.placements(of: id)
        let previousAuthorIndexes = authorCardIndexes(id)
        let previousModelIndexes = modelCardIndexes(id)
        let feedAnchor = feedBoard.anchors[id]
        dropUnavailableCard(id)
        let generation = (reportGeneration[id] ?? 0) + 1
        reportGeneration[id] = generation
        let sessionGeneration = writeSessionGeneration
        reportTasks[id] = Task { @MainActor in
            defer {
                if reportGeneration[id] == generation,
                   writeSessionGeneration == sessionGeneration {
                    reportTasks[id] = nil
                }
            }
            do {
                let state = try await cardsService.report(
                    id: id.uuidString.lowercased(),
                    reason: reason
                )
                guard !Task.isCancelled,
                      reportGeneration[id] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                guard state.reported else {
                    throw APIError.decoding("The report was not accepted.")
                }
            } catch {
                guard !Task.isCancelled,
                      reportGeneration[id] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                if let libraryIndex, !cards.contains(where: { $0.id == id }) {
                    cards.insert(target, at: min(libraryIndex, cards.count))
                }
                for placement in placements {
                    feedBoard.restore(target, at: placement)
                }
                if let feedAnchor {
                    feedBoard.restoreAnchor(feedAnchor)
                }
                restoreAuthorCards(target, at: previousAuthorIndexes)
                restoreModelCards(target, at: previousModelIndexes)
                reportWriteFailure(error, "Couldn't report that card. Check your connection.")
            }
        }
    }

    func blockAuthor(
        _ authorId: UUID,
        initials: String,
        avatarPath: String?
    ) {
        guard !isOwnAuthor(authorId), blockTasks[authorId] == nil else {
            return
        }

        let snapshot = blockAuthorSnapshot(authorId)
        let person = BlockedPerson(id: authorId, initials: initials, avatarPath: avatarPath)
        removeAuthorLocally(authorId)
        if !blockedPeople.contains(where: { $0.id == authorId }) {
            blockedPeople.insert(person, at: 0)
        }

        followTasks[authorId]?.cancel()
        followTasks[authorId] = nil
        followGeneration[authorId, default: 0] &+= 1

        blocksGeneration &+= 1
        let generation = (blockGeneration[authorId] ?? 0) + 1
        blockGeneration[authorId] = generation
        let sessionGeneration = writeSessionGeneration
        blockTasks[authorId] = Task { @MainActor in
            defer {
                if blockGeneration[authorId] == generation,
                   writeSessionGeneration == sessionGeneration {
                    blockTasks[authorId] = nil
                }
            }
            do {
                let state = try await profileService.block(id: authorId.uuidString.lowercased())
                guard !Task.isCancelled,
                      blockGeneration[authorId] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                guard state.blocked else {
                    throw APIError.decoding("The block was not accepted.")
                }
                if !blockedPeople.contains(where: { $0.id == authorId }) {
                    blockedPeople.insert(person, at: 0)
                }
                blocksGeneration &+= 1
            } catch {
                guard !Task.isCancelled,
                      blockGeneration[authorId] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                restoreBlockedAuthor(snapshot, authorId: authorId)
                reportWriteFailure(error, "Couldn't block that person. Check your connection.")
            }
        }
    }

    func unblock(_ person: BlockedPerson) {
        guard blockTasks[person.id] == nil else {
            return
        }
        let index = blockedPeople.firstIndex(where: { $0.id == person.id }) ?? 0
        blockedPeople.removeAll { $0.id == person.id }

        blocksGeneration &+= 1
        let generation = (blockGeneration[person.id] ?? 0) + 1
        blockGeneration[person.id] = generation
        let sessionGeneration = writeSessionGeneration
        blockTasks[person.id] = Task { @MainActor in
            defer {
                if blockGeneration[person.id] == generation,
                   writeSessionGeneration == sessionGeneration {
                    blockTasks[person.id] = nil
                }
            }
            do {
                let state = try await profileService.unblock(id: person.id.uuidString.lowercased())
                guard !Task.isCancelled,
                      blockGeneration[person.id] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                guard !state.blocked else {
                    throw APIError.decoding("The unblock was not accepted.")
                }
                blockedPeople.removeAll { $0.id == person.id }
                blocksGeneration &+= 1
            } catch {
                guard !Task.isCancelled,
                      blockGeneration[person.id] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                if !blockedPeople.contains(where: { $0.id == person.id }) {
                    blockedPeople.insert(person, at: min(index, blockedPeople.count))
                }
                reportWriteFailure(error, "Couldn't unblock that person. Check your connection.")
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
        let sessionGeneration = writeSessionGeneration
        followTasks[authorId]?.cancel()
        followTasks[authorId] = Task { @MainActor in
            defer {
                if self.followGeneration[authorId] == generation,
                   self.writeSessionGeneration == sessionGeneration {
                    self.followTasks[authorId] = nil
                }
            }
            do {
                let state =
                    next
                    ? try await cardsService.follow(id: authorId.uuidString.lowercased())
                    : try await cardsService.unfollow(id: authorId.uuidString.lowercased())
                guard !Task.isCancelled,
                      self.followGeneration[authorId] == generation,
                      self.writeSessionGeneration == sessionGeneration else {
                    return
                }
                setFollowing(authorId, following: state.following)
            } catch {
                guard !Task.isCancelled,
                      self.followGeneration[authorId] == generation,
                      self.writeSessionGeneration == sessionGeneration else {
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
        let previousPlacements = feedBoard.placements(of: id)
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

        let previousTask = publicTasks[id]
        let generation = (publicGeneration[id] ?? 0) + 1
        publicGeneration[id] = generation
        let sessionGeneration = writeSessionGeneration
        publicTasks[id] = Task { @MainActor in
            // Serialize privacy writes for this card. A cancelled transport can still commit,
            // so overlapping PATCH requests could otherwise leave the server in tap-old order.
            await previousTask?.value
            guard !Task.isCancelled,
                  publicGeneration[id] == generation,
                  writeSessionGeneration == sessionGeneration else {
                return
            }
            defer {
                if publicGeneration[id] == generation,
                   writeSessionGeneration == sessionGeneration {
                    publicTasks[id] = nil
                }
            }
            do {
                let stored = try await cardsService.patch(
                    id: id.uuidString.lowercased(),
                    PatchCardRequest(isPublic: isPublic)
                )
                guard !Task.isCancelled,
                      publicGeneration[id] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                if let current = cards.firstIndex(where: { $0.id == id }) {
                    cards[current].apply(stored)
                }
                _ = feedBoard.update(id) { card in
                    card.apply(stored)
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
                guard !Task.isCancelled,
                      publicGeneration[id] == generation,
                      writeSessionGeneration == sessionGeneration else {
                    return
                }
                applyLocal(id: id) { card in
                    card.isPublic = previousPublic
                }
                if previousPlacements.isEmpty {
                    removeFromFeed(id)
                } else {
                    var restored = snapshot
                    restored.isPublic = previousPublic
                    for placement in previousPlacements {
                        feedBoard.restore(restored, at: placement)
                    }
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
                reportWriteFailure(
                    error,
                    Self.publicModerationMessage(for: error)
                        ?? "Couldn't change who can see this. Check your connection."
                )
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

    func dismissUsageBanner() {
        usageBannerTask?.cancel()
        usageBannerTask = nil
        usageBanner = nil
    }

    private func showUsageBanner(_ message: String) {
        usageBanner = message
        usageBannerTask?.cancel()
        usageBannerTask = Task { @MainActor in
            defer { usageBannerTask = nil }
            try? await Task.sleep(for: Self.writeErrorDuration)
            guard !Task.isCancelled else {
                return
            }
            usageBanner = nil
        }
    }

    private func applyUsage(
        _ summary: UsageSummary,
        requestModel: LlmModel? = nil,
        creditsUsed: Int = 0
    ) {
        hasLoadedUsage = true
        usageSummary = summary

        let previousModel = selectedModel
        var switchMessage: String?
        if !summary.allowedModels.contains(previousModel.rawValue),
           let fallback = [LlmModel.mistral, .deepseek, .gemini].first(where: {
               summary.allowedModels.contains($0.rawValue)
           }) {
            selectedModel = fallback
            switchMessage = "\(previousModel.displayName) is paused. Switched to \(fallback.displayName) until your credits reset."
        }

        if creditsUsed > 0, let requestModel {
            usageFeedback = "\(creditsUsed) \(creditsUsed == 1 ? "credit" : "credits") used · \(requestModel.displayName)"
        }

        if let switchMessage {
            showUsageBanner(switchMessage)
        } else {
            showLowCreditWarningIfNeeded(summary)
        }
    }

    private func applyUsage(_ usage: ReframeUsage, requestModel: LlmModel) {
        var costs = usageSummary?.creditCost
            ?? Dictionary(uniqueKeysWithValues: LlmModel.allCases.map { ($0.rawValue, $0.creditCost) })
        costs[requestModel.rawValue] = usage.creditCost
        let previous = usageSummary
        applyUsage(
            UsageSummary(
                creditsGranted: usage.granted,
                creditsRemaining: usage.remaining,
                periodStart: previous?.periodStart,
                periodEnd: previous?.periodEnd,
                resetsAt: usage.resetsAt,
                warning: usage.warning,
                allowedModels: usage.allowedModels,
                creditCost: costs
            ),
            requestModel: requestModel,
            creditsUsed: usage.creditsUsed
        )
    }

    private func applyUsage(from payload: APIErrorPayload) {
        guard let creditsRemaining = payload.creditsRemaining,
              let creditsGranted = payload.creditsGranted,
              let allowedModels = payload.allowedModels else {
            return
        }
        let previous = usageSummary
        applyUsage(
            UsageSummary(
                creditsGranted: creditsGranted,
                creditsRemaining: creditsRemaining,
                periodStart: previous?.periodStart,
                periodEnd: previous?.periodEnd,
                resetsAt: payload.resetsAt,
                warning: Self.usageWarning(remaining: creditsRemaining),
                allowedModels: allowedModels,
                creditCost: previous?.creditCost
                    ?? Dictionary(
                        uniqueKeysWithValues: LlmModel.allCases.map { ($0.rawValue, $0.creditCost) }
                    )
            )
        )
    }

    private func showLowCreditWarningIfNeeded(_ summary: UsageSummary) {
        guard summary.warning == .low, let usageAccountID else {
            return
        }
        let period = summary.periodStart ?? summary.resetsAt ?? "granted-\(summary.creditsGranted)"
        let key = Self.lowWarningDefaultsKey(userID: usageAccountID)
        guard UserDefaults.standard.string(forKey: key) != period else {
            return
        }
        UserDefaults.standard.set(period, forKey: key)
        showUsageBanner("Credits are getting low")
    }

    static func lowWarningDefaultsKey(userID: String) -> String {
        "\(lowWarningPeriodKeyPrefix).\(userID.lowercased())"
    }

    private static func usageWarning(remaining: Int) -> UsageWarning {
        if remaining <= 0 {
            return .empty
        }
        if remaining <= 60 {
            return .critical
        }
        if remaining <= 120 {
            return .low
        }
        return .normal
    }

    private func composeFailure(
        for error: Error,
        model: LlmModel
    ) -> (message: String, allowsRetry: Bool) {
        guard case APIError.httpStatus(_, let payload?, _) = error else {
            return ("Couldn't generate a reframe. Try again.", true)
        }
        applyUsage(from: payload)
        let reset = payload.resetsAt
            .flatMap(ISO8601Dates.date(from:))
            .map { " until \($0.formatted(date: .abbreviated, time: .omitted))" }
            ?? ""

        switch payload.code {
        case "SUBSCRIPTION_REQUIRED":
            return ("Membership is required. Open Profile → Settings → Subscription.", false)
        case "INSUFFICIENT_CREDITS":
            return ("Not enough credits for \(model.displayName). Choose an available model or wait\(reset).", true)
        case "MODEL_NOT_AVAILABLE":
            return ("\(model.displayName) isn't available right now. Choose another model.", true)
        case "TASTE_RECOOK_UNAVAILABLE":
            return ("New answers aren't available during your free taste.", false)
        case "TASTE_LIMIT_REACHED":
            return ("Your free taste is finished. View membership to keep cooking.", false)
        case "DAILY_OPERATION_LIMIT":
            return ("You've reached today's cooking limit. Try again tomorrow.", true)
        case "OPERATION_RATE_LIMIT":
            return ("You're cooking too quickly. Wait a moment and try again.", true)
        case "PROVIDER_CALL_LIMIT":
            return ("Today's AI call limit is reached. Try again tomorrow.", true)
        case "IDEMPOTENCY_KEY_REQUIRED", "INVALID_IDEMPOTENCY_KEY":
            return ("This request couldn't be started safely. Try again.", true)
        case "IDEMPOTENCY_CONFLICT":
            return ("This request changed before it completed. Send it again.", true)
        case "OPERATION_RUNNING":
            return ("This request is still running. Wait a moment before trying again.", true)
        case "REQUEST_ALREADY_COMPLETED":
            return ("That request already finished, but its result can't be recovered. Start a new thought.", false)
        case "OPERATION_EXPIRED":
            return ("That request expired before it finished. Try again.", true)
        default:
            return ("Couldn't generate a reframe. Try again.", true)
        }
    }

    private static func favoriteTaskKey(id: UUID, style: Style) -> String {
        "\(id.uuidString)-\(style.rawValue)"
    }

    private func card(id: UUID) -> HomeCard? {
        if let match = feedBoard.record(id) {
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
        _ = feedBoard.update(id, body)
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
        if feedBoard.record(card.id) != nil {
            feedBoard.remember(card)
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
              isModelAvailable(cook.model),
              cook.results.contains(where: { $0.style == style })
        else {
            return
        }

        recookingStyle = style
        recookNotice = nil
        usageFeedback = nil
        // Recook works from the cleaned English thought, not the raw paste.
        let text = cook.thought
        let model = cook.model
        let requestID: UUID
        if pendingRecookStyle == style, let pendingRecookRequestID {
            requestID = pendingRecookRequestID
        } else {
            requestID = UUID()
            pendingRecookRequestID = requestID
            pendingRecookStyle = style
        }

        refineTask?.cancel()
        refineGeneration &+= 1
        let generation = refineGeneration
        refineTask = Task { @MainActor in
            defer {
                if refineGeneration == generation, recookingStyle == style {
                    recookingStyle = nil
                    refineTask = nil
                }
            }

            do {
                let response = try await reframeService.refine(
                    text: text,
                    styles: [style],
                    model: model,
                    requestID: requestID
                )
                guard !Task.isCancelled, refineGeneration == generation else {
                    return
                }
                pendingRecookRequestID = nil
                pendingRecookStyle = nil

                switch response {
                case .continueTurn(let message, _, _, let usage):
                    applyUsage(usage, requestModel: model)
                    // That style no longer fits this thought; keep what we have.
                    recookNotice = message
                case .ready(_, _, let incoming, _, _, let usage):
                    applyUsage(usage, requestModel: model)
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
                guard !Task.isCancelled,
                      refineGeneration == generation,
                      !Self.isCancellation(error) else {
                    return
                }
                if !Self.isAmbiguousReframeFailure(error) {
                    pendingRecookRequestID = nil
                    pendingRecookStyle = nil
                }
                recookNotice = composeFailure(for: error, model: model).message
            }
        }
    }

    func resetCompose() {
        refineGeneration &+= 1
        refineTask?.cancel()
        refineTask = nil
        saveTask?.cancel()
        saveTask = nil
        composeText = ""
        statement = ""
        turns = []
        recookingStyle = nil
        recookNotice = nil
        pendingRefineRequestID = nil
        pendingRecookRequestID = nil
        pendingRecookStyle = nil
        usageFeedback = nil
        composeErrorAllowsRetry = true
        saveError = nil
        isSaving = false
        composeIsPublic = true
        phase = .composing
    }

    private func startRefine(requestID: UUID) {
        refineTask?.cancel()
        refineGeneration &+= 1
        let generation = refineGeneration
        recookingStyle = nil
        recookNotice = nil
        pendingRecookRequestID = nil
        pendingRecookStyle = nil
        usageFeedback = nil
        composeErrorAllowsRetry = true
        phase = .cooking
        let text = statement
        let followUps = answeredFollowUps
        let model = selectedModel

        refineTask = Task { @MainActor in
            do {
                let response = try await reframeService.refine(
                    text: text,
                    followUps: followUps,
                    model: model,
                    requestID: requestID
                )
                guard !Task.isCancelled, refineGeneration == generation else {
                    return
                }
                pendingRefineRequestID = nil

                switch response {
                case .continueTurn(let message, let options, let safety, let usage):
                    applyUsage(usage, requestModel: model)
                    turns.append(
                        RefineTurn(
                            id: UUID(),
                            message: message,
                            options: options,
                            safety: safety
                        )
                    )
                    phase = .awaitingReply
                case .ready(
                    let thought,
                    let thoughtOriginal,
                    let results,
                    let meta,
                    let signature,
                    let usage
                ):
                    applyUsage(usage, requestModel: model)
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
                guard !Task.isCancelled,
                      refineGeneration == generation,
                      !Self.isCancellation(error) else {
                    return
                }

                if !Self.isAmbiguousReframeFailure(error) {
                    pendingRefineRequestID = nil
                }
                let failure = composeFailure(for: error, model: model)
                composeErrorAllowsRetry = failure.allowsRetry
                phase = .error(failure.message)
            }
            if refineGeneration == generation {
                refineTask = nil
            }
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
                            guard !isLocallyBlocked(card) else {
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
                if case APIError.httpStatus(let status, _, _) = error, status == 404 {
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
        if feedBoard.records.values.contains(where: { $0.authorId == authorId && $0.isOwner }) {
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
        if let card = feedBoard.records.values.first(where: { $0.authorId == authorId && !$0.isOwner }) {
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
        feedBoard.updateAuthor(authorId, following: following)
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
                            guard !isLocallyBlocked(card) else {
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

    /// A request may have reached the server when transport failed or a successful body could
    /// not be decoded. Replaying the same key is the only retry that cannot spend twice.
    private static func isAmbiguousReframeFailure(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else {
            return false
        }
        switch apiError {
        case .network, .decoding:
            return true
        case .invalidURL, .httpStatus:
            return false
        }
    }
}
