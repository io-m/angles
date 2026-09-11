import Foundation

/// Mirrors backend `src/types/index.ts`. Keep JSON keys in sync.

enum Style: String, Codable, CaseIterable, Sendable {
    case stoic
    case optimistic
    case humorous
    case toughLove = "tough_love"
}

/// Closed set on the backend. Anything new decodes as `.other` so a server-side
/// addition cannot fail a whole cook.
enum ThoughtCategory: String, Codable, CaseIterable, Sendable {
    case work
    case money
    case romantic
    case family
    case friendsSocial = "friends_social"
    case health
    case selfWorth = "self_worth"
    case future
    case griefLoss = "grief_loss"
    case identity
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ThoughtCategory(rawValue: raw) ?? .other
    }

    var displayName: String {
        switch self {
        case .work: return "Work"
        case .money: return "Money"
        case .romantic: return "Romantic"
        case .family: return "Family"
        case .friendsSocial: return "Friends"
        case .health: return "Health"
        case .selfWorth: return "Self-worth"
        case .future: return "Future"
        case .griefLoss: return "Grief"
        case .identity: return "Identity"
        case .other: return "Other"
        }
    }
}

enum Emotion: String, Codable, CaseIterable, Sendable {
    case anger
    case shame
    case fear
    case sadness
    case envy
    case loneliness
    case overwhelm
    case numbness
    case hope

    var displayName: String {
        switch self {
        case .anger: return "Anger"
        case .shame: return "Shame"
        case .fear: return "Fear"
        case .sadness: return "Sadness"
        case .envy: return "Envy"
        case .loneliness: return "Loneliness"
        case .overwhelm: return "Overwhelm"
        case .numbness: return "Numbness"
        case .hope: return "Hope"
        }
    }
}

enum Timeframe: String, Codable, CaseIterable, Sendable {
    case past
    case ongoing
    case future

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Timeframe(rawValue: raw) ?? .ongoing
    }
}

enum SafetyFlag: String, Codable, CaseIterable, Sendable {
    case none
    case selfHarm = "self_harm"
    case harmOthers = "harm_others"
    case abuse

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SafetyFlag(rawValue: raw) ?? .none
    }

    var needsCare: Bool {
        self != .none
    }
}

enum IntensityBand: String, Codable, CaseIterable, Sendable {
    case low
    case mid
    case high

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IntensityBand(rawValue: raw) ?? .mid
    }
}

struct SkippedStyle: Codable, Equatable, Sendable {
    let style: Style
    let reason: String
}

/// Anonymous similarity key for later community matching. Never carries text.
struct MatchingKey: Codable, Equatable, Sendable {
    let category: ThoughtCategory
    let tags: [String]
    let intensityBand: IntensityBand
}

struct ReframeMeta: Codable, Equatable, Sendable {
    let category: ThoughtCategory
    let proposedCategory: String?
    let proposedLabel: String?
    let tags: [String]
    let intensity: Int
    let timeframe: Timeframe
    let emotions: [Emotion]
    let safety: SafetyFlag
    let inputLanguage: String
    let skippedStyles: [SkippedStyle]
    let matching: MatchingKey

    init(
        category: ThoughtCategory,
        proposedCategory: String? = nil,
        proposedLabel: String? = nil,
        tags: [String],
        intensity: Int,
        timeframe: Timeframe,
        emotions: [Emotion],
        safety: SafetyFlag,
        inputLanguage: String,
        skippedStyles: [SkippedStyle],
        matching: MatchingKey
    ) {
        self.category = category
        self.proposedCategory = proposedCategory
        self.proposedLabel = proposedLabel
        self.tags = tags
        self.intensity = intensity
        self.timeframe = timeframe
        self.emotions = emotions
        self.safety = safety
        self.inputLanguage = inputLanguage
        self.skippedStyles = skippedStyles
        self.matching = matching
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(ThoughtCategory.self, forKey: .category)
        proposedCategory = try container.decodeIfPresent(String.self, forKey: .proposedCategory)
        proposedLabel = try container.decodeIfPresent(String.self, forKey: .proposedLabel)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        intensity = try container.decodeIfPresent(Int.self, forKey: .intensity) ?? 3
        timeframe = try container.decodeIfPresent(Timeframe.self, forKey: .timeframe) ?? .ongoing
        emotions = (try container.decodeIfPresent([String].self, forKey: .emotions) ?? [])
            .compactMap(Emotion.init(rawValue:))
        safety = try container.decodeIfPresent(SafetyFlag.self, forKey: .safety) ?? .none
        inputLanguage = try container.decodeIfPresent(String.self, forKey: .inputLanguage) ?? "en"
        skippedStyles = (
            try container.decodeIfPresent([Failable<SkippedStyle>].self, forKey: .skippedStyles) ?? []
        ).compactMap(\.value)
        matching = try container.decode(MatchingKey.self, forKey: .matching)
    }
}

