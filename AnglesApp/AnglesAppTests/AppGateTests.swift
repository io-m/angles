import Testing
@testable import Angles

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
