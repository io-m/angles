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

    func listFeed(
        limit: Int,
        before: String? = nil,
        categories: Set<ThoughtCategory> = [],
        emotions: Set<Emotion> = []
    ) async throws -> [StoredCard] {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        let orderedCategories = ThoughtCategory.allCases.filter(categories.contains)
        if !orderedCategories.isEmpty {
            queryItems.append(
                URLQueryItem(
                    name: "categories",
                    value: orderedCategories.map(\.rawValue).joined(separator: ",")
                )
            )
        }
        let orderedEmotions = Emotion.allCases.filter(emotions.contains)
        if !orderedEmotions.isEmpty {
            queryItems.append(
                URLQueryItem(
                    name: "emotions",
                    value: orderedEmotions.map(\.rawValue).joined(separator: ",")
                )
            )
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
