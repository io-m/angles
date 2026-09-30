import Foundation

/// One Home tab's page. The cards themselves live on `HomeFeedBoard`, so a heart
/// or a follow updates every shelf that is showing that post.
struct HomeFeedShelfState {
    var order: [UUID] = []
    var ids: Set<UUID> = []
    var before: String?
    var hasMore = true
    var loadState: LibraryLoadState = .loading
    var footerState: FeedFooterState = .idle
    var highWater: FeedCardMark?
    var seenIDs: Set<UUID> = []
    var isRotated = false
    var hasLoaded = false
    var generation = 0
    var isRefreshing = false
    var refreshOutcome: FeedRefreshOutcome?
    var refreshToken = 0
}

struct HomeFeedPlacement: Equatable {
    var tab: HomeFeedTab
    var index: Int
}

/// Shared card records plus one ordered shelf per Home tab.
struct HomeFeedBoard {
    private(set) var records: [UUID: HomeCard] = [:]
    private(set) var shelves: [HomeFeedTab: HomeFeedShelfState]
    /// Public cards inserted locally that a replacing page must not drop.
    private(set) var anchors: [UUID: HomeCard] = [:]

    init() {
        var shelves: [HomeFeedTab: HomeFeedShelfState] = [:]
        for tab in HomeFeedTab.allCases {
            shelves[tab] = HomeFeedShelfState()
        }
        self.shelves = shelves
    }

    func cards(on tab: HomeFeedTab) -> [HomeCard] {
        guard let shelf = shelves[tab] else {
            return []
        }
        return shelf.order.compactMap { records[$0] }
    }

    func record(_ id: UUID) -> HomeCard? {
        records[id]
    }

    func shelf(_ tab: HomeFeedTab) -> HomeFeedShelfState {
        shelves[tab] ?? HomeFeedShelfState()
    }

    func includes(_ card: HomeCard, on tab: HomeFeedTab) -> Bool {
        guard let style = tab.matchingStyle else {
            return true
        }
        return card.hasStyle(style)
    }

    func placements(of id: UUID) -> [HomeFeedPlacement] {
        HomeFeedTab.allCases.compactMap { tab in
            guard let index = shelves[tab]?.order.firstIndex(of: id) else {
                return nil
            }
            return HomeFeedPlacement(tab: tab, index: index)
        }
    }

    func placements(where matches: (HomeCard) -> Bool) -> [(placement: HomeFeedPlacement, card: HomeCard)] {
        var found: [(placement: HomeFeedPlacement, card: HomeCard)] = []
        for tab in HomeFeedTab.allCases {
            guard let shelf = shelves[tab] else {
                continue
            }
            for (index, id) in shelf.order.enumerated() {
                guard let card = records[id], matches(card) else {
                    continue
                }
                found.append((HomeFeedPlacement(tab: tab, index: index), card))
            }
        }
        return found
    }

    mutating func remember(_ card: HomeCard) {
        records[card.id] = card
        if anchors[card.id] != nil {
            anchors[card.id] = card
        }
    }

    @discardableResult
    mutating func update(_ id: UUID, _ body: (inout HomeCard) -> Void) -> Bool {
        guard var card = records[id] else {
            return false
        }
        body(&card)
        remember(card)
        return true
    }

    mutating func updateAuthor(_ authorId: UUID, following: Bool) {
        for id in Array(records.keys) {
            guard var card = records[id], card.authorId == authorId, !card.isOwner else {
                continue
            }
            card.authorFollowing = following
            remember(card)
        }
    }

    mutating func updateOwners(initials: String, avatarPath: String?) {
        for id in Array(records.keys) where records[id]?.isOwner == true {
            update(id) { card in
                card.authorInitials = initials
                card.authorAvatarPath = avatarPath
            }
        }
    }

