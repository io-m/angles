import Foundation

/// Mirrors backend `src/types/index.ts`. Keep JSON keys in sync.

enum Style: String, Codable, CaseIterable, Sendable {
    case stoic
    case optimistic
    case humorous
    case toughLove = "tough_love"
}

struct ReframeRequest: Codable, Equatable, Sendable {
    let text: String
    let styles: [Style]
}

struct ReframeResult: Codable, Equatable, Sendable {
    let style: Style
    let reframe: String
}

struct ReframeResponse: Codable, Equatable, Sendable {
    let results: [ReframeResult]
}
