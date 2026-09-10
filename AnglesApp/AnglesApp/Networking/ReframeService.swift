import Foundation

struct ReframeService: Sendable {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func refine(text: String, followUps: [FollowUpAnswer]) async throws -> ReframeResponse {
        try await client.post(
            path: "reframe",
            body: ReframeRequest(text: text, followUps: followUps)
        )
    }
}
