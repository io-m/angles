import Foundation

struct HomeCardSlide: Identifiable, Equatable {
    let id: UUID
    let thought: String
    var result: ReframeResult
    /// People who saved the card while this angle was on screen. Only your own public cards carry it.
    var saveCount: Int?
}

struct HomeCard: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    /// Exact server timestamp retained for cursor pagination.
    let createdAtCursor: String
    var slides: [HomeCardSlide] {
        didSet {
            styles = slides.map(\.result.style)
        }
    }
    /// The card's angles in the cook's order.
    private(set) var styles: [Style]
    var spotlightStyle: Style
    /// The angle this card opens on for this viewer (the server's `openingStyle`).
    var openingStyle: Style
    /// Cleaned thought in the language it was typed in, when that is not English.
    var thoughtOriginal: String?
    var isPublic: Bool
    /// An operator hid this card. The author sees why, and cannot publish it.
    var moderationHidden: Bool
    var isOwner: Bool
    /// A curated card from Angles. It shows the Angles mark and has no follow.
    var isHouse: Bool
    /// Stable author id. Nil when the payload has no UUID, so the avatar does not navigate.
    var authorId: UUID?
    var authorInitials: String
    /// `/avatars/{id}?v=` when this author has a photo. Nil means initials.
    var authorAvatarPath: String?
    /// Viewer follows this author. Always false on your own cards and house cards.
    var authorFollowing: Bool
    /// The viewer's save or pass on someone else's card.
    var decision: CardDecision?
    /// People who saved your own public card.
    var saveCount: Int?
    var meta: ReframeMeta?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        createdAtCursor: String? = nil,
        slides: [HomeCardSlide],
        spotlightStyle: Style = .stoic,
        openingStyle: Style? = nil,
        thoughtOriginal: String? = nil,
        isPublic: Bool = false,
        moderationHidden: Bool = false,
        isOwner: Bool = true,
        isHouse: Bool = false,
        authorId: UUID? = nil,
        authorInitials: String = UserInitials.letters,
        authorAvatarPath: String? = nil,
        authorFollowing: Bool = false,
        decision: CardDecision? = nil,
        saveCount: Int? = nil,
        meta: ReframeMeta? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.createdAtCursor = createdAtCursor ?? ISO8601Dates.string(from: createdAt)
        let styles = slides.map(\.result.style)
        self.slides = slides
        self.styles = styles
        self.spotlightStyle = spotlightStyle
        self.openingStyle = openingStyle.flatMap { styles.contains($0) ? $0 : nil }
            ?? (styles.contains(spotlightStyle) ? spotlightStyle : styles.first ?? spotlightStyle)
        self.thoughtOriginal = thoughtOriginal
        self.isPublic = isPublic
        self.moderationHidden = moderationHidden
        self.isOwner = isOwner
        self.isHouse = isHouse
        self.authorId = authorId
        self.authorInitials = authorInitials
        self.authorAvatarPath = authorAvatarPath
        self.authorFollowing = authorFollowing
        self.decision = decision
        self.saveCount = saveCount
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
                result: result.result,
                saveCount: result.saveCount
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
            openingStyle: stored.openingStyle,
            thoughtOriginal: stored.thoughtOriginal,
            isPublic: stored.isPublic,
            moderationHidden: stored.moderationHidden ?? false,
            isOwner: stored.isOwner,
            isHouse: stored.isHouse,
            authorId: UUID(uuidString: stored.author.id),
            authorInitials: stored.author.initials,
            authorAvatarPath: stored.author.avatarUrl,
            authorFollowing: stored.isOwner || stored.isHouse ? false : stored.author.following,
            decision: stored.isOwner ? nil : stored.decision,
            saveCount: stored.saveCount,
            meta: stored.reframeMeta
        )
    }

    var thought: String {
        slides.first?.thought ?? ""
    }

    static let moderationHiddenMessage =
        "Hidden by Angles. This post broke the community rules."

    var moderationNoticeText: String? {
        isOwner && !isPublic && moderationHidden ? Self.moderationHiddenMessage : nil
    }

    var allowsOwnerVisibilityChange: Bool {
        isOwner && !(!isPublic && moderationHidden)
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

    var isSaved: Bool {
        decision?.kind == .save
    }

    /// Someone else's card that can be saved or passed. Never your own.
    var isDecidable: Bool {
        !isOwner
    }

    func hasStyle(_ style: Style) -> Bool {
        styles.contains(style)
    }

    func slide(for style: Style) -> HomeCardSlide? {
        slides.first { $0.result.style == style }
    }

    mutating func apply(_ stored: StoredCard) {
        isPublic = stored.isPublic
        moderationHidden = stored.moderationHidden ?? false
        thoughtOriginal = stored.thoughtOriginal
        isHouse = stored.isHouse
        if let authorId = UUID(uuidString: stored.author.id) {
            self.authorId = authorId
        }
        authorInitials = stored.author.initials
        authorAvatarPath = stored.author.avatarUrl
        authorFollowing = stored.isOwner || stored.isHouse ? false : stored.author.following
        decision = stored.isOwner ? nil : stored.decision
        saveCount = stored.saveCount
        for index in slides.indices {
            let style = slides[index].result.style
            guard let match = stored.results.first(where: { $0.style == style }) else {
                continue
            }
            slides[index].result = match.result
            slides[index].saveCount = match.saveCount
        }
    }
}

extension Style {
    var displayName: String {
        switch self {
        case .stoic:
            return "Stoic"
        case .hopeful:
            return "Hopeful"
        case .witty:
            return "Witty"
        case .tough:
            return "Tough"
        case .tender:
            return "Tender"
        case .values:
            return "Values"
        }
    }
}
