import Foundation
import Testing
@testable import Angles

private final class RequestCaptureURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func inputs(
    sessionRestored: Bool = true,
    entitlementsReady: Bool = true,
    isSignedIn: Bool = true,
    isEntitled: Bool = false,
    serverTasteCompleted: Bool = false,
    membershipRequested: Bool = false
) -> AppGateInputs {
    AppGateInputs(
        sessionRestored: sessionRestored,
        entitlementsReady: entitlementsReady,
        isSignedIn: isSignedIn,
        isEntitled: isEntitled,
        serverTasteCompleted: serverTasteCompleted,
        membershipRequested: membershipRequested
    )
}

struct AppGateTests {
    @Test func waitsForSessionAndStoreKit() {
        #expect(AppGate.resolve(inputs(sessionRestored: false)) == .launching)
        #expect(AppGate.resolve(inputs(entitlementsReady: false)) == .launching)
        #expect(AppGate.resolve(inputs(sessionRestored: false, isEntitled: true)) == .launching)
    }

    @Test func signedOutIsAlwaysLogin() {
        #expect(AppGate.resolve(inputs(isSignedIn: false)) == .login)
        #expect(AppGate.resolve(inputs(isSignedIn: false, serverTasteCompleted: true)) == .login)
        #expect(AppGate.resolve(inputs(isSignedIn: false, membershipRequested: true)) == .login)
    }

    /// Logout clears the session in the same frame as StoreKit. Even if StoreKit has not dropped
    /// its unlock yet, the frame is Login — never Home, taste, or paywall.
    @Test func logoutSnapshotIsLoginEvenWhileStillEntitled() {
        let midLogout = inputs(isSignedIn: false, isEntitled: true, serverTasteCompleted: true)
        #expect(AppGate.resolve(midLogout) == .login)
        let untasted = inputs(isSignedIn: false, isEntitled: false, serverTasteCompleted: false)
        #expect(AppGate.resolve(untasted) == .login)
    }

    @Test func untastedUnpaidGetsTaste() {
        #expect(AppGate.resolve(inputs()) == .taste)
    }

    @Test func tastedUnpaidGetsPaywall() {
        #expect(AppGate.resolve(inputs(serverTasteCompleted: true)) == .paywall)
    }

    @Test func consumedUnsavedTasteRelaunchGetsPaywall() {
        let session = SessionBody(
            id: "00000000-0000-4000-8000-000000000001",
            initials: "JM",
            name: "Josip",
            tasteCompletedAt: nil,
            tasteConsumedAt: "2026-09-25T12:00:00.000Z",
            avatarUrl: nil
        )
        #expect(session.hasUsedTaste)
        #expect(
            AppGate.resolve(inputs(serverTasteCompleted: session.hasUsedTaste))
                == .paywall
        )
    }

    @Test func tasteRenewOpensPaywallBeforeTheTasteIsSaved() {
        #expect(AppGate.resolve(inputs(membershipRequested: true)) == .paywall)
    }

    /// A live subscription after Apple login is paid access, tasted or not.
    @Test func entitledLoginNeverSeesTasteOrPaywall() {
        for tasted in [false, true] {
            for requested in [false, true] {
                let result = AppGate.resolve(
                    inputs(isEntitled: true, serverTasteCompleted: tasted, membershipRequested: requested)
                )
                #expect(result == .home)
            }
        }
    }

    /// An ended membership never unlocks: expiry lands on paywall, or taste if the account is new.
    @Test func expiryLeavesHome() {
        #expect(AppGate.resolve(inputs(isEntitled: false, serverTasteCompleted: true)) == .paywall)
        #expect(AppGate.resolve(inputs(isEntitled: false, serverTasteCompleted: false)) == .taste)
    }
}

struct AuthCredentialsTests {
    @Test func clearsOnlyTheMatchingToken() {
        let credentials = AuthCredentials()
        credentials.bearerToken = "new"
        #expect(credentials.clear(ifMatching: "old") == false)
        #expect(credentials.bearerToken == "new")
        #expect(credentials.clear(ifMatching: "new") == true)
        #expect(credentials.bearerToken == nil)
    }

    @Test func doesNothingWhenAlreadySignedOut() {
        let credentials = AuthCredentials()
        #expect(credentials.clear(ifMatching: "old") == false)
        #expect(credentials.bearerToken == nil)
    }
}

struct AuditRegressionTests {
    @Test func reframeUsesTheExplicitIdempotencyKey() async {
        let requestID = UUID(uuidString: "00000000-0000-4000-8000-000000000123")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCaptureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(baseURL: URL(string: "https://angles.test"), session: session)
        let service = ReframeService(client: client)

        RequestCaptureURLProtocol.requestHandler = { request in
            #expect(
                request.value(forHTTPHeaderField: "Idempotency-Key")
                    == requestID.uuidString.lowercased()
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 409,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(#"{"error":"already completed","code":"REQUEST_ALREADY_COMPLETED"}"#.utf8)
            )
        }
        defer { RequestCaptureURLProtocol.requestHandler = nil }

        do {
            _ = try await service.refine(text: "A thought", requestID: requestID)
            Issue.record("Expected the stubbed conflict")
        } catch let APIError.httpStatus(code, payload, _) {
            #expect(code == 409)
            #expect(payload?.code == "REQUEST_ALREADY_COMPLETED")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test @MainActor func lowCreditWarningKeysAreAccountScoped() {
        let accountA = HomeViewModel.lowWarningDefaultsKey(
            userID: "00000000-0000-4000-8000-00000000000A"
        )
        let accountB = HomeViewModel.lowWarningDefaultsKey(
            userID: "00000000-0000-4000-8000-00000000000B"
        )
        #expect(accountA != accountB)
    }

    @Test @MainActor func subscriptionStatusDoesNotClaimRenewal() {
        #expect(StoreKitManager.activeUntilLine(for: nil) == "Active subscription")
        let line = StoreKitManager.activeUntilLine(for: Date(timeIntervalSince1970: 0))
        #expect(line.hasPrefix("Active until "))
        #expect(!line.contains("Renew"))
    }
}
