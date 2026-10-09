import Foundation
import Testing
@testable import Angles

private final class Recorder: @unchecked Sendable {
    var pauses: [TimeInterval] = []
    var clock = Date(timeIntervalSince1970: 1_000)
}

@Suite struct ReframeRetryTests {
    private let usage = #"{"creditsUsed":0,"remaining":599,"granted":600,"resetsAt":null,"warning":"normal","creditCost":1,"plan":"membership"}"#

    private func response() throws -> ReframeResponse {
        let json = #"{"kind":"continue","message":"What happened?","options":[],"safety":"none","usage":\#(usage)}"#
        return try JSONDecoder().decode(ReframeResponse.self, from: Data(json.utf8))
    }

    private func http(_ status: Int, _ code: String?) -> APIError {
        let payload = code.map {
            APIErrorPayload(error: "x", code: $0, creditsRemaining: nil, creditsGranted: nil, resetsAt: nil)
        }
        return .httpStatus(status, payload, nil)
    }

    private func retry(_ recorder: Recorder) -> ReframeRetry {
        ReframeRetry(
            sleep: { seconds in
                recorder.pauses.append(seconds)
                recorder.clock = recorder.clock.addingTimeInterval(seconds)
            },
            now: { recorder.clock }
        )
    }

    @Test func aLostConnectionRetriesWithTheSameAttempt() async throws {
        let recorder = Recorder()
        let first = ReframeAttempt()
        var seen: [ReframeAttempt] = []
        let expected = try response()

        let result = try await retry(recorder).run(attempt: first) { attempt in
            seen.append(attempt)
            if seen.count < 3 {
                throw APIError.network("The network connection was lost.")
            }
            return expected
        }

        #expect(result == expected)
        #expect(seen == [first, first, first])
        #expect(recorder.pauses.count == 2)
    }

    @Test func aCookStillRunningIsWaitedOutOnTheSameAttempt() async throws {
        let recorder = Recorder()
        let first = ReframeAttempt()
        var seen: [ReframeAttempt] = []
        let expected = try response()

        let result = try await retry(recorder).run(attempt: first) { attempt in
            seen.append(attempt)
            if seen.count < 4 {
                throw self.http(409, "OPERATION_RUNNING")
            }
            return expected
        }

        #expect(result == expected)
        #expect(seen.allSatisfy { $0 == first })
        #expect(recorder.pauses == [2.5, 2.5, 2.5])
    }

    @Test func aFinishedAttemptWithoutAResultStartsOneFreshAttempt() async throws {
        let recorder = Recorder()
        let first = ReframeAttempt()
        var seen: [ReframeAttempt] = []
        var announced: [ReframeAttempt] = []
        let expected = try response()

        let result = try await retry(recorder).run(
            attempt: first,
            onNewAttempt: { announced.append($0) }
        ) { attempt in
            seen.append(attempt)
            if seen.count == 1 {
                throw self.http(409, "REQUEST_ALREADY_COMPLETED")
            }
            return expected
        }

        #expect(result == expected)
        #expect(seen.count == 2)
        #expect(seen[1] != first)
        #expect(announced == [seen[1]])
    }

    @Test func aSecondFinishedWithoutResultIsReportedNotLooped() async throws {
        let recorder = Recorder()
        var calls = 0

        await #expect(throws: APIError.self) {
            _ = try await self.retry(recorder).run(attempt: ReframeAttempt()) { _ in
                calls += 1
                throw self.http(409, "REQUEST_ALREADY_COMPLETED")
            }
        }
        #expect(calls == 2)
    }

    @Test func aProviderFailureGetsOneQuietRetry() async throws {
        let recorder = Recorder()
        var calls = 0

        await #expect(throws: APIError.self) {
            _ = try await self.retry(recorder).run(attempt: ReframeAttempt()) { _ in
                calls += 1
                throw self.http(500, "LLM_ERROR")
            }
        }
        #expect(calls == 2)
        #expect(recorder.pauses == [2])
    }

    @Test func aRejectedRequestIsNeverRetried() async throws {
        let recorder = Recorder()
        var calls = 0

        for code in ["VALIDATION_ERROR", "INSUFFICIENT_CREDITS", "SUBSCRIPTION_REQUIRED", "TASTE_LIMIT_REACHED"] {
            calls = 0
            await #expect(throws: APIError.self) {
                _ = try await self.retry(recorder).run(attempt: ReframeAttempt()) { _ in
                    calls += 1
                    throw self.http(400, code)
                }
            }
            #expect(calls == 1, "\(code)")
        }
        #expect(recorder.pauses.isEmpty)
    }

    @Test func cancellationStopsAtOnce() async throws {
        let recorder = Recorder()
        var calls = 0

        await #expect(throws: CancellationError.self) {
            _ = try await self.retry(recorder).run(attempt: ReframeAttempt()) { _ in
                calls += 1
                throw CancellationError()
            }
        }
        #expect(calls == 1)
    }

    @Test func stopsRetryingOnceTheBudgetIsSpent() async throws {
        let recorder = Recorder()
        var calls = 0
        var policy = retry(recorder)
        policy.maxElapsed = 4
        policy.networkRetries = 10
        policy.networkPause = 1.5

        await #expect(throws: APIError.self) {
            _ = try await policy.run(attempt: ReframeAttempt()) { _ in
                calls += 1
                throw APIError.network("timed out")
            }
        }
        // 1.5 s per pause, 4 s budget: the fourth failure lands past it.
        #expect(calls == 4)
    }

    @Test func gatewayErrorsAreTreatedLikeALostConnection() {
        for status in [502, 503, 504] {
            #expect(ReframeFailureKind.of(http(status, nil)) == .network, "\(status)")
        }
        #expect(ReframeFailureKind.of(http(500, "LLM_ERROR")) == .provider)
        #expect(ReframeFailureKind.of(http(400, "VALIDATION_ERROR")) == .other)
        #expect(ReframeFailureKind.of(APIError.decoding("bad")) == .network)
        #expect(ReframeFailureKind.of(URLError(.timedOut)) == .network)
        #expect(ReframeFailureKind.of(URLError(.cancelled)) == .other)
    }

    @Test func aCookGetsLongerThanTheServersDeadline() {
        // The server fails a cook at 13 s. The phone must outwait that or a finished answer
        // is thrown away on arrival.
        #expect(ReframeService.requestTimeout >= 20)
    }
}
