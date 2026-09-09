import Foundation

struct ReframeService: Sendable {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func getReframes(text: String, styles: [Style]) async throws -> [ReframeResult] {
        let response: ReframeResponse = try await client.post(
            path: "reframe",
            body: ReframeRequest(text: text, styles: styles)
        )
        return response.results
    }
}