    mutating func remove(_ id: UUID) {
        records[id] = nil
        anchors[id] = nil
        for tab in HomeFeedTab.allCases {
            guard var shelf = shelves[tab] else {
                continue
            }
            shelf.order.removeAll { $0 == id }
            shelf.ids.remove(id)
            shelves[tab] = shelf
        }
    }

    mutating func remove(where matches: (HomeCard) -> Bool) {
        let ids = records.values.filter(matches).map(\.id)
        for id in ids {
            remove(id)
        }
    }

    mutating func restore(_ card: HomeCard, at placement: HomeFeedPlacement) {
        records[card.id] = card
        guard var shelf = shelves[placement.tab] else {
            return
        }
        guard !shelf.ids.contains(card.id) else {
            shelves[placement.tab] = shelf
            return
        }
        let index = min(placement.index, shelf.order.count)
        shelf.order.insert(card.id, at: index)
        shelf.ids.insert(card.id)
        shelves[placement.tab] = shelf
    }

    mutating func restoreAnchor(_ card: HomeCard) {
        anchors[card.id] = card
        records[card.id] = records[card.id] ?? card
    }

    @discardableResult
    mutating func bump(_ tab: HomeFeedTab) -> Int {
        var shelf = shelves[tab] ?? HomeFeedShelfState()
        shelf.generation &+= 1
        shelves[tab] = shelf
        return shelf.generation
    }

    /// Starts a pull. Nil when one is already running on this shelf.
    mutating func beginRefresh(on tab: HomeFeedTab) -> Int? {
        guard var shelf = shelves[tab], !shelf.isRefreshing else {
            return nil
        }
        shelf.isRefreshing = true
        shelf.generation &+= 1
        shelf.footerState = .idle
        shelf.loadState = shelf.order.isEmpty ? .loading : .loaded
        shelves[tab] = shelf
        return shelf.generation
    }

    mutating func stopRefresh(on tab: HomeFeedTab) {
        guard var shelf = shelves[tab] else {
            return
        }
        shelf.isRefreshing = false
        shelves[tab] = shelf
    }

    mutating func endRefresh(on tab: HomeFeedTab, generation: Int) {
        guard var shelf = shelves[tab], shelf.generation == generation else {
            return
        }
        shelf.isRefreshing = false
        shelves[tab] = shelf
    }

    mutating func markLoading(on tab: HomeFeedTab, replacing: Bool) {
        guard var shelf = shelves[tab] else {
            return
        }
        if replacing, shelf.order.isEmpty {
            shelf.loadState = .loading
            shelf.footerState = .idle
        } else {
            shelf.footerState = .loading
        }
        shelves[tab] = shelf
    }

    mutating func setFooter(_ footer: FeedFooterState, on tab: HomeFeedTab) {
        guard var shelf = shelves[tab] else {
            return
        }
        shelf.footerState = footer
        shelves[tab] = shelf
    }

    enum Commit: Equatable {
        case applied
        case stale
    }

    mutating func replace(
        _ page: [HomeCard],
        on tab: HomeFeedTab,
        before: String?,
        hasMore: Bool,
        generation: Int,
        filter: (HomeCard) -> Bool,
        pageSize: Int
    ) -> Commit {
        guard var shelf = shelves[tab], shelf.generation == generation else {
            return .stale
        }

        let next = mergingAnchors(into: page, on: tab, filter: filter, pageSize: pageSize)
        for card in next {
            records[card.id] = card
        }
        shelf.order = next.map(\.id)
        shelf.ids = Set(shelf.order)
        note(&shelf, next)
        shelf.before = before
        shelf.hasMore = hasMore
        shelf.footerState = .idle
        shelf.loadState = .loaded
        shelf.hasLoaded = true
        shelf.isRotated = false
        shelves[tab] = shelf
        return .applied
    }

