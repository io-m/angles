import Foundation

struct CardsService: Sendable {
    /// A decision, privacy, and delete are one small row write. The 15s session default is the
    /// cook's network slack; here it only hides an unreachable server behind a long spinner.
    private static let writeTimeout: TimeInterval = 6

    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func create(_ body: CreateCardRequest) async throws -> StoredCard {
        try await client.post(path: "cards", body: body)
    }

    /// `saved` false is your own cards, true the cards you saved, nil both.
    func list(
        limit: Int,
        before: String? = nil,
        saved: Bool? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> CardListResponse {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let saved {
            queryItems.append(URLQueryItem(name: "saved", value: saved ? "true" : "false"))
        }
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        return try await client.get(path: "cards", queryItems: queryItems, timeout: timeout)
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

    /// One page of the stack. A missing `session` starts a new visit. `seen` names the cards
    /// this visit already handed out that the server cannot leave out on its own yet.
    func stack(
        limit: Int,
        session: String?,
        seen: [String],
        filter: StackFilter = StackFilter()
    ) async throws -> StackResponse {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if !filter.categories.isEmpty {
            let value = filter.categories.map(\.rawValue).sorted().joined(separator: ",")
            queryItems.append(URLQueryItem(name: "categories", value: value))
        }
        if !filter.emotions.isEmpty {
            let value = filter.emotions.map(\.rawValue).sorted().joined(separator: ",")
            queryItems.append(URLQueryItem(name: "emotions", value: value))
        }
        if let session {
            queryItems.append(URLQueryItem(name: "session", value: session))
        }
        if !seen.isEmpty {
            queryItems.append(URLQueryItem(name: "seen", value: seen.joined(separator: ",")))
        }
        return try await client.get(path: "stack", queryItems: queryItems)
    }

    func decide(id: String, _ body: DecisionRequest) async throws -> DecisionResponse {
        try await client.put(path: "cards/\(id)/decision", body: body, timeout: Self.writeTimeout)
    }

    func clearDecision(id: String) async throws {
        try await client.delete(path: "cards/\(id)/decision", timeout: Self.writeTimeout)
    }

    func follow(id: String) async throws -> FollowStateResponse {
        try await client.put(path: "users/\(id)/follow", timeout: Self.writeTimeout)
    }

    func unfollow(id: String) async throws -> FollowStateResponse {
        try await client.deleteJSON(path: "users/\(id)/follow", timeout: Self.writeTimeout)
    }

    func listAuthorCards(id: String, limit: Int, before: String? = nil) async throws -> AuthorCardsResponse {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        return try await client.get(path: "users/\(id)/cards", queryItems: queryItems)
    }

    func report(id: String, reason: ReportReason) async throws -> ReportStateResponse {
        try await client.post(
            path: "cards/\(id)/report",
            body: ReportCardRequest(reason: reason),
            timeout: Self.writeTimeout
        )
    }
}

private struct ReportCardRequest: Encodable {
    let reason: ReportReason
}