/// Keeps one unrecognised element from throwing away the whole array.
struct Failable<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

struct FollowUpAnswer: Codable, Equatable, Sendable {
    let question: String
    let answer: String
}

struct ReframeRequest: Codable, Equatable, Sendable {
    let text: String
    let followUps: [FollowUpAnswer]
    let styles: [Style]?
    let model: LlmModel?

    private enum CodingKeys: String, CodingKey {
        case text
        case followUps
        case styles
        case model
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        if !followUps.isEmpty {
            try container.encode(followUps, forKey: .followUps)
        }
        try container.encodeIfPresent(styles, forKey: .styles)
        try container.encodeIfPresent(model, forKey: .model)
    }
}

struct ReframeResult: Codable, Equatable, Sendable {
    let style: Style
    let reframe: String
}

struct StoredReframeResult: Decodable, Equatable, Sendable {
    let style: Style
    let reframe: String
    let isFavorite: Bool
    let favoritedAt: String?

    private enum CodingKeys: String, CodingKey {
        case style
        case reframe
        case isFavorite
        case favoritedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decode(Style.self, forKey: .style)
        reframe = try container.decode(String.self, forKey: .reframe)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        favoritedAt = try container.decodeIfPresent(String.self, forKey: .favoritedAt)
    }
}

enum ReframeResponse: Decodable, Equatable, Sendable {
    /// Not ready to cook: the composer stays up and the user can answer or say more.
    case continueTurn(message: String, options: [String], safety: SafetyFlag)
    case ready(thought: String, thoughtOriginal: String?, results: [ReframeResult], meta: ReframeMeta)

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
        case options
        case safety
        case thought
        case thoughtOriginal
        case results
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "continue":
            self = .continueTurn(
                message: try container.decode(String.self, forKey: .message),
                options: try container.decodeIfPresent([String].self, forKey: .options) ?? [],
                safety: try container.decodeIfPresent(SafetyFlag.self, forKey: .safety) ?? .none
            )
        case "ready":
            self = .ready(
                thought: try container.decode(String.self, forKey: .thought),
                thoughtOriginal: try container.decodeIfPresent(String.self, forKey: .thoughtOriginal),
                results: try container.decode([ReframeResult].self, forKey: .results),
                meta: try container.decode(ReframeMeta.self, forKey: .meta)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown reframe kind \(kind)"
            )
        }
    }
}

struct StoredCardTag: Codable, Equatable, Sendable {
    let slug: String
    let label: String
}

struct StoredCardAuthor: Codable, Equatable, Sendable {
    let initials: String
}

struct StoredCard: Decodable, Equatable, Sendable {
    let id: String
    let thought: String
    let thoughtOriginal: String?
    let inputLanguage: String
    let category: ThoughtCategory
    let proposedCategory: String?
    let proposedLabel: String?
    let tags: [StoredCardTag]
    let intensity: Int
    let intensityBand: IntensityBand
    let timeframe: Timeframe
    let emotions: [Emotion]
    let safety: SafetyFlag
    let skippedStyles: [SkippedStyle]
    let matching: MatchingKey
    let results: [StoredReframeResult]
    let model: String
    let spotlightStyle: Style
    let isPublic: Bool
    let createdAt: String
    let isOwner: Bool
    let author: StoredCardAuthor

    private enum CodingKeys: String, CodingKey {
        case id
        case thought
        case thoughtOriginal
        case inputLanguage
        case category
        case proposedCategory
        case proposedLabel
        case tags
        case intensity
        case intensityBand
        case timeframe
        case emotions
        case safety
        case skippedStyles
        case matching
        case results
        case model
        case spotlightStyle
        case isPublic
        case createdAt
        case isOwner
        case author
    }

