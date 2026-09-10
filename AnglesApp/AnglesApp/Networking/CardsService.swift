import Foundation

struct CardsService: Sendable {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func create(_ body: CreateCardRequest) async throws -> StoredCard {
        try await client.post(path: "cards", body: body)
    }

    func list(limit: Int = 100) async throws -> [StoredCard] {
        let response: CardListResponse = try await client.get(
            path: "cards",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return response.cards
    }

    func get(id: String) async throws -> StoredCard {
        try await client.get(path: "cards/\(id)")
    }

    func setFavorite(id: String, isFavorite: Bool) async throws -> StoredCard {
        try await client.patch(
            path: "cards/\(id)",
            body: PatchCardRequest(isFavorite: isFavorite)
        )
    }

    func delete(id: String) async throws {
        try await client.delete(path: "cards/\(id)")
    }
}
