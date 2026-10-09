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

/// What a failed cook means for the next step. A cook that never reached the server, or that
/// the server is still writing, is retried with the same attempt: the server either replays
/// the finished angles or restarts the dead attempt, and never charges twice.
enum ReframeFailureKind: Equatable, Sendable {
    /// The request may or may not have arrived: transport loss, a timeout, a bad gateway.
    case network
    /// The same attempt, or another cook of this account, is still being written.
    case running
    /// The provider could not write it. The attempt was never charged and may cook again.
    case provider
    /// The attempt finished earlier but its sealed result is gone. Only a new attempt helps.
    case finishedWithoutResult
    case other

    static func of(_ error: Error) -> ReframeFailureKind {
        if let urlError = error as? URLError, urlError.code != .cancelled {
            return .network
        }
        guard let apiError = error as? APIError else {
            return .other
        }
        switch apiError {
        case .network, .decoding:
            return .network
        case .invalidURL:
            return .other
        case .httpStatus(let status, let payload, _):
            switch payload?.code {
            case "OPERATION_RUNNING":
                return .running
            case "REQUEST_ALREADY_COMPLETED":
                return .finishedWithoutResult
            case "LLM_ERROR":
                return .provider
            default:
                // The proxy answers these when the API restarts or is overloaded.
                return payload == nil && [502, 503, 504].contains(status) ? .network : .other
            }
        }
    }
}

/// Runs one cook and quietly retries what is safe to retry, so a locked phone, a dropped
/// connection, or a slow provider reads as one longer "cooking" and not as an error.
struct ReframeRetry: Sendable {
    var maxElapsed: TimeInterval = 45
    var networkRetries = 2
    var waitRetries = 5
    var providerRetries = 1
    var networkPause: TimeInterval = 1.5
    var waitPause: TimeInterval = 2.5
    var providerPause: TimeInterval = 2
    var sleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }
    var now: @Sendable () -> Date = { Date() }

    func run(
        attempt first: ReframeAttempt,
        onNewAttempt: (ReframeAttempt) -> Void = { _ in },
        call: (ReframeAttempt) async throws -> ReframeResponse
    ) async throws -> ReframeResponse {
        let started = now()
        var attempt = first
        var networkLeft = networkRetries
        var waitLeft = waitRetries
        var providerLeft = providerRetries
        var restarted = false

        while true {
            do {
                return try await call(attempt)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
                guard now().timeIntervalSince(started) < maxElapsed else {
                    throw error
                }
                switch ReframeFailureKind.of(error) {
                case .network where networkLeft > 0:
                    networkLeft -= 1
                    try await sleep(networkPause)
                case .running where waitLeft > 0:
                    waitLeft -= 1
                    try await sleep(waitPause)
                case .provider where providerLeft > 0:
                    providerLeft -= 1
                    try await sleep(providerPause)
                case .finishedWithoutResult where !restarted:
                    restarted = true
                    attempt = ReframeAttempt()
                    onNewAttempt(attempt)
                default:
                    throw error
                }
            }
        }
    }
}

struct ReframeService: Sendable {
    /// The server gives a cook 13 s and answers within about 14, so the phone waits past that:
    /// a finished answer always has time to arrive. A 15 s limit sat 2 s from a slow cook.
    static let requestTimeout: TimeInterval = 25

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
            headers: Self.headers(for: attempt),
            timeout: Self.requestTimeout
        )
    }

    func recook(_ recook: RecookRequest, attempt: ReframeAttempt = ReframeAttempt()) async throws -> ReframeResponse {
        try await client.post(
            path: "reframe",
            body: RecookRequestBody(recook: recook, region: Self.deviceRegion()),
            headers: Self.headers(for: attempt),
            timeout: Self.requestTimeout
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