    var reframeMeta: ReframeMeta {
        ReframeMeta(
            category: category,
            proposedCategory: proposedCategory,
            proposedLabel: proposedLabel,
            tags: tags.map(\.slug),
            intensity: intensity,
            timeframe: timeframe,
            emotions: emotions,
            safety: safety,
            inputLanguage: inputLanguage,
            skippedStyles: skippedStyles,
            matching: matching
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        thought = try container.decode(String.self, forKey: .thought)
        thoughtOriginal = try container.decodeIfPresent(String.self, forKey: .thoughtOriginal)
        inputLanguage = try container.decodeIfPresent(String.self, forKey: .inputLanguage) ?? "en"
        category = try container.decode(ThoughtCategory.self, forKey: .category)
        proposedCategory = try container.decodeIfPresent(String.self, forKey: .proposedCategory)
        proposedLabel = try container.decodeIfPresent(String.self, forKey: .proposedLabel)
        tags = (try container.decodeIfPresent([Failable<StoredCardTag>].self, forKey: .tags) ?? [])
            .compactMap(\.value)
        intensity = try container.decodeIfPresent(Int.self, forKey: .intensity) ?? 3
        intensityBand = try container.decodeIfPresent(IntensityBand.self, forKey: .intensityBand) ?? .mid
        timeframe = try container.decodeIfPresent(Timeframe.self, forKey: .timeframe) ?? .ongoing
        emotions = (try container.decodeIfPresent([String].self, forKey: .emotions) ?? [])
            .compactMap(Emotion.init(rawValue:))
        safety = try container.decodeIfPresent(SafetyFlag.self, forKey: .safety) ?? .none
        skippedStyles = (
            try container.decodeIfPresent([Failable<SkippedStyle>].self, forKey: .skippedStyles) ?? []
        ).compactMap(\.value)
        results = (try container.decodeIfPresent([Failable<StoredReframeResult>].self, forKey: .results) ?? [])
            .compactMap(\.value)
        guard !results.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .results,
                in: container,
                debugDescription: "Stored card had no usable reframes"
            )
        }
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        spotlightStyle = try container.decode(Style.self, forKey: .spotlightStyle)
        isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        createdAt = try container.decode(String.self, forKey: .createdAt)
        isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner) ?? true
        author = try container.decodeIfPresent(StoredCardAuthor.self, forKey: .author)
            ?? StoredCardAuthor(initials: "JM")
        matching = try container.decodeIfPresent(MatchingKey.self, forKey: .matching)
            ?? MatchingKey(
                category: category,
                tags: tags.map(\.slug),
                intensityBand: intensityBand
            )
    }
}

struct CreateCardRequest: Encodable, Equatable, Sendable {
    let thought: String
    let thoughtOriginal: String?
    let results: [ReframeResult]
    let meta: ReframeMeta
    let model: String
    let spotlightStyle: Style

    private enum CodingKeys: String, CodingKey {
        case thought
        case thoughtOriginal
        case results
        case meta
        case model
        case spotlightStyle
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(thought, forKey: .thought)
        try container.encodeIfPresent(thoughtOriginal, forKey: .thoughtOriginal)
        try container.encode(results, forKey: .results)
        try container.encode(meta, forKey: .meta)
        try container.encode(model, forKey: .model)
        try container.encode(spotlightStyle, forKey: .spotlightStyle)
    }
}

struct PatchCardRequest: Encodable, Equatable, Sendable {
    var isFavorite: Bool?
    var style: Style?
    var isPublic: Bool?

    private enum CodingKeys: String, CodingKey {
        case isFavorite
        case style
        case isPublic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(isPublic, forKey: .isPublic)
    }
}

struct CardListResponse: Decodable, Equatable, Sendable {
    let cards: [StoredCard]

    private enum CodingKeys: String, CodingKey {
        case cards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([Failable<StoredCard>].self, forKey: .cards) ?? []
        cards = raw.compactMap(\.value)
    }
}

enum FeedHomeSectionKind: String, Decodable, Sendable {
    case category
    case emotion
}

/// One Home shelf. Ids point into `FeedHomeResponse.cards`, so a card that belongs to
/// one life domain and several moods is only sent once.
struct FeedHomeSection: Decodable, Equatable, Sendable {
    let kind: FeedHomeSectionKind
    let id: String
    let cardIds: [String]
}

struct FeedHomeResponse: Decodable, Equatable, Sendable {
    let cards: [StoredCard]
    let recent: [String]
    let sections: [FeedHomeSection]

    private enum CodingKeys: String, CodingKey {
        case cards
        case recent
        case sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cards = (try container.decodeIfPresent([Failable<StoredCard>].self, forKey: .cards) ?? [])
            .compactMap(\.value)
        recent = try container.decodeIfPresent([String].self, forKey: .recent) ?? []
        sections = (try container.decodeIfPresent([Failable<FeedHomeSection>].self, forKey: .sections) ?? [])
            .compactMap(\.value)
    }
}

enum ISO8601Dates {
    static func date(from raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
