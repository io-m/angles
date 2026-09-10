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
private struct Failable<Wrapped: Decodable>: Decodable {
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
