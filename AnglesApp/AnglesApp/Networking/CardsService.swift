import Foundation

struct CardsService: Sendable {
    /// Heart, privacy, and delete are one small row write. The 15s session default is the
    /// cook's network slack; here it only hides an unreachable server behind a long spinner.
    private static let writeTimeout: TimeInterval = 6

    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func create(_ body: CreateCardRequest) async throws -> StoredCard {
        try await client.post(path: "cards", body: body)
    }

    func list(limit: Int = 200) async throws -> [StoredCard] {
        let response: CardListResponse = try await client.get(
            path: "cards",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return response.cards
    }

    func get(id: String) async throws -> StoredCard {
        try await client.get(path: "cards/\(id)")
    }

    func patch(id: String, _ body: PatchCardRequest) async throws -> StoredCard {
        try await client.patch(path: "cards/\(id)", body: body, timeout: Self.writeTimeout)
    }

    func delete(id: String) async throws {
        try await client.delete(path: "cards/\(id)", timeout: Self.writeTimeout)
    }

    /// Home shelves are capped, so the style filter has to run server-side or a shelf
    /// would come back with fewer than `perSection` matching cards.
    func homeFeed(style: Style?, perSection: Int) async throws -> FeedHomeResponse {
        var queryItems = [URLQueryItem(name: "perSection", value: String(perSection))]
        if let style {
            queryItems.append(URLQueryItem(name: "style", value: style.rawValue))
        }
        return try await client.get(path: "feed/home", queryItems: queryItems)
    }

    func listFeed(
        limit: Int,
        before: String? = nil,
        category: ThoughtCategory? = nil,
        emotion: Emotion? = nil,
        style: Style? = nil
    ) async throws -> [StoredCard] {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        if let emotion {
            queryItems.append(URLQueryItem(name: "emotion", value: emotion.rawValue))
        }
        if let style {
            queryItems.append(URLQueryItem(name: "style", value: style.rawValue))
        }
        let response: CardListResponse = try await client.get(path: "feed", queryItems: queryItems)
        return response.cards
    }

    func saveFeedAngle(id: String, style: Style) async throws -> StoredCard {
        try await client.put(path: "feed/cards/\(id)/angles/\(style.rawValue)", timeout: Self.writeTimeout)
    }

    func unsaveFeedAngle(id: String, style: Style) async throws -> StoredCard {
        try await client.deleteJSON(
            path: "feed/cards/\(id)/angles/\(style.rawValue)",
            timeout: Self.writeTimeout
        )
    }

    func removeFromBoard(id: String) async throws {
        try await client.delete(path: "feed/cards/\(id)/saves", timeout: Self.writeTimeout)
    }
}
