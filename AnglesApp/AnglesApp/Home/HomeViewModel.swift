import Foundation
import Observation
import SwiftUI
import UIKit

enum LibraryLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}

enum ListFooterState: Equatable {
    case idle
    case loading
    case failed
}

enum PostFetchResult: Equatable {
    case loaded(HomeCard)
    case notFound
    case failed
    case cancelled
}

/// Profile's two lists: the cards you wrote and the cards you loved.
enum ProfileSegment: String, CaseIterable, Hashable {
    case yours
    case saved

    var title: String {
        switch self {
        case .yours: "Yours"
        case .saved: "Loved"
        }
    }

    var symbol: String {
        switch self {
        case .yours: "square.stack"
        case .saved: "heart"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .yours: "square.stack.fill"
        case .saved: "heart.fill"
        }
    }

    /// `GET /cards?saved=`.
    var savedQuery: Bool {
        self == .saved
    }
}

/// One paged list of cards: a Profile segment or an author page.
struct CardList: Equatable {
    var cards: [HomeCard] = []
    var loadState: LibraryLoadState = .loading
    var footerState: ListFooterState = .idle
    var before: String?
    var hasMore = false
    var hasLoaded = false
    var generation = 0
}

/// The toast over the action row: "Posted" or "Saved privately" after a post, and once per
/// account the first Love, which tells the author who loved it.
struct PostToast: Equatable {
    let label: String
    var detail: String? = nil
    let symbol: String
    let tint: Style
    let token: Int
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
    var list = CardList()
    var task: Task<Void, Never>?
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var yours = CardList()
    private(set) var saved = CardList() {
        didSet {
            SavedAngleWidgetPublisher.publish(cards: saved.cards)
        }
    }
    var profileSegment: ProfileSegment = .yours

    private(set) var usageSummary: UsageSummary?
    private(set) var usageBanner: String?
    /// The server refused a cook because this account's free taste is spent. AppRoot moves a
    /// taste destination to the paywall so the composer is never a dead end.
    private(set) var tasteEndedByServer = false

    private(set) var postToast: PostToast?
    /// Bumped after a save or a post so the Profile button pulses once.
    private(set) var profilePulseToken = 0

    /// A save, privacy flag, or delete that did not reach the server. The rollback is
    /// invisible on its own, so the root banner reads this.
    private(set) var writeError: String?
    private(set) var followedPeople: [FollowedPerson] = []
    private(set) var followingLoadState: LibraryLoadState = .loading
    private(set) var blockedPeople: [BlockedPerson] = []
    private(set) var blocksLoadState: LibraryLoadState = .loading
    private(set) var followNotices: [FollowNotice] = []
    /// Loves on the viewer's own posts, newest first. Loaded and read with the follows.
    private(set) var loveNotices: [LoveNotice] = []
    private(set) var followNoticesLoadState: LibraryLoadState = .loading
    /// Unread follows and loves together: the bell dot and the app icon badge.
    private(set) var unreadNotificationCount = 0
    /// Bumped whenever the unread count is set, even to the same value, so the app icon is
    /// rewritten after a push changed it behind the app's back.
    private(set) var followBadgeRevision = 0
    /// Whose loves these are and whether they carry the name. AppRoot keeps it in step
    /// with the session.
    @ObservationIgnored var loveDisclosure: (accountId: String?, sharesName: Bool) = (nil, true)

    let compose: ComposeSession
    let stack: StackModel

    @ObservationIgnored private let cardsService: CardsService
    @ObservationIgnored private let profileService: ProfileService
    @ObservationIgnored private let writer: DecisionWriter
    @ObservationIgnored private var listTasks: [ProfileSegment: Task<Void, Never>] = [:]
    @ObservationIgnored private var followTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var followGeneration: [UUID: Int] = [:]
    @ObservationIgnored private var publicTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var publicGeneration: [UUID: Int] = [:]
    @ObservationIgnored private var deleteTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var reportTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var blockTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var blockGeneration: [UUID: Int] = [:]
    @ObservationIgnored private var blocksGeneration = 0
    @ObservationIgnored private var writeSessionGeneration = 0
    @ObservationIgnored private var authorFeeds: [UUID: AuthorFeed] = [:]
    @ObservationIgnored private var authorFeedOrder: [UUID] = []
    /// Author pages are observed through this, so a page redraws when its feed changes.
    private var authorRevision = 0
    @ObservationIgnored private var followNoticesGeneration = 0
    @ObservationIgnored private var followLoadTask: Task<Void, Never>?
    @ObservationIgnored private var followLoadTaskGeneration = -1
    @ObservationIgnored private var followReadTask: Task<Void, Never>?
    @ObservationIgnored private var writeErrorTask: Task<Void, Never>?
    @ObservationIgnored private var usageBannerTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var isLoadingUsage = false
    @ObservationIgnored private var hasLoadedUsage = false
    @ObservationIgnored private var usageAccountID: String?
    @ObservationIgnored private var usageGeneration = 0

    private static let lowWarningPeriodKeyPrefix = "angles.lowCreditWarningPeriod"
    private static let writeErrorDuration: Duration = .seconds(3)
    private static let toastDuration: Duration = .milliseconds(2600)
    static let listPageSize = 50
    static let authorPageSize = 24

    init(
        reframeService: ReframeService = ReframeService(),
        cardsService: CardsService = CardsService(),
        profileService: ProfileService = ProfileService()
    ) {
        let writer = DecisionWriter(cardsService: cardsService)
        self.compose = ComposeSession(reframeService: reframeService, cardsService: cardsService)
        self.cardsService = cardsService
        self.profileService = profileService
        self.writer = writer
        self.stack = StackModel(cardsService: cardsService, writer: writer)
        UserDefaults.standard.removeObject(forKey: "angles.llmModel")
        compose.host = self
        stack.host = self
    }

    // MARK: - Usage