    mutating func append(
        _ page: [HomeCard],
        on tab: HomeFeedTab,
        before: String?,
        hasMore: Bool,
        generation: Int
    ) -> Commit {
        guard var shelf = shelves[tab], shelf.generation == generation else {
            return .stale
        }
        var arrived: [HomeCard] = []
        for card in page {
            records[card.id] = card
            anchors[card.id] = nil
            guard shelf.ids.insert(card.id).inserted else {
                continue
            }
            shelf.order.append(card.id)
            arrived.append(card)
        }
        note(&shelf, arrived)
        if let before {
            shelf.before = before
        }
        shelf.hasMore = hasMore
        shelf.footerState = .idle
        shelf.loadState = .loaded
        shelf.hasLoaded = true
        shelves[tab] = shelf
        return .applied
    }

    mutating func prepend(
        _ cards: [HomeCard],
        on tab: HomeFeedTab,
        generation: Int
    ) -> Commit {
        guard var shelf = shelves[tab], shelf.generation == generation else {
            return .stale
        }
        var fresh: [HomeCard] = []
        for card in cards {
            records[card.id] = card
            guard shelf.ids.insert(card.id).inserted else {
                continue
            }
            fresh.append(card)
        }
        shelf.order.insert(contentsOf: fresh.map(\.id), at: 0)
        note(&shelf, fresh)
        shelf.loadState = .loaded
        shelf.hasLoaded = true
        shelf.footerState = .idle
        shelves[tab] = shelf
        return .applied
    }

    /// A rotation swaps the visible page but keeps the visit's high-water mark.
    mutating func rotate(
        _ page: [HomeCard],
        on tab: HomeFeedTab,
        before: String?,
        hasMore: Bool,
        generation: Int,
        filter: (HomeCard) -> Bool,
        pageSize: Int
    ) -> Commit {
        guard var shelf = shelves[tab], shelf.generation == generation else {
            return .stale
        }
        let next = mergingAnchors(into: page, on: tab, filter: filter, pageSize: pageSize)
        for card in next {
            records[card.id] = card
        }
        shelf.order = next.map(\.id)
        shelf.ids = Set(shelf.order)
        note(&shelf, next)
        shelf.before = before
        shelf.hasMore = hasMore
        shelf.footerState = .idle
        shelf.loadState = .loaded
        shelf.hasLoaded = true
        shelf.isRotated = true
        shelves[tab] = shelf
        return .applied
    }

    mutating func fail(
        on tab: HomeFeedTab,
        generation: Int,
        replacing: Bool,
        message: String
    ) -> Commit {
        guard var shelf = shelves[tab], shelf.generation == generation else {
            return .stale
        }
        if replacing, shelf.order.isEmpty {
            shelf.loadState = .failed(message)
        } else {
            shelf.footerState = .failed
        }
        shelves[tab] = shelf
        return .applied
    }

    mutating func publish(_ outcome: FeedRefreshOutcome, on tab: HomeFeedTab, generation: Int) -> Commit {
        guard var shelf = shelves[tab], shelf.generation == generation else {
            return .stale
        }
        shelf.refreshOutcome = outcome
        shelf.refreshToken &+= 1
        shelves[tab] = shelf
        return .applied
    }

    /// The card you just posted. For you gets it immediately; a style shelf gets it
    /// only once that shelf has already loaded and the card has that angle.
    mutating func insertPublishedAtFront(_ card: HomeCard) {
        records[card.id] = card
        anchors[card.id] = card
        for tab in HomeFeedTab.allCases {
            guard var shelf = shelves[tab] else {
                continue
            }
            let open = tab == .all || shelf.hasLoaded
            guard open, includes(card, on: tab) else {
                continue
            }
            shelf.order.removeAll { $0 == card.id }
            shelf.order.insert(card.id, at: 0)
            shelf.ids.insert(card.id)
            note(&shelf, [card])
            shelf.loadState = .loaded
            shelf.hasLoaded = true
            shelves[tab] = shelf
        }
    }

