import Foundation

/// One logical cook. A retry sends the same pair, so a response lost in transit comes back
/// from the server instead of costing the taste or a second charge.
struct ReframeAttempt: Equatable, Sendable {
    let id: UUID
    /// 32 random bytes, unpadded base64url. The server seals the finished response under it
    /// and never stores it.
    let replayKey: String

    init(id: UUID = UUID(), replayKey: String = ReframeAttempt.newReplayKey()) {
        self.id = id
        self.replayKey = replayKey
    }

    static func newReplayKey() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct ReframeService: Sendable {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func refine(
        text: String,
        followUps: [FollowUpAnswer] = [],
        attempt: ReframeAttempt = ReframeAttempt()
    ) async throws -> ReframeResponse {
        try await client.post(
            path: "reframe",
            body: ReframeRequest(
                text: text,
                followUps: followUps,
                region: Self.deviceRegion()
            ),
            headers: Self.headers(for: attempt)
        )
    }

    func recook(_ recook: RecookRequest, attempt: ReframeAttempt = ReframeAttempt()) async throws -> ReframeResponse {
        try await client.post(
            path: "reframe",
            body: RecookRequestBody(recook: recook, region: Self.deviceRegion()),
            headers: Self.headers(for: attempt)
        )
    }

    private static func headers(for attempt: ReframeAttempt) -> [String: String] {
        [
            "Idempotency-Key": attempt.id.uuidString.lowercased(),
            "Replay-Key": attempt.replayKey,
        ]
    }

    /// Where the phone is set to, not the language typed. Numeric UN regions are left out.
    static func deviceRegion(_ locale: Locale = .current) -> String? {
        guard let code = locale.region?.identifier,
              code.count == 2,
              code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return nil
        }
        return code.uppercased()
    }
}