    /// False only once the server says the balance cannot pay for one more cook.
    /// Local development may run against a backend without `/profile/usage`.
    var hasCreditsForCook: Bool {
        guard let usageSummary else {
            return true
        }
        return usageSummary.creditsRemaining >= usageSummary.creditCost
    }

    /// The free taste is welcomed on the compose screen itself, never counted as a balance.
    var usageStatus: String? {
        guard let usageSummary, usageSummary.plan == .membership else {
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

    /// One account-scoped summary is shared by Home, Profile, and compose.
    func configureUsageAccount(userID: String?) {
        guard usageAccountID != userID else {
            return
        }
        usageGeneration &+= 1
        usageAccountID = userID
        usageSummary = nil
        compose.clearUsageFeedback()
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

    private func applyUsage(_ summary: UsageSummary) {
        hasLoadedUsage = true
        usageSummary = summary
        showLowCreditWarningIfNeeded(summary)
    }

    func applyCookUsage(_ usage: ReframeUsage) {
        let previous = usageSummary
        applyUsage(
            UsageSummary(
                creditsGranted: usage.granted,
                creditsRemaining: usage.remaining,
                periodStart: previous?.periodStart,
                periodEnd: previous?.periodEnd,
                resetsAt: usage.resetsAt,
                warning: usage.warning,
                creditCost: usage.creditCost,
                plan: usage.plan
            )
        )
    }

    func applyUsage(from payload: APIErrorPayload) {
        guard let creditsRemaining = payload.creditsRemaining,
              let creditsGranted = payload.creditsGranted else {
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
                warning: Self.usageWarning(remaining: creditsRemaining, granted: creditsGranted),
                creditCost: previous?.creditCost ?? 1,
                plan: previous?.plan ?? .membership
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

    private static func usageWarning(remaining: Int, granted: Int) -> UsageWarning {
        if remaining <= 0 {
            return .empty
        }
        let base = max(granted, 1)
        if remaining <= base / 10 {
            return .critical
        }
        if remaining <= base / 5 {
            return .low
        }
        return .normal
    }

    // MARK: - Profile lists

    func list(_ segment: ProfileSegment) -> CardList {
        segment == .yours ? yours : saved
    }

    private func mutateList(_ segment: ProfileSegment, _ body: (inout CardList) -> Void) {
        switch segment {
        case .yours:
            body(&yours)
        case .saved:
            body(&saved)
        }
    }

    func applyOwnerIdentity(initials: String, avatarPath: String?) {
        for index in yours.cards.indices {
            yours.cards[index].authorInitials = initials
            yours.cards[index].authorAvatarPath = avatarPath
        }
        for authorId in Array(authorFeeds.keys) {
            mutateAuthor(authorId) { feed in
                if feed.isSelf {
                    feed.initials = initials
                    feed.avatarPath = avatarPath
                }
                for index in feed.list.cards.indices where feed.list.cards[index].isOwner {
                    feed.list.cards[index].authorInitials = initials
                    feed.list.cards[index].authorAvatarPath = avatarPath
                }
            }
        }
    }

    func loadLibraryIfNeeded() async {
        async let own: Void = loadListIfNeeded(.yours)
        async let kept: Void = loadListIfNeeded(.saved)
        _ = await (own, kept)
    }

    func loadListIfNeeded(_ segment: ProfileSegment) async {
        guard !list(segment).hasLoaded, listTasks[segment] == nil else {
            return
        }
        startListTask(segment, replacing: true)
        await listTasks[segment]?.value
    }

    func retryList(_ segment: ProfileSegment) {
        listTasks[segment]?.cancel()
        listTasks[segment] = nil
        mutateList(segment) { list in
            list.generation &+= 1
            if list.cards.isEmpty {
                list.loadState = .loading
            }
        }
        startListTask(segment, replacing: true)
    }

    func refreshList(_ segment: ProfileSegment) async {
        listTasks[segment]?.cancel()
        listTasks[segment] = nil
        mutateList(segment) { list in
            list.generation &+= 1
            if list.footerState == .loading {
                list.footerState = .idle
            }
        }
        startListTask(segment, replacing: true)
        await listTasks[segment]?.value
    }

    func loadMore(_ segment: ProfileSegment) {
        let current = list(segment)
        guard current.hasLoaded, current.hasMore, current.before != nil,
              current.footerState == .idle, listTasks[segment] == nil
        else {
            return
        }
        mutateList(segment) { $0.footerState = .loading }
        startListTask(segment, replacing: false)
    }

    func retryLoadMore(_ segment: ProfileSegment) {
        guard list(segment).footerState == .failed else {
            return
        }
        mutateList(segment) { $0.footerState = .idle }
        loadMore(segment)
    }

    private func startListTask(_ segment: ProfileSegment, replacing: Bool) {
        let generation = list(segment).generation
        let before = replacing ? nil : list(segment).before
        listTasks[segment] = Task { @MainActor in
            defer {
                if list(segment).generation == generation {
                    listTasks[segment] = nil
                }
            }
            do {
                let response = try await cardsService.list(
                    limit: Self.listPageSize,
                    before: before,
                    saved: segment.savedQuery
                )
                guard !Task.isCancelled, list(segment).generation == generation else {
                    return
                }
                let incoming = response.cards
                    .compactMap(HomeCard.init(stored:))
                    .filter { !isLocallyBlocked($0) }
                withoutAnimation {
                    mutateList(segment) { list in
                        list.cards = replacing
                            ? reconciled(incoming, over: list.cards, segment: segment)
                            : appended(incoming, to: list.cards, segment: segment)
                        list.before = response.page.nextCursor ?? (replacing ? nil : list.before)
                        list.hasMore = response.page.hasMore(pageSize: Self.listPageSize)
                        list.footerState = .idle
                        list.loadState = .loaded
                        list.hasLoaded = true
                    }
                }
            } catch {
                guard !Task.isCancelled, list(segment).generation == generation, !Self.isCancellation(error) else {
                    return
                }
                mutateList(segment) { list in
                    if replacing, list.cards.isEmpty {
                        list.loadState = .failed(
                            segment == .yours ? "Couldn't load your cards." : "Couldn't load your loved cards."
                        )
                    } else if !replacing {
                        list.footerState = .failed
                    }
                }
            }
        }
    }

    /// A fresh first page, with this phone's own writes still in flight laid over it: a save
    /// or unsave the server may not have yet, a follow, or a privacy change.
    private func reconciled(_ incoming: [HomeCard], over current: [HomeCard], segment: ProfileSegment) -> [HomeCard] {
        let local = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [HomeCard] = []
        for card in incoming {
            if writer.isPending(card.id), local[card.id] == nil, segment == .saved {
                continue
            }
            result.append(patched(card, local: local[card.id]))
        }
        if segment == .saved {
            let fresh = Set(result.map(\.id))
            let kept = current.filter { writer.isPending($0.id) && !fresh.contains($0.id) }
            result.insert(contentsOf: kept, at: 0)
        }
        return result
    }

    private func appended(_ incoming: [HomeCard], to current: [HomeCard], segment: ProfileSegment) -> [HomeCard] {
        var known = Set(current.map(\.id))
        var result = current
        for card in incoming where known.insert(card.id).inserted {
            if segment == .saved, writer.isPending(card.id) {
                continue
            }
            result.append(patched(card, local: nil))
        }
        return result
    }

    private func patched(_ card: HomeCard, local: HomeCard?) -> HomeCard {
        var card = card
        if let authorId = card.authorId, followTasks[authorId] != nil, let local {
            card.authorFollowing = local.authorFollowing
        }
        if publicTasks[card.id] != nil, let local {
            card.isPublic = local.isPublic
        }
        return card
    }

    // MARK: - Stack and posting

    /// After the save cover slides away: a toast over the action row and a Profile pulse.
    func announcePost(_ cardID: UUID) {
        guard let card = yours.cards.first(where: { $0.id == cardID }) else {
            return
        }
        showToast(
            label: card.isPublic ? "Posted" : "Saved privately",
            symbol: card.isPublic ? "globe" : "lock.fill",
            tint: card.spotlightStyle
        )
        profilePulseToken &+= 1
    }

    private func showToast(label: String, detail: String? = nil, symbol: String, tint: Style, duration: Duration? = nil) {
        let token = (postToast?.token ?? 0) &+ 1
        postToast = PostToast(label: label, detail: detail, symbol: symbol, tint: tint, token: token)
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: duration ?? Self.toastDuration)
            guard !Task.isCancelled, postToast?.token == token else {
                return
            }
            postToast = nil
        }
    }

    /// The first Love on this account says, once, that the author sees who loved it.
    private func discloseLoveIfFirst(_ card: HomeCard) {
        guard !card.isHouse, let account = loveDisclosure.accountId, loveDisclosure.sharesName else {
            return
        }
        let key = "angles.loveNameDisclosed.\(account)"
        guard !UserDefaults.standard.bool(forKey: key) else {
            return
        }
        UserDefaults.standard.set(true, forKey: key)
        showToast(
            label: "Loved. They'll see it was you",
            detail: "Turn this off in Settings",
            symbol: "heart.fill",
            tint: card.decision?.style ?? card.spotlightStyle,
            duration: .milliseconds(4200)
        )
    }

    func dismissPostToast() {
        toastTask?.cancel()
        toastTask = nil
        postToast = nil
    }

    // MARK: - Saving from a list

    /// The heart on a list card. Unloving counts every angle as seen, so the card does not
    /// come back to the stack.
    func toggleSave(_ id: UUID, style: Style) {
        guard let card = card(id: id), card.isDecidable else {
            return
        }
        let previous = card.decision
        let request = card.isSaved
            ? StackDeck.unsaveRequest(for: card)
            : StackDeck.request(kind: .save, card: card, style: style, checked: [style])
        let next = CardDecision(request)
        applyLocal(id: id) { $0.decision = next }
        if request.kind == .save {
            var savedCard = card
            savedCard.decision = next
            insertSaved(savedCard)
            stack.remove { $0.id == id }
            profilePulseToken &+= 1
        } else {
            saved.cards.removeAll { $0.id == id }
        }

        let session = writeSessionGeneration
        writer.enqueue(id, .put(request)) { [weak self] outcome in
            guard let self, writeSessionGeneration == session else {
                return
            }
            switch outcome {
            case .done:
                break
            case .gone:
                dropUnavailableCard(id)
                reportWriteFailure(APIError.httpStatus(404, nil, nil), Self.unavailableCardMessage)
            case .failed(let error):
                applyLocal(id: id) { $0.decision = previous }
                if request.kind == .save {
                    saved.cards.removeAll { $0.id == id }
                } else if var restored = self.card(id: id) {
                    restored.decision = previous
                    insertSaved(restored)
                }
                reportWriteFailure(
                    error,
                    request.kind == .save
                        ? "Couldn't love that card. Check your connection."
                        : "Couldn't remove that card. Check your connection."
                )
            }
        }
    }

    private func insertSaved(_ card: HomeCard) {
        guard card.isSaved else {
            return
        }
        if let index = saved.cards.firstIndex(where: { $0.id == card.id }) {
            saved.cards[index] = card
        } else {
            saved.cards.insert(card, at: 0)
        }
    }

    // MARK: - Owner writes

    func deleteCard(_ id: UUID) {
        guard let snapshot = ownerCard(id: id), deleteTasks[id] == nil else {
            return
        }
        let libraryIndex = yours.cards.firstIndex { $0.id == id }
        let authorIndexes = authorCardIndexes(id)
        yours.cards.removeAll { $0.id == id }
        removeFromAuthorFeeds(id)

        let session = writeSessionGeneration
        deleteTasks[id] = Task { @MainActor in
            defer {
                if writeSessionGeneration == session {
                    deleteTasks[id] = nil
                }
            }
            do {
                try await cardsService.delete(id: id.uuidString.lowercased())
            } catch {
                guard !Task.isCancelled, writeSessionGeneration == session else {
                    return
                }
                if Self.isNotFound(error) {
                    return
                }
                if let libraryIndex, !yours.cards.contains(where: { $0.id == id }) {
                    yours.cards.insert(snapshot, at: min(libraryIndex, yours.cards.count))
                }
                restoreAuthorCards(snapshot, at: authorIndexes)
                reportWriteFailure(error, "Couldn't delete that card. Check your connection.")
            }
        }
    }

    func setPublic(_ id: UUID, isPublic: Bool) {
        guard let snapshot = ownerCard(id: id), snapshot.isPublic != isPublic else {
            return
        }
        let previousPublic = snapshot.isPublic
        let authorIndexes = authorCardIndexes(id)
        applyLocal(id: id) { $0.isPublic = isPublic }
        if !isPublic {
            removeFromAuthorFeeds(id)
        }

        let previousTask = publicTasks[id]
        let generation = (publicGeneration[id] ?? 0) + 1
        publicGeneration[id] = generation
        let session = writeSessionGeneration
        publicTasks[id] = Task { @MainActor in
            // Serialize privacy writes for this card. A cancelled transport can still commit,
            // so overlapping PATCH requests could otherwise leave the server in tap-old order.
            await previousTask?.value
            guard !Task.isCancelled, publicGeneration[id] == generation, writeSessionGeneration == session else {
                return
            }
            defer {
                if publicGeneration[id] == generation, writeSessionGeneration == session {
                    publicTasks[id] = nil
                }
            }
            do {
                let stored = try await cardsService.patch(
                    id: id.uuidString.lowercased(),
                    PatchCardRequest(isPublic: isPublic)
                )
                guard !Task.isCancelled, publicGeneration[id] == generation, writeSessionGeneration == session else {
                    return
                }
                applyLocal(id: id) { $0.apply(stored) }
                if !stored.isPublic {
                    removeFromAuthorFeeds(id)
                }
            } catch {
                guard !Task.isCancelled, publicGeneration[id] == generation, writeSessionGeneration == session else {
                    return
                }
                if Self.isNotFound(error) {
                    dropUnavailableCard(id)
                    reportWriteFailure(error, Self.unavailableCardMessage)
                    return
                }
                applyLocal(id: id) { $0.isPublic = previousPublic }
                if previousPublic {
                    var restored = snapshot
                    restored.isPublic = true
                    restoreAuthorCards(restored, at: authorIndexes)
                }
                reportWriteFailure(
                    error,
                    Self.publicModerationMessage(for: error)
                        ?? "Couldn't change who can see this. Check your connection."
                )
            }
        }
    }

    // MARK: - Community safety

    func reportCard(_ id: UUID, reason: ReportReason) {
        guard reportTasks[id] == nil, let target = card(id: id) ?? stackCard(id), !target.isOwner else {
            return
        }
        let savedIndex = saved.cards.firstIndex { $0.id == id }
        let authorIndexes = authorCardIndexes(id)
        dropUnavailableCard(id)

        let session = writeSessionGeneration
        reportTasks[id] = Task { @MainActor in
            defer {
                if writeSessionGeneration == session {
                    reportTasks[id] = nil
                }
            }
            do {
                let state = try await cardsService.report(id: id.uuidString.lowercased(), reason: reason)
                guard state.reported else {
                    throw APIError.decoding("The report was not accepted.")
                }
            } catch {
                guard !Task.isCancelled, writeSessionGeneration == session else {
                    return
                }
                if let savedIndex, !saved.cards.contains(where: { $0.id == id }) {
                    saved.cards.insert(target, at: min(savedIndex, saved.cards.count))
                }
                restoreAuthorCards(target, at: authorIndexes)
                reportWriteFailure(error, "Couldn't report that card. Check your connection.")
            }
        }
    }

    func blockAuthor(_ authorId: UUID, initials: String, avatarPath: String?) {
        guard !isOwnAuthor(authorId), blockTasks[authorId] == nil else {
            return
        }
        let savedSnapshot = saved.cards
        let followedSnapshot = followedPeople
        let feedSnapshot = authorFeeds
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
        let session = writeSessionGeneration
        blockTasks[authorId] = Task { @MainActor in
            defer {
                if blockGeneration[authorId] == generation, writeSessionGeneration == session {
                    blockTasks[authorId] = nil
                }
            }
            do {
                let state = try await profileService.block(id: authorId.uuidString.lowercased())
                guard state.blocked else {
                    throw APIError.decoding("The block was not accepted.")
                }
                blocksGeneration &+= 1
            } catch {
                guard !Task.isCancelled, blockGeneration[authorId] == generation, writeSessionGeneration == session else {
                    return
                }
                saved.cards = savedSnapshot
                followedPeople = followedSnapshot
                for (id, snapshot) in feedSnapshot {
                    mutateAuthor(id) { feed in
                        feed.list.cards = snapshot.list.cards
                        feed.list.hasMore = snapshot.list.hasMore
                        feed.list.before = snapshot.list.before
                        feed.following = snapshot.following
                    }
                }
                blockedPeople.removeAll { $0.id == authorId }
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
        let session = writeSessionGeneration
        blockTasks[person.id] = Task { @MainActor in
            defer {
                if blockGeneration[person.id] == generation, writeSessionGeneration == session {
                    blockTasks[person.id] = nil
                }
            }
            do {
                let state = try await profileService.unblock(id: person.id.uuidString.lowercased())
                guard !state.blocked else {
                    throw APIError.decoding("The unblock was not accepted.")
                }
                blocksGeneration &+= 1
            } catch {
                guard !Task.isCancelled, blockGeneration[person.id] == generation, writeSessionGeneration == session else {
                    return
                }
                if !blockedPeople.contains(where: { $0.id == person.id }) {
                    blockedPeople.insert(person, at: min(index, blockedPeople.count))
                }
                reportWriteFailure(error, "Couldn't unblock that person. Check your connection.")
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

    private func removeAuthorLocally(_ authorId: UUID) {
        let isTheirs: (HomeCard) -> Bool = { $0.authorId == authorId && !$0.isOwner }
        saved.cards.removeAll(where: isTheirs)
        stack.remove(where: isTheirs)
        followedPeople.removeAll { $0.id == authorId }
        followNotices.removeAll { $0.actorId == authorId }
        loveNotices.removeAll { $0.actor?.id == authorId }
        unreadNotificationCount = followNotices.filter { $0.readAt == nil }.count
            + loveNotices.filter { $0.readAt == nil }.count
        followBadgeRevision &+= 1
        for id in Array(authorFeeds.keys) {
            mutateAuthor(id) { feed in
                feed.task?.cancel()
                feed.task = nil
                feed.list.generation &+= 1
                feed.list.cards.removeAll(where: isTheirs)
                feed.list.footerState = .idle
                if id == authorId {
                    feed.following = false
                    feed.list.hasMore = false
                    feed.list.before = nil
                    feed.list.hasLoaded = true
                    feed.list.loadState = .loaded
                }
            }
        }
    }

    private func isLocallyBlocked(_ card: HomeCard) -> Bool {
        guard !card.isOwner, let authorId = card.authorId else {
            return false
        }
        return blockedPeople.contains { $0.id == authorId }
    }

    // MARK: - Follows

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

    func loadFollowNotifications() async {
        if let existing = followLoadTask, followLoadTaskGeneration == followNoticesGeneration {
            await existing.value
            return
        }
        if followNotices.isEmpty, loveNotices.isEmpty {
            followNoticesLoadState = .loading
        }
        let generation = followNoticesGeneration
        followLoadTaskGeneration = generation
        let task = Task { @MainActor in
            defer {
                if self.followLoadTaskGeneration == generation {
                    self.followLoadTask = nil
                }
            }
            do {
                let response = try await self.profileService.followNotifications()
                guard !Task.isCancelled, generation == self.followNoticesGeneration else {
                    return
                }
                self.followNotices = response.notifications.compactMap(FollowNotice.init)
                self.loveNotices = response.loves.compactMap(LoveNotice.init)
                self.unreadNotificationCount = response.unreadCount
                self.followNoticesLoadState = .loaded
                self.followBadgeRevision &+= 1
            } catch {
                guard !Self.isCancellation(error), generation == self.followNoticesGeneration else {
                    return
                }
                if self.followNotices.isEmpty, self.loveNotices.isEmpty {
                    self.followNoticesLoadState = .failed("Couldn't load notifications.")
                }
            }
        }
        followLoadTask = task
        await task.value
    }

    func loadFollowNotificationsIfEmpty() async {
        guard followNotices.isEmpty, loveNotices.isEmpty else {
            return
        }
        await loadFollowNotifications()
    }

    /// Marks the specific follow or love notification from a tapped push (or row) read immediately.
    func markPushNotificationRead(followId: UUID? = nil, loveId: UUID? = nil, cardId: UUID? = nil) {
        let now = Date()
        var markedCount = 0
        if let followId {
            for index in followNotices.indices where followNotices[index].id == followId && followNotices[index].readAt == nil {
                followNotices[index].readAt = now
                markedCount += 1
            }
        }
        var resolvedLoveId = loveId
        if let cardId {
            for index in loveNotices.indices where loveNotices[index].cardId == cardId {
                if resolvedLoveId == nil {
                    resolvedLoveId = loveNotices[index].id
                }
                if loveNotices[index].readAt == nil {
                    loveNotices[index].readAt = now
                    markedCount += 1
                }
            }
        } else if let loveId {
            for index in loveNotices.indices where loveNotices[index].id == loveId && loveNotices[index].readAt == nil {
                loveNotices[index].readAt = now
                markedCount += 1
            }
        }
        if markedCount > 0 {
            unreadNotificationCount = max(0, unreadNotificationCount - markedCount)
            followBadgeRevision &+= 1
        }
        guard followId != nil || resolvedLoveId != nil else {
            return
        }
        let session = writeSessionGeneration
        followNoticesGeneration &+= 1
        Task { @MainActor in
            do {
                let left = try await profileService.markNotificationsRead(
                    throughId: followId?.uuidString.lowercased(),
                    loveThroughId: resolvedLoveId?.uuidString.lowercased()
                )
                guard writeSessionGeneration == session else {
                    return
                }
                followNoticesGeneration &+= 1
                unreadNotificationCount = left
                followBadgeRevision &+= 1
            } catch {
                return
            }
        }
    }

    /// The people sheet opened. The view model owns this work, so closing the sheet at once,
    /// or a dialog over it, still finishes the read. Rows already on screen are read first;
    /// the refresh then reads any follow that arrived since.
    func openedFollowNotifications() {
        let previous = followReadTask
        let session = writeSessionGeneration
        followReadTask = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled, writeSessionGeneration == session else {
                return
            }
            await markDisplayedFollowNotificationsRead()
            guard !Task.isCancelled, writeSessionGeneration == session else {
                return
            }
            await loadFollowNotifications()
            guard !Task.isCancelled, writeSessionGeneration == session else {
                return
            }
            await markDisplayedFollowNotificationsRead()
        }
    }

    /// Reads everything up to the newest row on screen. The server compares at its own
    /// precision and answers with the count left, which is what the badge shows.
    private func markDisplayedFollowNotificationsRead() async {
        guard followNoticesLoadState == .loaded else {
            return
        }
        let followThrough = followNotices.contains(where: { $0.readAt == nil }) ? followNotices.first : nil
        let loveThrough = loveNotices.contains(where: { $0.readAt == nil }) ? loveNotices.first : nil
        guard followThrough != nil || loveThrough != nil else {
            return
        }
        let session = writeSessionGeneration
        followNoticesGeneration &+= 1
        let now = Date()
        for index in followNotices.indices where followNotices[index].readAt == nil {
            followNotices[index].readAt = now
        }
        for index in loveNotices.indices where loveNotices[index].readAt == nil {
            loveNotices[index].readAt = now
        }
        unreadNotificationCount = 0
        followBadgeRevision &+= 1
        do {
            let left = try await profileService.markNotificationsRead(
                throughId: followThrough?.id.uuidString.lowercased(),
                loveThroughId: loveThrough?.id.uuidString.lowercased()
            )
            guard writeSessionGeneration == session else {
                return
            }
            followNoticesGeneration &+= 1
            unreadNotificationCount = left
            followBadgeRevision &+= 1
        } catch {
            // The server still has them unread; the next list restores the count.
            return
        }
    }

    func followBack(_ authorId: UUID) {
        guard !isOwnAuthor(authorId) else {
            return
        }
        if followNotices.contains(where: { $0.actorId == authorId && $0.following })
            || loveNotices.contains(where: { $0.actor?.id == authorId && $0.actor?.following == true })
            || isFollowing(authorId) {
            return
        }
        commitFollow(authorId, following: true)
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

    private func commitFollow(_ authorId: UUID, following next: Bool, onRollback: (() -> Void)? = nil) {
        setFollowing(authorId, following: next)
        let generation = (followGeneration[authorId] ?? 0) + 1
        followGeneration[authorId] = generation
        let session = writeSessionGeneration
        followTasks[authorId]?.cancel()
        followTasks[authorId] = Task { @MainActor in
            defer {
                if self.followGeneration[authorId] == generation, self.writeSessionGeneration == session {
                    self.followTasks[authorId] = nil
                }
            }
            do {
                let state = next
                    ? try await cardsService.follow(id: authorId.uuidString.lowercased())
                    : try await cardsService.unfollow(id: authorId.uuidString.lowercased())
                guard !Task.isCancelled, self.followGeneration[authorId] == generation,
                      self.writeSessionGeneration == session else {
                    return
                }
                setFollowing(authorId, following: state.following)
                if next, state.following, !followedPeople.contains(where: { $0.id == authorId }) {
                    if let notice = followNotices.first(where: { $0.actorId == authorId }) {
                        followedPeople.insert(
                            FollowedPerson(id: authorId, initials: notice.initials, avatarPath: notice.avatarPath),
                            at: 0
                        )
                    } else if let lover = loveNotices.lazy.compactMap(\.actor).first(where: { $0.id == authorId }) {
                        followedPeople.insert(
                            FollowedPerson(id: authorId, initials: lover.initials, avatarPath: lover.avatarPath),
                            at: 0
                        )
                    }
                }
            } catch {
                guard !Task.isCancelled, self.followGeneration[authorId] == generation,
                      self.writeSessionGeneration == session else {
                    return
                }
                setFollowing(authorId, following: !next)
                onRollback?()
                reportWriteFailure(error, "Couldn't update that follow. Check your connection.")
            }
        }
    }

    private func isOwnAuthor(_ authorId: UUID) -> Bool {
        if authorFeeds[authorId]?.isSelf == true {
            return true
        }
        return yours.cards.contains { $0.authorId == authorId }
    }

    private func isFollowing(_ authorId: UUID) -> Bool {
        if let feed = authorFeeds[authorId], !feed.isSelf {
            return feed.following
        }
        let isTheirs: (HomeCard) -> Bool = { $0.authorId == authorId && !$0.isOwner }
        if let card = stack.deck.cards.first(where: isTheirs) ?? saved.cards.first(where: isTheirs) {
            return card.authorFollowing
        }
        for feed in authorFeeds.values {
            if let card = feed.list.cards.first(where: isTheirs) {
                return card.authorFollowing
            }
        }
        return followedPeople.contains { $0.id == authorId }
    }

    private func setFollowing(_ authorId: UUID, following: Bool) {
        let update: (inout HomeCard) -> Void = { card in
            if card.authorId == authorId, !card.isOwner, !card.isHouse {
                card.authorFollowing = following
            }
        }
        for index in saved.cards.indices {
            update(&saved.cards[index])
        }
        stack.updateCards(update)
        for id in Array(authorFeeds.keys) {
            mutateAuthor(id) { feed in
                if id == authorId, !feed.isSelf {
                    feed.following = following
                }
                for index in feed.list.cards.indices {
                    update(&feed.list.cards[index])
                }
            }
        }
        for index in followNotices.indices where followNotices[index].actorId == authorId {
            followNotices[index].following = following
        }
        for index in loveNotices.indices where loveNotices[index].actor?.id == authorId {
            loveNotices[index].actor?.following = following
        }
    }

    // MARK: - Author pages

    /// Author pages are kept so a back and forth costs no fetch, but not without limit: past
    /// `maxAuthorFeeds`, the oldest idle ones go. Opening them again just refetches.
    private static let maxAuthorFeeds = 16

    func authorHeader(for authorId: UUID) -> AuthorHeader? {
        _ = authorRevision
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

    func authorList(_ authorId: UUID) -> CardList {
        _ = authorRevision
        return authorFeeds[authorId]?.list ?? CardList()
    }

    func loadAuthorIfNeeded(_ route: AuthorRoute) async {
        if authorFeeds[route.id] == nil {
            evictOldAuthorFeeds(keeping: route.id)
            authorFeeds[route.id] = AuthorFeed(
                initials: route.initials,
                avatarPath: route.avatarPath,
                isSelf: route.isSelf,
                following: route.isSelf ? false : isFollowing(route.id)
            )
            authorRevision &+= 1
        }
        guard authorFeeds[route.id]?.list.hasLoaded != true else {
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
        guard authorFeeds[id] != nil else {
            return
        }
        mutateAuthor(id) { feed in
            feed.task?.cancel()
            feed.task = nil
            feed.list.generation &+= 1
            feed.list.footerState = .idle
        }
        startAuthorTask(id, replacing: true)
        await authorFeeds[id]?.task?.value
    }

    func retryLoadAuthor(_ id: UUID) {
        guard authorFeeds[id] != nil else {
            return
        }
        mutateAuthor(id) { feed in
            feed.task?.cancel()
            feed.task = nil
            feed.list.generation &+= 1
            feed.list.before = nil
            feed.list.footerState = .idle
            feed.list.hasLoaded = false
            if feed.list.cards.isEmpty {
                feed.list.loadState = .loading
            }
        }
        startAuthorTask(id, replacing: true)
    }

    func loadMoreAuthor(_ id: UUID) {
        guard let feed = authorFeeds[id], feed.list.hasLoaded, feed.list.hasMore,
              feed.list.before != nil, feed.list.footerState == .idle, feed.task == nil
        else {
            return
        }
        mutateAuthor(id) { $0.list.footerState = .loading }
        startAuthorTask(id, replacing: false)
    }

    func retryLoadMoreAuthor(_ id: UUID) {
        guard let feed = authorFeeds[id], feed.list.footerState == .failed, feed.task == nil else {
            return
        }
        mutateAuthor(id) { $0.list.footerState = .loading }
        startAuthorTask(id, replacing: feed.list.before == nil)
    }

    private func evictOldAuthorFeeds(keeping id: UUID) {
        authorFeedOrder.removeAll { $0 == id || authorFeeds[$0] == nil }
        while authorFeeds.count >= Self.maxAuthorFeeds,
              let oldest = authorFeedOrder.first(where: { authorFeeds[$0]?.task == nil }) {
            authorFeeds[oldest] = nil
            authorFeedOrder.removeAll { $0 == oldest }
        }
        authorFeedOrder.append(id)
    }

    private func startAuthorTask(_ id: UUID, replacing: Bool) {
        guard let feed = authorFeeds[id], feed.task == nil else {
            return
        }
        let generation = feed.list.generation
        let task = Task { @MainActor in
            await self.fetchAuthorPage(id: id, replacing: replacing, generation: generation)
            guard self.authorFeeds[id]?.list.generation == generation else {
                return
            }
            self.mutateAuthor(id) { $0.task = nil }
        }
        mutateAuthor(id) { $0.task = task }
    }

    private func fetchAuthorPage(id: UUID, replacing: Bool, generation: Int) async {
        let before = replacing ? nil : authorFeeds[id]?.list.before
        do {
            let response = try await cardsService.listAuthorCards(
                id: id.uuidString.lowercased(),
                limit: Self.authorPageSize,
                before: before
            )
            guard !Task.isCancelled, authorFeeds[id]?.list.generation == generation else {
                return
            }
            let incoming = response.cards.compactMap(HomeCard.init(stored:)).filter { !isLocallyBlocked($0) }
            withoutAnimation {
                mutateAuthor(id) { feed in
                    let preserveFollow = self.followTasks[id] != nil
                    feed.initials = response.user.initials
                    feed.avatarPath = response.user.avatarUrl
                    if response.cards.contains(where: \.isOwner) {
                        feed.isSelf = true
                    }
                    if replacing {
                        let local = Dictionary(feed.list.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                        feed.list.cards = incoming.map { card in
                            var card = self.patched(card, local: local[card.id])
                            if self.writer.isPending(card.id), let mine = local[card.id] {
                                card.decision = mine.decision
                            }
                            return card
                        }
                    } else {
                        feed.list.cards = self.appended(incoming, to: feed.list.cards, segment: .yours)
                    }
                    if let cursor = response.page.nextCursor {
                        feed.list.before = cursor
                    } else if replacing {
                        feed.list.before = nil
                    }
                    feed.list.hasMore = response.page.hasMore(pageSize: Self.authorPageSize)
                    feed.list.footerState = .idle
                    feed.list.loadState = .loaded
                    feed.list.hasLoaded = true
                    if feed.isSelf {
                        feed.following = false
                    } else if !preserveFollow {
                        feed.following = response.user.following
                    }
                }
            }
        } catch {
            guard !Task.isCancelled, authorFeeds[id]?.list.generation == generation, !Self.isCancellation(error) else {
                return
            }
            mutateAuthor(id) { feed in
                if case APIError.httpStatus(404, _, _) = error {
                    feed.list.loadState = .failed("That profile isn't available.")
                    feed.list.footerState = .idle
                    feed.list.hasMore = false
                } else if replacing, feed.list.cards.isEmpty {
                    feed.list.loadState = .failed("Couldn't load these posts.")
                    feed.list.footerState = .idle
                } else {
                    feed.list.footerState = .failed
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
        authorRevision &+= 1
    }

    private func removeFromAuthorFeeds(_ id: UUID) {
        for authorId in Array(authorFeeds.keys) where authorFeeds[authorId]?.list.cards.contains(where: { $0.id == id }) == true {
            mutateAuthor(authorId) { $0.list.cards.removeAll { $0.id == id } }
        }
    }

    private func authorCardIndexes(_ id: UUID) -> [UUID: Int] {
        var indexes: [UUID: Int] = [:]
        for (authorId, feed) in authorFeeds {
            if let index = feed.list.cards.firstIndex(where: { $0.id == id }) {
                indexes[authorId] = index
            }
        }
        return indexes
    }

    private func restoreAuthorCards(_ card: HomeCard, at indexes: [UUID: Int]) {
        for (authorId, index) in indexes {
            mutateAuthor(authorId) { feed in
                guard !feed.list.cards.contains(where: { $0.id == card.id }) else {
                    return
                }
                feed.list.cards.insert(card, at: min(index, feed.list.cards.count))
            }
        }
    }

    // MARK: - Shared card state

    func postCard(id: UUID) -> HomeCard? {
        card(id: id)
    }

    func fetchPost(id: UUID) async -> PostFetchResult {
        let session = writeSessionGeneration
        do {
            let stored = try await cardsService.get(id: id.uuidString.lowercased())
            guard !Task.isCancelled, writeSessionGeneration == session else {
                return .cancelled
            }
            guard var fetched = HomeCard(stored: stored) else {
                return .failed
            }
            if publicTasks[fetched.id] != nil, let local = yours.cards.first(where: { $0.id == fetched.id }) {
                fetched.isPublic = local.isPublic
            }
            if fetched.isOwner {
                if let index = yours.cards.firstIndex(where: { $0.id == fetched.id }) {
                    yours.cards[index] = fetched
                } else {
                    yours.cards.insert(fetched, at: 0)
                }
            }
            applyLocal(id: fetched.id) { $0.apply(stored) }
            return .loaded(fetched)
        } catch {
            if Self.isCancellation(error) || Task.isCancelled {
                return .cancelled
            }
            if Self.isNotFound(error) {
                dropUnavailableCard(id)
                return .notFound
            }
            return .failed
        }
    }

    private func card(id: UUID) -> HomeCard? {
        if let match = saved.cards.first(where: { $0.id == id }) ?? yours.cards.first(where: { $0.id == id }) {
            return match
        }
        for feed in authorFeeds.values {
            if let match = feed.list.cards.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    private func stackCard(_ id: UUID) -> HomeCard? {
        stack.deck.cards.first { $0.id == id }
    }

    private func ownerCard(id: UUID) -> HomeCard? {
        guard let match = card(id: id), match.isOwner else {
            return nil
        }
        return match
    }

    private func applyLocal(id: UUID, _ body: (inout HomeCard) -> Void) {
        if let index = yours.cards.firstIndex(where: { $0.id == id }) {
            body(&yours.cards[index])
        }
        if let index = saved.cards.firstIndex(where: { $0.id == id }) {
            body(&saved.cards[index])
        }
        for authorId in Array(authorFeeds.keys) where authorFeeds[authorId]?.list.cards.contains(where: { $0.id == id }) == true {
            mutateAuthor(authorId) { feed in
                if let index = feed.list.cards.firstIndex(where: { $0.id == id }) {
                    body(&feed.list.cards[index])
                }
            }
        }
    }

    /// A card the server no longer has leaves every list and the stack at once.
    private func dropUnavailableCard(_ id: UUID) {
        yours.cards.removeAll { $0.id == id }
        saved.cards.removeAll { $0.id == id }
        removeFromAuthorFeeds(id)
        stack.remove { $0.id == id }
    }

    private static let unavailableCardMessage = "That card isn't available anymore."

    private static func isNotFound(_ error: Error) -> Bool {
        if case APIError.httpStatus(404, _, _) = error {
            return true
        }
        return false
    }

    static func publicModerationMessage(for error: Error) -> String? {
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

    // MARK: - Banners

    /// Every write here is optimistic, so a rollback looks like the tap never happened.
    /// Say so instead.
    private func reportWriteFailure(_ error: Error, _ message: String) {
        guard !Self.isCancellation(error) else {
            return
        }
        showWriteError(message)
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

    // MARK: - Session

    /// Log out starts over on this iPhone: nothing the last session loaded stays in memory, and
    /// the next unlock loads Home and the library from scratch.
    func resetForSignOut() {
        tasteEndedByServer = false
        writeSessionGeneration &+= 1
        compose.abandonInFlight()
        writer.reset()
        stack.reset()
        for task in listTasks.values { task.cancel() }
        for task in followTasks.values { task.cancel() }
        for task in publicTasks.values { task.cancel() }
        for task in deleteTasks.values { task.cancel() }
        for task in reportTasks.values { task.cancel() }
        for task in blockTasks.values { task.cancel() }
        for feed in authorFeeds.values { feed.task?.cancel() }
        listTasks = [:]
        followTasks = [:]
        followGeneration = [:]
        publicTasks = [:]
        publicGeneration = [:]
        deleteTasks = [:]
        reportTasks = [:]
        blockTasks = [:]
        blockGeneration = [:]
        authorFeeds = [:]
        authorFeedOrder = []
        authorRevision &+= 1

        yours = CardList()
        saved = CardList()
        profileSegment = .yours

        followedPeople = []
        followingLoadState = .loading
        blockedPeople = []
        blocksLoadState = .loading
        followNotices = []
        loveNotices = []
        followNoticesLoadState = .loading
        unreadNotificationCount = 0
        followBadgeRevision &+= 1
        followNoticesGeneration &+= 1
        followLoadTask?.cancel()
        followLoadTask = nil
        followLoadTaskGeneration = -1
        followReadTask?.cancel()
        followReadTask = nil
        blocksGeneration &+= 1
        configureUsageAccount(userID: nil)
        dismissWriteError()
        dismissPostToast()
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
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

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }
}

extension HomeViewModel: ComposeSessionHost {
    var usageIsCritical: Bool {
        usageSummary?.warning == .critical
    }

    var libraryCardCount: Int {
        yours.cards.count
    }

    func markTasteEnded() {
        tasteEndedByServer = true
    }

    func insertSavedCard(_ card: HomeCard) {
        yours.cards.removeAll { $0.id == card.id }
        yours.cards.insert(card, at: 0)
    }
}

extension HomeViewModel: StackHost {
    func stackSaved(_ card: HomeCard) {
        insertSaved(card)
        applyLocal(id: card.id) { $0.decision = card.decision }
        profilePulseToken &+= 1
        discloseLoveIfFirst(card)
    }

    func stackUnsaved(_ card: HomeCard) {
        saved.cards.removeAll { $0.id == card.id }
        applyLocal(id: card.id) { $0.decision = card.decision }
        insertSaved(card)
    }

    func stackCardGone(_ id: UUID) {
        dropUnavailableCard(id)
    }

    func stackWriteFailed(_ error: Error, _ message: String) {
        reportWriteFailure(error, message)
    }

    func isBlocked(_ card: HomeCard) -> Bool {
        isLocallyBlocked(card)
    }
}
