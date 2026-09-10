import Foundation

/// Mirrors backend `src/types/index.ts`. Keep JSON keys in sync.

enum Style: String, Codable, CaseIterable, Sendable {
    case stoic
    case optimistic
    case humorous
    case toughLove = "tough_love"
}

struct FollowUpAnswer: Codable, Equatable, Sendable {
    let question: String
    let answer: String
}

struct ReframeRequest: Codable, Equatable, Sendable {
    let text: String
    let followUps: [FollowUpAnswer]
}

struct ReframeResult: Codable, Equatable, Sendable {
    let style: Style
    let reframe: String
}

enum ReframeResponse: Codable, Equatable, Sendable {
    case clarify(question: String, options: [String])
    case ready(results: [ReframeResult])

    private enum CodingKeys: String, CodingKey {
        case kind
        case question
        case options
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "clarify":
            self = .clarify(
                question: try container.decode(String.self, forKey: .question),
                options: try container.decode([String].self, forKey: .options)
            )
        case "ready":
            self = .ready(
                results: try container.decode([ReframeResult].self, forKey: .results)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown reframe kind \(kind)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clarify(let question, let options):
            try container.encode("clarify", forKey: .kind)
            try container.encode(question, forKey: .question)
            try container.encode(options, forKey: .options)
        case .ready(let results):
            try container.encode("ready", forKey: .kind)
            try container.encode(results, forKey: .results)
        }
    }
}