    /// A card that became public lands in newest-first position on loaded shelves.
    mutating func insertPublishedInOrder(_ card: HomeCard) {
        records[card.id] = card
        for tab in HomeFeedTab.allCases {
            guard var shelf = shelves[tab], shelf.hasLoaded, includes(card, on: tab) else {
                continue
            }
            if shelf.ids.contains(card.id) {
                shelves[tab] = shelf
                continue
            }
            if shelf.hasMore,
               let lastID = shelf.order.last,
               let last = records[lastID],
               !FeedOrder.isBefore(card, last) {
                continue
            }
            let index = shelf.order.firstIndex { id in
                guard let other = records[id] else {
                    return false
                }
                return FeedOrder.isBefore(card, other)
            } ?? shelf.order.endIndex
            shelf.order.insert(card.id, at: index)
            shelf.ids.insert(card.id)
            anchors[card.id] = card
            shelves[tab] = shelf
        }
    }

    /// Clears every shelf. `blank` drops the cards on screen; otherwise For you stays
    /// up until its replacement page arrives and the style shelves reload later.
    mutating func invalidate(blank: Bool) {
        if blank {
            let generations = shelves.mapValues(\.generation)
            records = [:]
            anchors = [:]
            for tab in HomeFeedTab.allCases {
                var shelf = HomeFeedShelfState()
                shelf.generation = (generations[tab] ?? 0) &+ 1
                shelves[tab] = shelf
            }
            return
        }

        for tab in HomeFeedTab.allCases {
            var shelf = shelves[tab] ?? HomeFeedShelfState()
            shelf.generation &+= 1
            shelf.before = nil
            shelf.hasMore = true
            shelf.highWater = nil
            shelf.seenIDs = []
            shelf.isRotated = false
            shelf.footerState = .idle
            shelf.isRefreshing = false
            if tab != .all {
                shelf.order = []
                shelf.ids = []
                shelf.hasLoaded = false
                shelf.loadState = .loading
            }
            shelves[tab] = shelf
        }
        let live = Set(shelves.values.flatMap(\.order)).union(anchors.keys)
        records = records.filter { live.contains($0.key) }
    }

    mutating func reset() {
        records = [:]
        anchors = [:]
        for tab in HomeFeedTab.allCases {
            shelves[tab] = HomeFeedShelfState()
        }
    }

    mutating func clearVisitHistory(on tab: HomeFeedTab, generation: Int) -> Commit {
        guard var shelf = shelves[tab], shelf.generation == generation else {
            return .stale
        }
        shelf.seenIDs = []
        shelf.isRotated = false
        shelves[tab] = shelf
        return .applied
    }

    private mutating func mergingAnchors(
        into page: [HomeCard],
        on tab: HomeFeedTab,
        filter: (HomeCard) -> Bool,
        pageSize: Int
    ) -> [HomeCard] {
        var next = page
        let returned = Set(next.map(\.id))
        for id in returned where anchors[id] != nil {
            anchors[id] = nil
        }
        let missing = anchors.values
            .filter { anchor in
                anchor.isPublic
                    && filter(anchor)
                    && !returned.contains(anchor.id)
                    && includes(anchor, on: tab)
            }
            .sorted { FeedOrder.isBefore($0, $1) }
        let pageIsFull = page.count >= pageSize
        for anchor in missing {
            if pageIsFull, let last = next.last, !FeedOrder.isBefore(anchor, last) {
                continue
            }
            let index = next.firstIndex { FeedOrder.isBefore(anchor, $0) } ?? next.endIndex
            next.insert(anchor, at: index)
        }
        return next
    }

    private func note(_ shelf: inout HomeFeedShelfState, _ cards: [HomeCard]) {
        for card in cards {
            shelf.seenIDs.insert(card.id)
            if let mark = shelf.highWater {
                if FeedOrder.isNewer(card, than: mark) {
                    shelf.highWater = FeedCardMark(card)
                }
            } else {
                shelf.highWater = FeedCardMark(card)
            }
        }
    }
}
